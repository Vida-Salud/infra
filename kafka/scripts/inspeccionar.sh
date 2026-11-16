#!/usr/bin/env bash
# Muestra el estado de la plataforma: tópicos, su configuración y los grupos de consumidores.
#   docker compose exec kafka-1 bash /opt/vidasalud/scripts/inspeccionar.sh
set -uo pipefail

# En kafka-1 el broker ya ocupa el puerto JMX: las herramientas de línea de comandos no deben abrirlo.
unset JMX_PORT KAFKA_JMX_PORT KAFKA_JMX_OPTS
export KAFKA_HEAP_OPTS="-Xmx128m"

BOOTSTRAP="${BOOTSTRAP:-kafka-1:29092,kafka-2:29092,kafka-3:29092}"

echo "===== TÓPICOS (particiones, líder, réplicas, ISR) ====="
kafka-topics --bootstrap-server "$BOOTSTRAP" --describe --exclude-internal

echo
echo "===== CONFIGURACIÓN POR TÓPICO (retención, cleanup.policy, min.insync.replicas) ====="
for topico in $(kafka-topics --bootstrap-server "$BOOTSTRAP" --list --exclude-internal); do
  kafka-configs --bootstrap-server "$BOOTSTRAP" --describe --entity-type topics --entity-name "$topico"
done

echo
echo "===== GRUPOS DE CONSUMIDORES: estado ====="
kafka-consumer-groups --bootstrap-server "$BOOTSTRAP" --describe --all-groups --state || true

echo
echo "===== GRUPOS DE CONSUMIDORES: offsets y lag por partición ====="
kafka-consumer-groups --bootstrap-server "$BOOTSTRAP" --describe --all-groups || true

echo
echo "===== GRUPOS DE CONSUMIDORES: miembros y particiones asignadas ====="
kafka-consumer-groups --bootstrap-server "$BOOTSTRAP" --describe --all-groups --members --verbose || true
