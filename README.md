# Self-hosted Matrix Stack Template

Reusable Docker template for a Matrix/Synapse backend, Element Web, coturn with TLS, AWS RDS PostgreSQL, and S3 media storage.

## Quick Start

```bash
git clone https://github.com/YOUR_USER/matrix-infra-test.git
cd matrix-infra-test
chmod +x install.sh setup.sh
./install.sh
```

The installer asks for your domains, public IP, RDS PostgreSQL settings, and S3 bucket. It writes `.env`, generates Synapse and Element configs, and can start the stack with Docker Compose.

If you prefer editing values manually:

```bash
cp .env.example .env
$EDITOR .env
./setup.sh
docker compose up -d --build
```

## Requirements

- Docker with the modern Compose plugin: `docker compose`
- Your shell user must be able to use Docker, or you must run Docker commands with `sudo`
- `envsubst` from `gettext-base`
- A PostgreSQL RDS instance reachable from the host
- An S3 bucket and AWS credentials available to the Synapse container environment/host role
- DNS records for `DOMAIN` and `TURN_DOMAIN`
- TLS certificates under `/etc/letsencrypt/live/$TURN_DOMAIN/` for coturn

Use DNS-only Cloudflare records for TURN. Cloudflare proxying is fine for the web domain when your reverse proxy is configured for it, but TURN traffic should not be proxied through Cloudflare.

## EC2 Docker Permission

If Docker says `permission denied while trying to connect to the docker API at unix:///var/run/docker.sock`, add your Ubuntu user to the Docker group:

```bash
sudo usermod -aG docker $USER
newgrp docker
docker compose up -d --build
```

If `newgrp docker` does not refresh the session, log out and SSH back in. To start immediately without changing groups, use:

```bash
sudo docker compose up -d --build
```

## What Gets Generated

`install.sh` and `setup.sh` generate local runtime files:

- `.env`
- `synapse/homeserver.yaml`
- `synapse/homeserver.log.config`
- `element-config.json`
- `synapse/media_store/`

The secret-bearing generated files are ignored by Git. Synapse generates `/data/signing.key` itself on first start. Do not commit generated config files, secrets, keys, database files, or media uploads.

## Media Uploads

`MAX_UPLOAD_SIZE` controls Synapse's upload limit. The default example value is `200M`.

If uploads fail for files or videos but small images sometimes work, check every layer in front of Synapse:

- Synapse: `MAX_UPLOAD_SIZE` in `.env`, then rerun `./setup.sh` and restart Synapse
- Reverse proxy: set the body limit at least as high, for example Nginx `client_max_body_size 200M;`
- Proxy timeouts: large uploads need longer read/send timeouts
- Nginx buffering: use `proxy_request_buffering off;` for the Matrix upload path or server
- Cloudflare: proxied HTTP uploads are subject to Cloudflare plan limits
- S3: the Synapse container needs working AWS credentials or an instance profile/IAM role

The template keeps a local media copy and writes to S3 asynchronously. That makes client uploads less likely to fail because of a temporary S3 delay.

## Ports

- Synapse listens on host port `8008`
- Element listens on host port `8080`
- coturn uses host networking and listens on `3478` and `5349`, with relay ports `49152-65535`

In production, put a reverse proxy in front of Synapse and Element and expose normal HTTPS ports for Matrix clients.

## Validation

```bash
./setup.sh
docker compose config
docker compose build synapse
docker compose up -d
docker compose ps
docker compose logs --tail=100 synapse
docker compose logs --tail=100 coturn
```

If you still have the legacy Python `docker-compose` 1.29.x installed, prefer `docker compose`. The old tool can fail during recreate with `KeyError: 'ContainerConfig'` even when the template is valid.
