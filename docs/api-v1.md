# API v1 de VidaSalud

La versión va en la URI: /api/v1/... Sube solo ante un cambio incompatible: quitar o
renombrar un campo, cambiar un tipo, una ruta o un código de estado. Agregar un campo
opcional o un endpoint no cambia la versión. Una versión no soportada responde 400.
Cuando exista la v2, la v1 responderá con los encabezados Deprecation y Sunset.

## Errores (application/problem+json, RFC 9457)
400 dato inválido o versión no soportada; si es de validación, trae "errores": {"campo": "mensaje"}
401 sin token · 403 rol insuficiente · 404 no existe · 409 regla de negocio

## appointments
GET  /api/v1/appointments?status=&from=&to=   Admin, Operador (todas); Cliente (las suyas)
POST /api/v1/appointments                     {paciente, servicio, box, fechaHora}
GET  /api/v1/appointments/{id}
PUT  /api/v1/appointments/{id}                {servicio, box, fechaHora}      Admin, Operador
PUT  /api/v1/appointments/{id}/status         {"status": "CONFIRMADA"}       Admin, Operador

## catalog
GET, POST /api/v1/catalog/services · GET, PUT /api/v1/catalog/services/{id}
GET, POST /api/v1/catalog/boxes?servicioId= · GET /api/v1/catalog/boxes/{id}
GET /api/v1/catalog/slots?date=2026-11-20&boxId=3   (reemplaza /cupos y /cupos/box/{boxId}/fecha/{fecha})
PUT /api/v1/catalog/slots/{id}                      {cuposDisponibles}

## report (solo Admin; datos que arma el consumidor de Kafka)
GET /api/v1/report/kpis?range=last24h            totalAtenciones, tiempoEsperaPromedioMinutos, atencionesPorHora, atencionesPorEstado
GET /api/v1/report/top-services?range=last7d&limit=5   {rango, desde, hasta, servicios: [{servicio, cantidad}]}
range: last24h | last7d | last30d (sin importar mayúsculas) · limit: 1 a 20

## audit (Admin, Auditor; solo lectura)
GET /api/v1/audit?usuario=&type=&atencionId=&from=2026-11-01&to=2026-11-30   (máximo 500 filas, más recientes primero)
GET /api/v1/audit/appointments/{id}              timeline de una atención, en orden cronológico

## kafka-admin (solo Admin; directo al servicio, puerto 8095, no pasa por el BFF)
GET /api/v1/kafka/cluster
GET /api/v1/kafka/topics · GET /api/v1/kafka/topics/{name}
POST /api/v1/kafka/topics {nombre, particiones, replicas, configs: {"retention.ms": "604800000"}}
PUT /api/v1/kafka/topics/{name}/configs {configs: {...}} · DELETE /api/v1/kafka/topics/{name}/configs/{key}
PUT /api/v1/kafka/topics/{name}/partitions {particiones}
DELETE /api/v1/kafka/topics/{name}                (409 para los tópicos del sistema)
GET /api/v1/kafka/consumer-groups · GET /api/v1/kafka/consumer-groups/{groupId}
POST /api/v1/kafka/consumer-groups/{groupId}/offsets/reset {topico, posicion: EARLIEST|LATEST}   (409 si el grupo tiene consumidores)

## rabbit-admin (solo Admin)
POST /api/v1/rabbit/queues {nombre} · DELETE /api/v1/rabbit/queues/{name}
POST /api/v1/rabbit/exchanges {nombre, tipo} · DELETE /api/v1/rabbit/exchanges/{name}
POST /api/v1/rabbit/bindings {exchange, queue, routingKey}
DELETE /api/v1/rabbit/bindings?exchange=&queue=&routingKey=
