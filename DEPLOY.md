# Deploying PantryChef on a VPS

Target: one Linux host running Docker Compose. Caddy serves the built React app
and proxies the API, issuing a certificate from its own local CA for now (the
"self-signed" phase). Swap in a domain and automatic HTTPS later without
touching the application images.

The database is about 500 MB on disk; the raw CSV and build files add another
~830 MB while you load. A 2 GB VPS is comfortable; 1 GB works if you lower
`DB_POOL_MAX` (see `.env.example`).

## 1. Prepare the host

```bash
sudo apt update
sudo apt install -y docker.io docker-compose-v2 postgresql-client rsync
sudo systemctl enable --now docker
```

Copy the repository to `/opt/pantrychef` (git clone or rsync). Everything below
assumes that directory.

## 2. Configure

```bash
cd /opt/pantrychef
cp .env.example .env
```

Edit `.env`:

```dotenv
POSTGRES_PASSWORD=<openssl rand -hex 24>
SITE_ADDRESS=203.0.113.10     # your VPS IP for now
CORS_ORIGIN=*
```

`SITE_ADDRESS` is the hostname Caddy answers on. An IP is fine; Caddy will put
its internal certificate on it, and browsers will warn until you trust that CA.

## 3. Start Postgres

```bash
docker compose up -d db
docker compose ps           # wait for "healthy"
```

The database port is bound to `127.0.0.1:5432` on purpose: the data load runs
over localhost, and the database is never exposed to the internet.

## 4. Load the catalogue

Generate the COPY files on a machine with the raw CSV (see the main README),
then copy only the small artefacts:

```bash
rsync -av --progress build/ you@vps:/opt/pantrychef/build/
```

On the VPS:

```bash
cd /opt/pantrychef
DATABASE_URL="postgres://pantry:YOUR_PASSWORD@127.0.0.1:5432/pantry" \
  bash db/load.sh
```

This applies migrations, truncates the four catalogue tables, loads them with
`COPY`, and runs `VACUUM ANALYZE`. Re-running it is safe, but it also clears
favourites and events through foreign-key cascades once those tables are in use.

## 5. Build and start everything

```bash
docker compose up -d --build
docker compose ps
```

First boot builds two Node images and generates the Caddy certificate. Watch it:

```bash
docker compose logs -f web api
```

Visit `https://YOUR_IP/`. The browser will show a certificate warning because
the CA is local. Accept it to continue, or import Caddy's root certificate
(`docker compose exec web cat /data/caddy/pki/authorities/local/root.crt`) into
your device/browser trust store.

Check the API through the proxy:

```bash
curl -k https://YOUR_IP/health
```

## 6. Updating

```bash
git pull
docker compose up -d --build
```

Schema changes are additive migrations in `db/migrations/`; run
`DATABASE_URL=... bash db/migrate.sh` after a deploy that adds one. A full data
refresh means re-running step 4 (and therefore regenerating `build/` from the
raw CSV).

## Backups

```bash
docker compose exec -T db pg_dump -U pantry pantry \
  | gzip > pantry-$(date +%F).sql.gz
```

Keep those off the VPS. The catalogue is reproducible from the CSV, but
accounts and favourites (once they exist) are not.

## Later: a real certificate

Once a domain points at the VPS:

1. Set `SITE_ADDRESS=pantry.example.com` in `.env`.
2. Replace `tls internal` with `tls you@example.com` in `deploy/Caddyfile`
   (or delete the line and let Caddy use ACME automatically).
3. `docker compose up -d web`.

Caddy fetches and renews the certificate on its own.

## Troubleshooting

- **API unhealthy**: `docker compose logs api`; usually a bad `DATABASE_URL` or
  the database is still initialising.
- **502 from Caddy**: the `api` container is not healthy yet; check `docker
  compose ps` and the API logs.
- **Data load is slow**: it is 3.5M rows over `COPY`; a minute or two is normal.
- **Out of memory during matching**: lower `DB_WORK_MEM` to `16MB` and
  `DB_POOL_MAX` to `4` in `.env`, then `docker compose up -d api`.
