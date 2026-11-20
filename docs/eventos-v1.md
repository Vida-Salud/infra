# Eventos v1 de VidaSalud (Kafka)

Kafka guarda **hechos** (algo que ya ocurrió) para que cualquiera los lea, ahora o después.
RabbitMQ sigue llevando **comandos** a un único consumidor (ver `mensajes-v1.md`). Los dos conviven:
appointments publica en ambos después del commit, a partir del mismo evento de dominio.

## Tópicos

| Tópico | Particiones | Réplicas | min.insync | cleanup.policy | Retención | Clave | Productor | Consumer groups |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `appointments.events` | 3 | 3 | 2 | `delete` | 7 días | `atencionId` | appointments | `report-kpis`, `vidasalud-audit` |
| `audit.timeline` | 3 | 3 | 2 | `compact,delete` | 30 días | `atencionId` | audit | `vidasalud-audit-timeline` |
| `appointments.events.report.DLT` | 3 | 3 | 2 | `delete` | 14 días | la original | report (error handler) | — (inspección en Kafka UI) |
| `appointments.events.audit.DLT` | 3 | 3 | 2 | `delete` | 14 días | la original | audit (error handler) | — |
| `audit.timeline.audit.DLT` | 3 | 3 | 2 | `delete` | 14 días | la original | audit (error handler) | — |

La fuente de verdad es `infra/kafka/topics.conf`; `kafka-init` la aplica al levantar el clúster y
`ms-vidasalud-kafka-admin` permite ajustarla en caliente. Los brokers tienen `auto.create.topics.enable=false`.

## `appointments.events` (type = `APPOINTMENT_CREATED` | `APPOINTMENT_STATUS_CHANGED`)

```json
{
  "version": 1,
  "eventId": "0b7f7c3e-4a51-4d36-9d0e-1f2a3b4c5d6e",
  "type": "APPOINTMENT_STATUS_CHANGED",
  "timestamp": "2026-11-16T13:00:00.123Z",
  "correlationId": "atencion-42",
  "traceId": "3b9f6c1a-0d2e-4f7b-8a51-c4e2d9f07a63",
  "payload": {
    "atencionId": 42, "servicio": "Dental", "box": "Box 3", "fechaHora": "2026-11-20T10:30:00",
    "estado": "CONFIRMADA", "estadoAnterior": "SOLICITADA",
    "actor":  { "id": "<oid de Azure AD>", "nombre": "Olga Operadora", "rol": "Operador" },
    "origen": { "servicio": "ms-vidasalud-appointments", "ip": "190.20.30.40" }
  }
}
```

`APPOINTMENT_CREATED` lleva `estadoAnterior: null` y `estado: "SOLICITADA"`. A diferencia de RabbitMQ, se publican
**todos** los estados. El evento no lleva el nombre del paciente ni datos clínicos. `origen.ip` es el valor de
`X-Forwarded-For` que manda el BFF (o la IP de la conexión si no viene). El BFF no reenvía la cabecera del cliente,
porque cualquiera puede inventarla: manda un único valor que determina él, usando `vidasalud.proxies-de-confianza`
para saber cuántos proxies hay delante (0 en local; 1 en AWS, detrás del API Gateway).

## `audit.timeline`

```json
{
  "version": 1, "eventId": "0b7f7c3e-...", "type": "APPOINTMENT_STATUS_CHANGED",
  "ocurridoEn": "2026-11-16T13:00:00.123Z", "atencionId": 42,
  "estadoAnterior": "SOLICITADA", "estado": "CONFIRMADA",
  "actorId": "<oid>", "actorNombre": "Olga Operadora", "actorRol": "Operador",
  "origenServicio": "ms-vidasalud-appointments", "origenIp": "190.20.30.40",
  "traceId": "3b9f6c1a-..."
}
```

## Reglas

- **Orden**: la clave de `appointments.events` y de `audit.timeline` es el `atencionId`; todos los eventos de una
  atención caen en la misma partición y se consumen en orden.
- **Compactación de `audit.timeline`**: con la clave `atencionId`, `compact` conserva el último estado conocido de
  cada atención y `delete` borra a los 30 días. El historial completo e inmutable está en Oracle (`AUD_EVENTO`,
  una fila por `eventId`), no en Kafka.
- **Entrega al menos una vez**: productores con `acks=all` + `enable.idempotence=true`; los consumidores
  confirman el offset después de procesar (`ack-mode: record`) y descartan duplicados por `eventId`
  (report: tabla `REPORT_EVENTO`; audit: clave primaria de `AUD_EVENTO`).
- **Versión**: el consumidor acepta `version` ausente o `1`; otra versión es un error permanente y va al DLT.
  Agregar un campo opcional no cambia la versión; los consumidores ignoran los campos desconocidos.
- **Serialización**: JSON sin cabeceras de tipo (`spring.json.add.type.headers=false`), así el contrato no depende
  de nombres de clases Java. report deserializa con `ErrorHandlingDeserializer` + `JacksonJsonDeserializer`; audit lee
  bytes y convierte en el listener. En ambos casos un JSON roto llega al DLT con sus bytes originales.
- **Errores**: inválido (JSON roto, campo obligatorio faltante, versión o estado desconocido) → DLT sin reintentos.
  Cualquier otro error → 3 reintentos (1 s, 2 s, 4 s) → DLT. El DLT agrega las cabeceras
  `kafka_dlt-exception-message`, `kafka_dlt-original-topic`, `kafka_dlt-original-partition` y `kafka_dlt-original-offset`.
