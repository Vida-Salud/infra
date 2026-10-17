# infra — VidaSalud

Archivos de despliegue con Docker Compose. Cada carpeta corresponde a una EC2 del caso.

| Archivo | Dónde se usa | Servicios |
|---|---|---|
| `apps/compose.yml` | Local (PC de desarrollo) | Oracle, appointments, notify, Mailpit, catalog, bff, frontend |
| `apps/compose.aws.yml` | **ec2-apps** (AWS) | Los mismos, con API Gateway, HTTPS y RabbitMQ en ec2-mq |
| `mq/compose.yml` | Local y **ec2-mq** (AWS) | Clúster RabbitMQ de 2 nodos con Management UI |

## Arquitectura en AWS

```
Navegador ──HTTPS──▶ ec2-apps: frontend (443)
          ──JWT───▶ API Gateway ──▶ ec2-apps: bff (8080) ──▶ appointments / catalog ──▶ Oracle
                                                                  │
                                         publica (AMQP, IP privada 5672/5673)
                                                                  ▼
                                      ec2-mq: rabbitmq-1 ◀──clúster──▶ rabbitmq-2
                                                                  │
                                                consume           ▼
                                      ec2-apps: notify ──SMTP──▶ Mailpit (bandeja web 8025)
```

- **ec2-apps** y **ec2-mq** están en la misma VPC y subred; se comunican por **IP privada**, que no cambia al reiniciar el laboratorio.
- Todos los contenedores usan `restart: always`: al reiniciar una EC2, vuelven a arrancar solos.

## Estructura esperada

Los repos de los microservicios deben estar al lado de `infra` (los `context` de `apps/` usan `../../`):

```
carpeta/
├── infra/
├── ms-vidasalud-appointments/
├── ms-vidasalud-notify/
├── ms-vidasalud-catalog/
├── ms-vidasalud-bff/
└── frontend-vidasalud/
```

## Levantar en local

RabbitMQ primero (esperar a que los dos nodos estén `healthy`):

```bash
cd mq
docker compose up -d
docker compose ps
```

Después los microservicios:

```bash
cd ../apps
docker compose up -d --build
```

## Desplegar en AWS

**ec2-mq** (Ubuntu, t2.small):

```bash
git clone https://github.com/Vida-Salud/infra.git
cd infra/mq
docker compose up -d
docker exec rabbitmq-1 rabbitmqctl cluster_status
```

**ec2-apps** (con los repos clonados al lado de `infra`):

```bash
cd infra/apps
docker compose -f compose.aws.yml up -d --build
```

Para actualizar un solo servicio sin tocar el resto (por ejemplo, después de un `git pull`):

```bash
docker compose -f compose.aws.yml up -d --build --no-deps notify
```

`compose.aws.yml` usa `name: vidasalud-deploy` para reutilizar los contenedores existentes. Oracle no tiene volumen: si se recreara su contenedor, se perderían los datos.

## Accesos

| Servicio | Local | AWS |
|---|---|---|
| Frontend | http://localhost:4200 | https://IP-ec2-apps |
| BFF | http://localhost:8090 | vía API Gateway |
| Bandeja de correos (Mailpit) | http://localhost:8025 | http://IP-ec2-apps:8025 (con usuario y clave) |
| RabbitMQ nodo 1 | http://localhost:15672 | http://IP-ec2-mq:15672 |
| RabbitMQ nodo 2 | http://localhost:15673 | http://IP-ec2-mq:15673 |

## Security Groups

| EC2 | Puerto | Origen | Uso |
|---|---|---|---|
| ec2-mq | 5672-5673 | IP privada de ec2-apps | AMQP (microservicios) |
| ec2-mq | 15672-15673 | Internet (con login) | Consola de RabbitMQ |
| ec2-mq | 22 | IP del administrador + EC2 Instance Connect | SSH |
| ec2-apps | 80, 443 | Internet | Frontend |
| ec2-apps | 8080 | Internet | BFF (API Gateway) |
| ec2-apps | 8025 | Internet (con login) | Bandeja de Mailpit |

El SMTP de Mailpit (1025) no se publica: solo lo usa notify por la red interna de Docker.

## Clúster RabbitMQ

- 2 nodos (`rabbitmq-1`, `rabbitmq-2`) unidos por `rabbitmq.conf` (`classic_config`) y la misma Erlang cookie.
- Los microservicios se conectan con `RABBITMQ_ADDRESSES` (lista de los 2 nodos): si uno cae, se reconectan al otro.
- Colas clásicas: la definición se comparte en el clúster; los mensajes viven en el nodo donde se creó la cola.

## Mailpit

Servidor SMTP de pruebas: notify envía los correos de verdad, Mailpit los captura y los muestra en una bandeja web, sin enviarlos a nadie. Si Mailpit está caído, notify reintenta con backoff y el mensaje termina en la DLQ `q.cmd.email.dlq`. En producción se reemplazaría por un servicio SMTP real (por ejemplo, Amazon SES) cambiando solo `MAIL_HOST`, `MAIL_PORT` y las credenciales.