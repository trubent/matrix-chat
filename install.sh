#!/bin/bash
set -eu

echo "=== Matrix Infra Installer ==="
echo "This creates .env, renders config templates, and can start Docker Compose."
echo ""

if [ -f .env ]; then
  printf ".env already exists. Overwrite it? [y/N]: "
  read -r overwrite
  case "$overwrite" in
    y|Y|yes|YES) ;;
    *)
      echo "Keeping existing .env. Running setup with current values."
      ./setup.sh
      exit 0
      ;;
  esac
fi

prompt_required() {
  label="$1"
  var_name="$2"
  while :; do
    printf "%s: " "$label"
    read -r value
    if [ -n "$value" ]; then
      printf -v "$var_name" '%s' "$value"
      return
    fi
    echo "Value is required."
  done
}

prompt_default() {
  label="$1"
  default="$2"
  var_name="$3"
  printf "%s [%s]: " "$label" "$default"
  read -r value
  if [ -z "$value" ]; then
    value="$default"
  fi
  printf -v "$var_name" '%s' "$value"
}

prompt_secret() {
  label="$1"
  var_name="$2"
  printf "%s (leave blank to generate): " "$label"
  stty -echo 2>/dev/null || true
  read -r value
  stty echo 2>/dev/null || true
  echo ""
  if [ -z "$value" ]; then
    value="$(generate_secret)"
  fi
  printf -v "$var_name" '%s' "$value"
}

generate_secret() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
  else
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 64
    echo ""
  fi
}

check_docker_compose() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "Docker is not installed or not in PATH."
    echo "Install Docker first, then run: docker compose up -d --build"
    return 1
  fi

  if ! docker compose version >/dev/null 2>&1; then
    echo "Docker Compose plugin is not available."
    echo "Install the modern Docker Compose plugin, then run: docker compose up -d --build"
    return 1
  fi

  if ! docker compose ps >/dev/null 2>&1; then
    if command -v sudo >/dev/null 2>&1 && ! sudo docker ps >/dev/null 2>&1; then
      echo "Docker is installed, but the Docker daemon is not running."
      echo ""
      echo "On Ubuntu/EC2, start it with:"
      echo "  sudo systemctl enable --now docker"
      echo "  sudo systemctl status docker"
      echo ""
      echo "Then run:"
      echo "  docker compose up -d --build"
      return 1
    fi

    echo "Docker is installed, but this user cannot access the Docker daemon."
    echo ""
    echo "On Ubuntu/EC2, fix it with:"
    echo "  sudo usermod -aG docker \$USER"
    echo "  newgrp docker"
    echo ""
    echo "Or log out and SSH back in, then run:"
    echo "  docker compose up -d --build"
    echo ""
    echo "If you need to start immediately, you can run:"
    echo "  sudo docker compose up -d --build"
    return 1
  fi

  return 0
}

prompt_required "Main Matrix domain (example.com)" DOMAIN
prompt_default "Matrix server name" "$DOMAIN" SERVER_NAME
prompt_required "TURN domain (turn.example.com)" TURN_DOMAIN
prompt_required "Server public IPv4 address" PUBLIC_IP
echo ""

prompt_required "PostgreSQL host/RDS endpoint" POSTGRES_HOST
prompt_default "PostgreSQL database" "synapse" POSTGRES_DB
prompt_default "PostgreSQL user" "synapse" POSTGRES_USER
prompt_default "PostgreSQL port" "5432" POSTGRES_PORT
prompt_default "PostgreSQL SSL mode" "require" POSTGRES_SSLMODE
prompt_secret "PostgreSQL password" POSTGRES_PASSWORD
echo ""

prompt_required "S3 bucket" S3_BUCKET
prompt_required "AWS region" AWS_REGION
prompt_default "Max upload size" "200M" MAX_UPLOAD_SIZE
echo ""

prompt_secret "TURN shared secret" TURN_SECRET
REGISTRATION_SHARED_SECRET="$(generate_secret)"
MACAROON_SECRET_KEY="$(generate_secret)"
FORM_SECRET="$(generate_secret)"

cat > .env <<EOF
DOMAIN=$DOMAIN
SERVER_NAME=$SERVER_NAME

TURN_DOMAIN=$TURN_DOMAIN
TURN_SECRET=$TURN_SECRET
PUBLIC_IP=$PUBLIC_IP

POSTGRES_HOST=$POSTGRES_HOST
POSTGRES_DB=$POSTGRES_DB
POSTGRES_USER=$POSTGRES_USER
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_PORT=$POSTGRES_PORT
POSTGRES_SSLMODE=$POSTGRES_SSLMODE

S3_BUCKET=$S3_BUCKET
AWS_REGION=$AWS_REGION
MAX_UPLOAD_SIZE=$MAX_UPLOAD_SIZE

REGISTRATION_SHARED_SECRET=$REGISTRATION_SHARED_SECRET
MACAROON_SECRET_KEY=$MACAROON_SECRET_KEY
FORM_SECRET=$FORM_SECRET
EOF

chmod 600 .env
echo "[+] .env created"

./setup.sh

printf "Start the stack now with docker compose up -d --build? [y/N]: "
read -r start_now
case "$start_now" in
  y|Y|yes|YES)
    if check_docker_compose; then
      docker compose up -d --build
      echo "[+] Stack started"
    else
      echo "Config files are ready. Start the stack after fixing Docker access."
    fi
    ;;
  *)
    echo "Run manually when ready: docker compose up -d --build"
    ;;
esac

echo "=== Done ==="
