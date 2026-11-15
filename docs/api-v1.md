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

## rabbit-admin (solo Admin)
POST /api/v1/rabbit/queues {nombre} · DELETE /api/v1/rabbit/queues/{name}
POST /api/v1/rabbit/exchanges {nombre, tipo} · DELETE /api/v1/rabbit/exchanges/{name}
POST /api/v1/rabbit/bindings {exchange, queue, routingKey}
DELETE /api/v1/rabbit/bindings?exchange=&queue=&routingKey=
