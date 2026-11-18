# infra — VidaSalud

Archivos de despliegue con Docker Compose. Cada carpeta corresponde a una EC2 del caso.

| Archivo | Dónde se usa | Servicios |
|---|---|---|
| `apps/compose.yml` | Local (PC de desarrollo) | Oracle, appointments, notify, Mailpit, catalog, rabbit-admin, report, audit, kafka-admin, bff, frontend |
| `apps/compose.aws.yml` | **ec2-apps** (AWS) | Los mismos, con API Gateway, HTTPS y RabbitMQ en ec2-mq |
| `mq/compose.yml` | Local y **ec2-mq** (AWS) | Clúster RabbitMQ de 2 nodos con Management UI |
| `kafka/compose.yml` | Local (y **ec2-kafka** cuando se despliegue) | Clúster Kafka: 3 Zookeeper, 3 brokers, `kafka-init` (crea los tópicos) y Kafka UI |

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
├── ms-vidasalud-rabbit-admin/
├── ms-vidasalud-report/
├── ms-vidasalud-audit/
├── ms-vidasalud-kafka-admin/
└── frontend-vidasalud/
```

## Variables de entorno (`.env`)

Las contraseñas no están en el repo. Copia `apps/.env.example` a `apps/.env` y `mq/.env.example` a `mq/.env` y completa los valores (solo letras y números en las contraseñas). Los `.env` están en `.gitignore`; en AWS se copian con `scp`, nunca por git. `apps/.env` incluye `FRONTEND_URL` y `API_BASE_URL` (en AWS) y `NOTIFY_PERFIL`: vacío por defecto, `demo` enciende los pacientes `FALLA_TEMPORAL` y `FALLA_PERMANENTE` de notify para la demo de la DLQ.

## Levantar en local

RabbitMQ primero (esperar a que los dos nodos estén `healthy`):

```bash
cd mq
docker compose up -d
docker compose ps
```

Después Kafka (copia `kafka/.env.example` a `kafka/.env` y define `KAFKA_UI_PASS`). La primera vez tarda:
los 3 brokers esperan a que ZooKeeper tenga quórum y `kafka-init` crea los tópicos.

```bash
cd ../kafka
docker compose up -d
docker compose ps                  # zookeeper-1..3 y kafka-1..3 (healthy); kafka-init "exited (0)"
```

Después los microservicios:

```bash
cd ../apps
docker compose up -d --build
```

Para ver el balanceo del consumer group de reportería: `docker compose up -d --scale report=2` y revisar el grupo
`report-kpis` en Kafka UI (cada instancia tiene particiones distintas).

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

`compose.aws.yml` usa `name: vidasalud-deploy` para reutilizar los contenedores existentes. Oracle guarda sus datos en el volumen `oracle_data`: recrear el contenedor no los borra. Los servicios con healthcheck (`appointments`, `catalog`, `notify`, `rabbit-admin`, `bff`) informan `(healthy)` en `docker compose ps`; el BFF espera a appointments y catalog. En AWS, appointments, catalog y Oracle no se publican en el host (solo `expose`): para consultar la base, `docker exec -it vidasalud-oracle sqlplus vidasalud@//localhost/FREEPDB1`.

Los contratos están en `docs/api-v1.md` (HTTP), `docs/mensajes-v1.md` (RabbitMQ) y `docs/eventos-v1.md` (Kafka).
Las decisiones de diseño de Kafka están en `docs/kafka-diseno.md`.

`compose.aws.yml` todavía no incluye Kafka (no hay ec2-kafka): appointments arranca con `KAFKA_HABILITADO=false`
y no publica eventos. Para desplegarlo: levantar `infra/kafka` en una EC2 con `KAFKA_HOST` = su IP privada,
agregar report, audit y kafka-admin a `compose.aws.yml` y definir `KAFKA_BOOTSTRAP_SERVERS` con esa IP.

## Accesos

| Servicio | Local | AWS |
|---|---|---|
| Frontend | http://localhost:4200 | https://IP-ec2-apps |
| BFF | http://localhost:8090 | vía API Gateway |
| rabbit-admin | http://localhost:8093 | http://IP-ec2-apps:8093 (solo Admin, por Postman) |
| Bandeja de correos (Mailpit) | http://localhost:8025 | http://IP-ec2-apps:8025 (con usuario y clave) |
| RabbitMQ nodo 1 | http://localhost:15672 | http://IP-ec2-mq:15672 |
| RabbitMQ nodo 2 | http://localhost:15673 | http://IP-ec2-mq:15673 |
| Kafka UI | http://localhost:8080 (usuario y clave de `kafka/.env`) | http://IP-ec2-kafka:8080 |
| kafka-admin | http://localhost:8095 (solo Admin, por Postman) | — |
| audit (directo, para pruebas) | http://localhost:8096 | — |
| Kafka (clientes) | localhost:9092, 9093, 9094 | IP-privada-ec2-kafka:9092, 9093, 9094 |

