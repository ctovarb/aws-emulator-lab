# Este script debe cargarse con: source scripts/env-emulator.sh

# 1. Limpiar variables estáticas que tienen precedencia sobre el archivo de credenciales del emulador
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE

# 2. Apuntar SDK, CLI y Terraform a los artefactos generados dinámicamente por aws-emulator
export AWS_ENDPOINT_URL="https://127.0.0.1:9297"
export AWS_SHARED_CREDENTIALS_FILE="${HOME}/.aws/emulator/9297/emulator_credentials"
export AWS_CONFIG_FILE="${HOME}/.aws/emulator/9297/config"
export AWS_CA_BUNDLE="${HOME}/.aws/emulator/9297/ca.pem"
export SSL_CERT_FILE="${HOME}/.aws/emulator/9297/ca.pem"
export REQUESTS_CA_BUNDLE="${HOME}/.aws/emulator/9297/ca.pem"

# 3. Flags obligatorios de compatibilidad local
export AWS_EC2_METADATA_DISABLED="true"
export AWS_DISABLE_HOST_PREFIX_INJECTION="true"
export AWS_REGION="us-east-1"
export AWS_DEFAULT_REGION="us-east-1"

echo "[OK] Entorno configurado hacia AWS Emulator (127.0.0.1:9297)."
echo "     Credenciales: ${AWS_SHARED_CREDENTIALS_FILE}"
echo "     CA Bundle:    ${AWS_CA_BUNDLE}"
export AWS_PAGER=""
