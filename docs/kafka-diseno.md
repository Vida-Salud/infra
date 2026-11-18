# Kafka en VidaSalud: decisiones de diseño

## Por qué Kafka además de RabbitMQ

| | RabbitMQ (EP3) | Kafka (EP5) |
| --- | --- | --- |
| Qué transporta | Comandos: "envía este correo", "emite este ticket" | Hechos: "la atención 42 pasó a CONFIRMADA" |
| Consumidores | Uno por cola (notify) | Muchos grupos independientes (report, audit, los que vengan) |
| Después de consumir | El mensaje desaparece (ACK) | El evento queda retenido 7 días y se puede releer (reset de offsets) |
| Fallas | DLQ por cola | DLT por consumidor |

appointments no cambió su integración con RabbitMQ: el mismo evento de dominio
(`AtencionEstadoCambiadoEvent`, después del commit) lo escuchan dos adaptadores independientes,
`messaging/NotificacionListener` (RabbitMQ) y `messaging/kafka/EventosAtencionListener` (Kafka); `ArquitecturaTest`
comprueba que no dependen uno del otro. Si Kafka está caído,
la petición HTTP y los correos siguen funcionando: el publicador de Kafka registra el error y no lo propaga.

## Topología

```
appointments ──(clave atencionId)──▶ appointments.events (3 particiones, RF 3)
                                       │                  │
                     grupo report-kpis         grupo vidasalud-audit
                                       ▼                  ▼
                              ms-vidasalud-report   ms-vidasalud-audit ──(clave eventId)──▶ audit.timeline
                              (KPIs en Oracle)                                               │
                                                                        grupo vidasalud-audit-timeline
                                                                                             ▼
                                                                              ms-vidasalud-audit (AUD_EVENTO)
```

- **3 particiones**: el paralelismo máximo de un grupo; `concurrency: 3` da un hilo por partición. Con dos
  instancias de report (`docker compose up -d --scale report=2`) Kafka reparte las 3 particiones entre ellas
  (asignador `CooperativeStickyAssignor`: el rebalanceo no detiene a todos los consumidores).
- **3 réplicas + `min.insync.replicas=2` + `acks=all`**: se puede perder 1 broker sin perder escrituras confirmadas.
- **`appointments.events` con `delete` y 7 días**: alcanza para reconstruir la reportería ante una falla.
- **`audit.timeline` con `compact,delete` y 30 días**: la clave es el `eventId`; si una entrada se publica dos veces
  (reintento), la compactación deja una sola. `delete` evita que el tópico crezca para siempre; el historial
  permanente vive en Oracle (`AUD_EVENTO`).
- **DLT por consumidor** (`<tópico>.<consumidor>.DLT`): si report falla con un evento, audit no se entera y viceversa.
- **Grupos distintos para report y audit**: los dos reciben todos los eventos (publish-subscribe). Dentro de un
  grupo, cada partición la lee una sola instancia (balanceo de carga).
- **`vidasalud-audit-timeline` separado de `vidasalud-audit`**: permite reprocesar el timeline hacia Oracle
  (reset de offsets) sin volver a leer `appointments.events`.

## Infraestructura (`infra/kafka`)

- ZooKeeper x3 (quórum de 2) y Kafka x3 con Confluent Platform 7.9.8 = Apache Kafka 3.9, la última versión que
  funciona con ZooKeeper (Kafka 4.0 solo soporta KRaft). Los clientes de Spring Boot 4 (Kafka 4.1) son compatibles.
- Dos listeners por broker: `INTERNO` (`kafka-N:29092`, entre brokers, Kafka UI y kafka-init) y `EXTERNO`
  (`${KAFKA_HOST}:9092..9094`, microservicios e IDE).
- `kafka-init` crea y reconcilia los tópicos de `topics.conf`; `kafka-ui` (Kafbat UI, con login) muestra brokers,
  tópicos, mensajes, DLT y consumer groups con su lag.

## Administración

| Tarea | API (`ms-vidasalud-kafka-admin`, rol Admin) | Script (`infra/kafka/scripts`) |
| --- | --- | --- |
| Estado del clúster | `GET /api/v1/kafka/cluster` | `inspeccionar.sh` |
| Crear tópico con particiones, réplicas y configs | `POST /api/v1/kafka/topics` | `crear-topicos.sh` (desde `topics.conf`) |
| Listar / describir (líder, réplicas, ISR, configs) | `GET /api/v1/kafka/topics[/{name}]` | `inspeccionar.sh` |
| Cambiar retención, cleanup.policy, min.insync | `PUT /api/v1/kafka/topics/{name}/configs` | `crear-topicos.sh` (reconcilia) |
| Volver una config al valor del broker | `DELETE /api/v1/kafka/topics/{name}/configs/{key}` | — |
| Aumentar particiones | `PUT /api/v1/kafka/topics/{name}/partitions` | — |
| Eliminar tópico (no los del sistema) | `DELETE /api/v1/kafka/topics/{name}` | — |
| Grupos: estado, miembros, offsets, lag | `GET /api/v1/kafka/consumer-groups[/{groupId}]` | `inspeccionar.sh` |
| Reprocesar o saltar mensajes | `POST /api/v1/kafka/consumer-groups/{groupId}/offsets/reset` | `reiniciar-offsets.sh` |
