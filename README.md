# infra — VidaSalud

Archivos de despliegue con Docker Compose. Cada carpeta corresponde a una EC2 del caso.

| Carpeta | EC2 | Contenido |
|---|---|---|
| `apps/` | ec2-apps | Oracle, appointments, notify, catalog, bff, frontend |
| `mq/` | ec2-mq | Clúster RabbitMQ de 2 nodos con Management UI |

## Estructura esperada

Los repos de los microservicios deben estar al lado de `infra` (los `context` del compose usan `../../`):

```
carpeta/
├── infra/
├── ms-vidasalud-appointments/
├── ms-vidasalud-notify/
├── ms-vidasalud-catalog/
├── ms-vidasalud-bff/
└── frontend-vidasalud/
```

## Levantar (local)

1. RabbitMQ primero:
```bash
   cd mq
   docker compose up -d
   docker compose ps    # esperar a que rabbitmq-1 y rabbitmq-2 estén (healthy)
```
2. Microservicios:
```bash
   cd ../apps
   docker compose up -d --build
```

## Accesos

| Servicio | URL |
|---|---|
| Frontend | http://localhost:4200 |
| BFF | http://localhost:8090 |
| RabbitMQ nodo 1 | http://localhost:15672 |
| RabbitMQ nodo 2 | http://localhost:15673 |

## Clúster RabbitMQ

- 2 nodos (`rabbitmq-1`, `rabbitmq-2`) unidos por `rabbitmq.conf` (`classic_config`) y la misma Erlang cookie.
- Los microservicios se conectan con `RABBITMQ_ADDRESSES` (lista de los 2 nodos): si uno cae, se reconectan al otro.
- Colas clásicas: la definición se comparte en el clúster; los mensajes viven en el nodo donde se creó la cola.