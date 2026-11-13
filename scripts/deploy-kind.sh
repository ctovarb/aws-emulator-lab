#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="aws-emulator-lab"
EMULATOR_DIR="${HOME}/.aws/emulator/9297"
IMAGE_TAR="/tmp/order-processor-local.tar"

# Forzar proveedor Podman si existe en el sistema o si DOCKER_HOST apunta a podman.sock
if command -v podman >/dev/null 2>&1 && [[ "${DOCKER_HOST:-}" == *"podman"* || -z "${DOCKER_HOST:-}" ]]; then
  CONTAINER_CLI="podman"
  export KIND_EXPERIMENTAL_PROVIDER="podman"
else
  CONTAINER_CLI="docker"
fi

echo "[INFO] 1. Construyendo imagen con ${CONTAINER_CLI} (localhost/order-processor:local)..."
if [[ "${CONTAINER_CLI}" == "podman" ]]; then
  podman build -t localhost/order-processor:local ./app
  rm -f "${IMAGE_TAR}"
  podman save -o "${IMAGE_TAR}" localhost/order-processor:local
else
  docker build --load -t localhost/order-processor:local ./app
  rm -f "${IMAGE_TAR}"
  docker save -o "${IMAGE_TAR}" localhost/order-processor:local
fi

echo "[INFO] 2. Verificando clúster kind '${CLUSTER_NAME}'..."
if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  # Ejecutamos dentro de un scope de systemd de usuario con Delegate=yes para sesiones rootless activas
  systemd-run --user --scope -p Delegate=yes kind create cluster --config k8s/kind-config.yaml
else
  echo "[INFO] El clúster '${CLUSTER_NAME}' ya existe."
fi

echo "[INFO] 3. Cargando archivo de imagen dentro del nodo de kind..."
kind load image-archive "${IMAGE_TAR}" --name "${CLUSTER_NAME}"
rm -f "${IMAGE_TAR}"

echo "[INFO] 4. Resolviendo IP del host accesible desde el contenedor kind..."
if [[ "${CONTAINER_CLI}" == "podman" ]]; then
  HOST_GATEWAY_IP=$(podman exec "${CLUSTER_NAME}-control-plane" getent hosts host.containers.internal | awk '{print $1}' | head -n1 || true)
  if [[ -z "${HOST_GATEWAY_IP}" ]]; then
    HOST_GATEWAY_IP=$(podman network inspect kind --format '{{(index .Subnets 0).Gateway}}')
  fi
else
  HOST_GATEWAY_IP=$(docker network inspect kind -f '{{(index .IPAM.Config 0).Gateway}}')
fi
echo "[INFO] IP del host detectada para el túnel: ${HOST_GATEWAY_IP}"

echo "[INFO] 5. Verificando regla de firewalld en Fedora para permitir tráfico al puerto 9297..."
if systemctl is-active --quiet firewalld; then
  sudo firewall-cmd --add-port=9297/tcp 2>/dev/null || true
fi

echo "[INFO] 6. Sincronizando Secret 'aws-emulator-runtime' (CA + Credenciales efímeras)..."
kubectl create secret generic aws-emulator-runtime \
  --from-file=ca.pem="${EMULATOR_DIR}/ca.pem" \
  --from-file=emulator_credentials="${EMULATOR_DIR}/emulator_credentials" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "[INFO] 7. Desplegando manifiestos de Kubernetes..."
sed "s/__HOST_GATEWAY_IP__/${HOST_GATEWAY_IP}/g" k8s/deployment.yaml | kubectl apply -f -

echo "[INFO] 8. Reiniciando rollout y esperando que el Pod esté Ready..."
kubectl rollout restart deployment/order-processor
kubectl rollout status deployment/order-processor --timeout=90s

echo "[OK] Despliegue en kind completado y conectado a AWS Emulator."
