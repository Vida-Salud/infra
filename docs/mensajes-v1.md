# Mensajes v1 de VidaSalud (RabbitMQ)

appointments publica comandos con un envelope JSON; ms-vidasalud-notify los consume.

## Envelope

```json
{
  "version": 1,
  "eventId": "6f1c2b0e-8a4d-4c1e-9f0b-2d7e5a3c9b11",
  "type": "email.confirmada",
  "timestamp": "2026-11-14T15:02:11.482Z",
  "correlationId": "atencion-42",
  "traceId": "3b9f6c1a-0d2e-4f7b-8a51-c4e2d9f07a63",
  "data": {
    "atencionId": 42, "paciente": "Ana Pérez", "servicio": "Dental",
    "box": "Box 3", "fechaHora": "2026-11-20T10:30:00", "estado": "CONFIRMADA"
  }
}
```

## Reglas de versión

- El productor siempre envía `version` (entero). La versión actual es 1.
- El consumidor acepta `version` ausente (mensaje anterior a este contrato) o `1`.
- Cualquier otra versión es un error permanente: NACK sin requeue y el mensaje va a la DLQ de su cola.
- Agregar un campo opcional no cambia la versión; el consumidor ignora los campos que no conoce.
- `traceId` es el `X-Trace-Id` de la petición HTTP que originó el cambio de estado y aparece en los logs de bff, appointments y notify.

## Mensajes por tipo

| Estado | Exchange | Routing key | `type` | Cola |
| --- | --- | --- | --- | --- |
| CONFIRMADA | `cmd.topic` | `email.confirmada` | `email.confirmada` | `q.cmd.email` |
| EN_ESPERA | `cmd.direct` | `admission.ticket` | `admission.ticket` | `q.cmd.admission` |
| EN_ESPERA | `cmd.topic` | `email.llamado-box` | `email.llamado-box` | `q.cmd.email` |
| CERRADA | `cmd.direct` | `record.gen` | `record.gen` | `q.cmd.record` |
| CERRADA | `cmd.topic` | `email.cierre` | `email.cierre` | `q.cmd.email` |
| CANCELADA | `cmd.fanout` | (ninguna) | `atencion.cancelada` | `q.cmd.email` y `q.cmd.admission` |

## Colas

Las colas de trabajo tienen `x-message-ttl` de 10 minutos y `x-max-length` 1000; los mensajes rechazados, expirados o desbordados van al DLX `cmd.dead.dlx` y a la DLQ de la cola (TTL de 24 h, sin consumidor).
