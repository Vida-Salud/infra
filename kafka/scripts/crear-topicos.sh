#!/usr/bin/env bash
# Crea los tópicos declarados en topics.conf y reconcilia su configuración.
# Es idempotente: se puede ejecutar las veces que haga falta (docker compose run --rm kafka-init).
#   - Tópico inexistente  -> se crea con sus particiones, réplicas y configuración.
#   - Tópico ya existente -> se vuelve a aplicar la configuración (retención, cleanup.policy, ...).
set -euo pipefail

# En kafka-1 el broker ya ocupa el puerto JMX: las herramientas de línea de comandos no deben abrirlo.
unset JMX_PORT KAFKA_JMX_PORT KAFKA_JMX_OPTS
export KAFKA_HEAP_OPTS="-Xmx128m"

BOOTSTRAP="${BOOTSTRAP:-kafka-1:29092,kafka-2:29092,kafka-3:29092}"
ARCHIVO="${TOPICS_FILE:-/opt/vidasalud/topics.conf}"

echo "==> Esperando a los brokers (${BOOTSTRAP})"
until kafka-broker-api-versions --bootstrap-server "$BOOTSTRAP" >/dev/null 2>&1; do
  sleep 3
done

while IFS= read -r linea || [[ -n "$linea" ]]; do
  linea="${linea%$'\r'}"                       # tolera CRLF
  sin_espacios="${linea//[[:space:]]/}"
  if [[ -z "$sin_espacios" || "$sin_espacios" == \#* ]]; then
    continue                                   # línea vacía o comentario
  fi

  IFS='|' read -r nombre particiones replicas configs <<< "$sin_espacios"
  IFS=';' read -ra pares <<< "$configs"

  crear=()      # --config clave=valor (uno por configuración)
  alterar=""    # clave=valor,clave=[v1,v2]  (formato de kafka-configs)
  for par in "${pares[@]}"; do
    [[ -z "$par" ]] && continue
    crear+=(--config "$par")
    clave="${par%%=*}"
    valor="${par#*=}"
    [[ "$valor" == *,* ]] && valor="[$valor]"  # los valores con coma van entre corchetes
    alterar+="${alterar:+,}${clave}=${valor}"
  done

  echo "==> ${nombre}: particiones=${particiones} réplicas=${replicas} ${configs}"
  kafka-topics --bootstrap-server "$BOOTSTRAP" --create --if-not-exists \
    --topic "$nombre" --partitions "$particiones" --replication-factor "$replicas" "${crear[@]}"

  if [[ -n "$alterar" ]]; then
    kafka-configs --bootstrap-server "$BOOTSTRAP" --alter \
      --entity-type topics --entity-name "$nombre" --add-config "$alterar"
  fi
done < "$ARCHIVO"

echo "==> Topología aplicada:"
kafka-topics --bootstrap-server "$BOOTSTRAP" --describe --exclude-internal
