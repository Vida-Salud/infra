#!/usr/bin/env bash
# Reposiciona un grupo de consumidores al inicio de un tópico para reprocesarlo (replay).
# Kafka solo lo permite con el grupo inactivo: detén antes el microservicio consumidor.
#
#   docker compose exec kafka-1 bash /opt/vidasalud/scripts/reiniciar-offsets.sh <grupo> <tópico>            # simulación
#   docker compose exec kafka-1 bash /opt/vidasalud/scripts/reiniciar-offsets.sh <grupo> <tópico> --execute  # aplica
set -euo pipefail

# En kafka-1 el broker ya ocupa el puerto JMX: las herramientas de línea de comandos no deben abrirlo.
unset JMX_PORT KAFKA_JMX_PORT KAFKA_JMX_OPTS
export KAFKA_HEAP_OPTS="-Xmx128m"

BOOTSTRAP="${BOOTSTRAP:-kafka-1:29092,kafka-2:29092,kafka-3:29092}"

if [[ $# -lt 2 ]]; then
  echo "Uso: $0 <grupo> <tópico> [--execute]" >&2
  exit 1
fi

MODO="--dry-run"
if [[ "${3:-}" == "--execute" ]]; then
  MODO="--execute"
fi

kafka-consumer-groups --bootstrap-server "$BOOTSTRAP" \
  --group "$1" --topic "$2" --reset-offsets --to-earliest "$MODO"