## Security Groups

| EC2 | Puerto | Origen | Uso |
|---|---|---|---|
| ec2-mq | 5672-5673 | IP privada de ec2-apps | AMQP (microservicios) |
| ec2-mq | 15672-15673 | IP de cada integrante del equipo ("My IP") | Consola de RabbitMQ |
| ec2-mq | 22 | IP del administrador + EC2 Instance Connect | SSH |
| ec2-apps | 80, 443 | Internet | Frontend |
| ec2-apps | 8080 | Internet | BFF (API Gateway) |
| ec2-apps | 8025 | IP de cada integrante del equipo ("My IP") | Bandeja de Mailpit |
| ec2-apps | 8093 | IP de cada integrante (opcional) | rabbit-admin con Postman |
| ec2-kafka | 9092-9094 | IP privada de ec2-apps | Brokers Kafka (microservicios) |
| ec2-kafka | 8080 | IP de cada integrante del equipo ("My IP") | Kafka UI |
| ec2-kafka | 22 | IP del administrador + EC2 Instance Connect | SSH |

appointments (8081), catalog (8091) y Oracle (1521) no tienen regla: ya no se publican en el host.

El SMTP de Mailpit (1025) no se publica: solo lo usa notify por la red interna de Docker.

## Clúster RabbitMQ

- 2 nodos (`rabbitmq-1`, `rabbitmq-2`) unidos por `rabbitmq.conf` (`classic_config`) y la misma Erlang cookie.
- Los microservicios se conectan con `RABBITMQ_ADDRESSES` (lista de los 2 nodos): si uno cae, se reconectan al otro.
- Colas clásicas: la definición se comparte en el clúster; los mensajes viven en el nodo donde se creó la cola.

## Clúster Kafka

- **3 Zookeeper** (`zookeeper-1..3`): guardan los metadatos del clúster (qué brokers están vivos, quién es líder de cada partición). Con 3 nodos el quórum es 2, así que sigue funcionando si cae uno.
- **3 brokers** (`kafka-1..3`): guardan las particiones. Por defecto cada tópico nuevo tiene 3 particiones y 3 réplicas, y `min.insync.replicas=2`: con `acks=all` se puede caer un broker sin perder datos ni dejar de escribir.
- **Kafka UI** (puerto 8080, con usuario y clave de `kafka/.env`): muestra brokers, tópicos, particiones, mensajes, consumer groups, offsets y lag.
- `auto.create.topics.enable=false`: los tópicos se crean a propósito, con su configuración, y no al primer envío.
- **Topología** en `kafka/topics.conf` (tópico, particiones, réplicas, retención, `cleanup.policy`). El servicio `kafka-init` la aplica al levantar y es idempotente: `docker compose run --rm kafka-init` la vuelve a aplicar.
- Cada broker tiene un listener **interno** (`kafka-N:29092`, entre brokers, Kafka UI y kafka-init) y uno **externo** (9092, 9093 y 9094, para los microservicios). `KAFKA_HOST` en `kafka/.env` es la dirección que anuncian: `host.docker.internal` en el PC (sirve al IDE y a los contenedores de `apps`; con `localhost` los contenedores no encuentran al broker) y la IP privada de ec2-kafka en AWS.
- Necesita unos 3 GB de RAM: en AWS, una t2.medium o más.

Levantar (local o en ec2-kafka):

```bash
cd kafka
cp .env.example .env      # completar KAFKA_UI_PASS; en AWS, la IP privada de ec2-kafka en KAFKA_HOST
docker compose up -d
docker compose ps         # 3 zookeeper + 3 kafka (healthy), kafka-ui Up, kafka-init Exited (0)
```

Operaciones replicables:

```bash
# Tópicos, configuración, consumer groups, offsets y lag
docker compose exec kafka-1 bash /opt/vidasalud/scripts/inspeccionar.sh

# Reprocesar un tópico desde el inicio (con el consumidor detenido). Sin --execute es una simulación.
docker compose exec kafka-1 bash /opt/vidasalud/scripts/reiniciar-offsets.sh <grupo> <tópico> --execute
```

Los microservicios se conectan con `KAFKA_BOOTSTRAP_SERVERS=IP:9092,IP:9093,IP:9094`.

## Mailpit

Servidor SMTP de pruebas: notify envía los correos de verdad, Mailpit los captura y los muestra en una bandeja web, sin enviarlos a nadie. Si Mailpit está caído, notify reintenta con backoff y el mensaje termina en la DLQ `q.cmd.email.dlq`. En producción se reemplazaría por un servicio SMTP real (por ejemplo, Amazon SES) cambiando solo `MAIL_HOST`, `MAIL_PORT` y las credenciales.
