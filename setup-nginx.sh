#!/bin/bash
set -eu

if [ ! -f .env ]; then
  echo ".env file not found. Run ./install.sh first."
  exit 1
fi

set -a
. ./.env
set +a

DOMAIN="${DOMAIN:?DOMAIN is required in .env}"
SERVER_NAME="${SERVER_NAME:-$DOMAIN}"
ELEMENT_DOMAIN="${ELEMENT_DOMAIN:-app.$DOMAIN}"
MAX_UPLOAD_SIZE="${MAX_UPLOAD_SIZE:-200M}"
export DOMAIN SERVER_NAME ELEMENT_DOMAIN MAX_UPLOAD_SIZE

if ! command -v sudo >/dev/null 2>&1; then
  echo "sudo is required to install and configure Nginx."
  exit 1
fi

echo "=== Matrix Nginx Setup ==="
echo "Matrix API domain: $DOMAIN"
echo "Element web domain: $ELEMENT_DOMAIN"
echo ""

if [ "$SERVER_NAME" != "$DOMAIN" ]; then
  echo "Warning: SERVER_NAME is '$SERVER_NAME' but DOMAIN is '$DOMAIN'."
  echo "This Nginx helper is simplest when SERVER_NAME and DOMAIN match."
  echo ""
fi

if ! command -v nginx >/dev/null 2>&1 || ! command -v certbot >/dev/null 2>&1 || ! command -v envsubst >/dev/null 2>&1; then
  echo "Installing nginx, certbot, and gettext-base..."
  sudo apt-get update
  sudo apt-get install -y nginx certbot python3-certbot-nginx gettext-base
fi

tmp_config="$(mktemp)"
envsubst '${DOMAIN} ${SERVER_NAME} ${ELEMENT_DOMAIN} ${MAX_UPLOAD_SIZE}' > "$tmp_config" <<'NGINXEOF'
server {
    listen 80;
    server_name ${ELEMENT_DOMAIN};

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

server {
    listen 80;
    server_name ${DOMAIN};

    client_max_body_size ${MAX_UPLOAD_SIZE};

    location = /.well-known/matrix/client {
        default_type application/json;
        add_header Access-Control-Allow-Origin * always;
        return 200 '{"m.homeserver":{"base_url":"https://${DOMAIN}"}}';
    }

    location = /.well-known/matrix/server {
        default_type application/json;
        return 200 '{"m.server":"${SERVER_NAME}:443"}';
    }

    location ~ ^/(?:_matrix|_synapse/client) {
        proxy_pass http://127.0.0.1:8008;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
        proxy_request_buffering off;
    }
}
NGINXEOF

sudo cp "$tmp_config" /etc/nginx/sites-available/matrix-chat
rm -f "$tmp_config"

sudo ln -sf /etc/nginx/sites-available/matrix-chat /etc/nginx/sites-enabled/matrix-chat
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl enable --now nginx
sudo systemctl reload nginx

echo "[+] Nginx HTTP proxy is ready."
echo ""
echo "Make sure DNS points these records to this EC2 public IP:"
echo "  $DOMAIN"
echo "  $ELEMENT_DOMAIN"
echo ""
echo "Make sure the EC2 security group allows inbound 80/tcp and 443/tcp."
echo ""
printf "Issue Let's Encrypt HTTPS certificates now? [y/N]: "
read -r issue_certs
case "$issue_certs" in
  y|Y|yes|YES)
    sudo certbot --nginx -d "$DOMAIN" -d "$ELEMENT_DOMAIN"
    ;;
  *)
    echo "Run later: sudo certbot --nginx -d $DOMAIN -d $ELEMENT_DOMAIN"
    ;;
esac

echo "=== Done ==="
