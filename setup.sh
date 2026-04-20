#!/bin/bash
set -eu

if [ ! -f .env ]; then
  echo ".env file not found"
  echo "Copy .env.example to .env and fill in real values first."
  exit 1
fi

if [ ! -f synapse/homeserver.yaml.template ]; then
  echo "synapse/homeserver.yaml.template not found"
  exit 1
fi

if [ ! -f element-config.json.template ]; then
  echo "element-config.json.template not found"
  exit 1
fi

if ! command -v envsubst >/dev/null 2>&1; then
  echo "envsubst not found. Install gettext-base."
  exit 1
fi

set -a
. ./.env
set +a

SERVER_NAME="${SERVER_NAME:-${DOMAIN:-}}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
export SERVER_NAME POSTGRES_PORT

required_vars="
DOMAIN
SERVER_NAME
TURN_DOMAIN
TURN_SECRET
PUBLIC_IP
POSTGRES_HOST
POSTGRES_DB
POSTGRES_USER
POSTGRES_PASSWORD
POSTGRES_PORT
S3_BUCKET
AWS_REGION
MAX_UPLOAD_SIZE
REGISTRATION_SHARED_SECRET
MACAROON_SECRET_KEY
FORM_SECRET
"

for name in $required_vars; do
  value="${!name:-}"
  if [ -z "$value" ]; then
    echo "$name is required in .env"
    exit 1
  fi
done

placeholder_values="
example.com
call.example.com
change_me
your-server-ip
your-rds-endpoint
your-bucket-name
your-region
"

for name in $required_vars; do
  value="${!name}"
  for placeholder in $placeholder_values; do
    if [ "$value" = "$placeholder" ]; then
      echo "$name still has placeholder value: $value"
      exit 1
    fi
  done
done

IFS=. read -r ip1 ip2 ip3 ip4 ip_extra <<EOF
$PUBLIC_IP
EOF

if [ -n "${ip_extra:-}" ] || [ -z "${ip1:-}" ] || [ -z "${ip2:-}" ] || [ -z "${ip3:-}" ] || [ -z "${ip4:-}" ]; then
  echo "PUBLIC_IP must be an IPv4 address, not: $PUBLIC_IP"
  exit 1
fi

for octet in "$ip1" "$ip2" "$ip3" "$ip4"; do
  case "$octet" in
    *[!0-9]* )
      echo "PUBLIC_IP must be an IPv4 address, not: $PUBLIC_IP"
      exit 1
      ;;
  esac

  if [ "$octet" -gt 255 ]; then
    echo "PUBLIC_IP must be an IPv4 address, not: $PUBLIC_IP"
    exit 1
  fi
done

if ! printf '%s\n' "$MAX_UPLOAD_SIZE" | grep -Eq '^[0-9]+([KMGkmg])?$'; then
  echo "MAX_UPLOAD_SIZE must be a size like 100M, 1G, or a byte count."
  exit 1
fi

for name in TURN_SECRET REGISTRATION_SHARED_SECRET MACAROON_SECRET_KEY FORM_SECRET POSTGRES_PASSWORD; do
  value="${!name}"
  if [ "${#value}" -lt 8 ]; then
    echo "$name should be at least 8 characters."
    exit 1
  fi
done

mkdir -p synapse/media_store
rm -rf element-config.json

envsubst < synapse/homeserver.yaml.template > synapse/homeserver.yaml
envsubst < element-config.json.template > element-config.json

cat > synapse/homeserver.log.config <<'LOGEOF'
version: 1

formatters:
  simple:
    format: "%(asctime)s %(name)s %(levelname)s %(message)s"

handlers:
  console:
    class: logging.StreamHandler
    formatter: simple
    stream: ext://sys.stdout

root:
  level: INFO
  handlers: [console]

disable_existing_loggers: false
LOGEOF

chmod 644 synapse/homeserver.yaml
chmod 644 synapse/homeserver.log.config
chmod 644 element-config.json
chmod 755 synapse/media_store 2>/dev/null || true

if command -v chown >/dev/null 2>&1; then
  chown 991:991 synapse/media_store 2>/dev/null || chmod 777 synapse/media_store 2>/dev/null || true
else
  chmod 777 synapse/media_store 2>/dev/null || true
fi

echo "[+] Generated:"
ls -l synapse/homeserver.yaml synapse/homeserver.log.config element-config.json
