#!/usr/bin/env bash
set -euo pipefail

EMULATOR_PORT=9297
EMULATOR_DIR="${HOME}/.aws/emulator/${EMULATOR_PORT}"
CA_CERT="${EMULATOR_DIR}/ca.pem"
HEALTH_URL="https://127.0.0.1:${EMULATOR_PORT}/__admin/health"
LOG_FILE="/tmp/aws-emulator.log"

echo "[INFO] Verificando procesos previos de aws-emulator..."
if pgrep -f "aws-emulator" >/dev/null; then
  echo "[INFO] Deteniendo instancia existente para regenerar estado limpio..."
  pkill -f "aws-emulator" || true
  sleep 2
fi

echo "[INFO] Iniciando aws-emulator en 0.0.0.0:${EMULATOR_PORT}..."
# -b / --bind enlaza a 0.0.0.0 para que los Pods de kind alcancen el host en la Fase 4
# --telemetry off desactiva el envío de telemetría anónima
nohup aws-emulator -b 0.0.0.0 -p "${EMULATOR_PORT}" --telemetry off >"${LOG_FILE}" 2>&1 &
EMULATOR_PID=$!

echo "[INFO] Esperando health-check en ${HEALTH_URL}..."
for i in $(seq 1 30); do
  if ! kill -0 "${EMULATOR_PID}" 2>/dev/null; then
    echo "[ERROR] El proceso aws-emulator falló al iniciar. Revisa el log:"
    cat "${LOG_FILE}"
    exit 1
  fi

  if [[ -f "${CA_CERT}" ]] && curl -sf --cacert "${CA_CERT}" "${HEALTH_URL}" >/dev/null 2>&1; then
    echo "[OK] aws-emulator activo (PID: ${EMULATOR_PID}) y respondiendo en https://127.0.0.1:${EMULATOR_PORT}"
    exit 0
  fi
  sleep 1
done

echo "[ERROR] Timeout esperando que aws-emulator responda en ${HEALTH_URL}"
cat "${LOG_FILE}"
exit 1
