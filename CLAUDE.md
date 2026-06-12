# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Dockerized WordPress installation serving as a headless CMS backend (API-first) for a Next.js frontend. Three services: WordPress + MariaDB + Redis, orchestrated via Docker Compose on a bridge network (`food-inno-network`).

## Commands

```bash
# Start all services
docker-compose up -d

# Stop all services
docker-compose down

# View running containers
docker-compose ps

# Follow logs (all services)
docker-compose logs -f

# Access WordPress container shell
docker exec -it food-inno bash

# Access database
docker exec -it food-inno-db mysql -u $MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE

# Test Redis
docker exec -it food-inno-redis redis-cli ping

# Check resource usage
docker stats food-inno food-inno-db food-inno-redis
```

WordPress is accessible at `http://127.0.0.1:9000` after starting.

## Architecture

```
┌──────────────────── food-inno-network (bridge) ────────────────────┐
│                                                                     │
│  wordpress (food-inno)    db (food-inno-db)    redis (food-inno-redis)
│  127.0.0.1:9000 → :80    internal :3306        internal :6379      │
│  ./public_html            ./mysql-data          ephemeral cache     │
│  depends_on: db, redis                          maxmemory 256m lru  │
└─────────────────────────────────────────────────────────────────────┘
```

- **WordPress** depends on both `db` and `redis`
- Only WordPress port is exposed to host (127.0.0.1:9000); DB and Redis are internal-only
- `public_html/` is empty until first `docker-compose up` populates it with WordPress files

## Environment

Run `./setup.sh` to open the management dashboard; menu 1 (wizard) generates
`docker-compose.yml` + `.env` (random passwords + salts) from a project name, preserving
all headless optimizations. Alternatively, copy `env.example` to `.env` manually.
Required variables:

| Variable | Purpose |
|---|---|
| `MYSQL_ROOT_PASSWORD` | MariaDB root password |
| `MYSQL_DATABASE` | Database name |
| `MYSQL_USER` | Database user |
| `MYSQL_PASSWORD` | Database password |
| `WORDPRESS_TABLE_PREFIX` | Table prefix (default: `wp_`) |
| `WP_SITE_URL` | Public CMS URL → `WP_HOME`/`WP_SITEURL` (headless, behind HTTPS proxy) |
| `FRONTEND_ORIGIN` | Next.js origin allowed by CORS (mu-plugin), no wildcard |

## Key Configuration Files

- **`setup.sh`** — Interactive dashboard (run with no args): install wizard (with optional advanced settings — image tag, upload limit, Redis maxmemory, cron interval, www toggle), up/down/restart/logs/status, backup/restore (restore requires typing `yes`, flushes Redis after), WP-CLI shell, nginx + certbot. Subcommands skip the menu: `./setup.sh wizard|up|down|restart|status|backup|init|nginx`
- **`docker-compose.yml`** — Service definitions, volumes, network. `WORDPRESS_CONFIG_EXTRA` injects: `WP_REDIS_*` constants (Redis Object Cache plugin), X-Forwarded-Proto trust (no redirect loop behind HTTPS proxy), `WP_HOME`/`WP_SITEURL` from `WP_SITE_URL`, `DISALLOW_FILE_EDIT`
- **`php-uploads.ini`** — PHP tuning: 512M upload/post/memory limit, 600s max execution, OPCache enabled
- **`wp-init.sh`** — Post-`up` automation: waits for healthy, installs WP-CLI into the container, runs `wp core install`, sets `/%postname%/` permalinks (plain permalinks break `/wp-json`), installs + activates Redis Object Cache (enables drop-in) and WPGraphQL. Idempotent.
- **`backup.sh`** — DB dump (verified, gzipped) into `./backups/`, `--uploads` flag tars uploads, `KEEP=N` retention (default 14)
- **`mu-plugins/`** — Must-use plugins mounted read-only into the container: `headless-cors.php` (CORS for REST + WPGraphQL driven by `FRONTEND_ORIGIN`, supports comma-separated origins, removes core's permissive `rest_send_cors_headers`) and `headless-hardening.php` (block XML-RPC requests with 403, block REST user enumeration, hide WP version)

A 4th compose service `wpcron` (alpine sidecar) hits `wp-cron.php` every 5 minutes; `DISABLE_WP_CRON` is set in `WORDPRESS_CONFIG_EXTRA`.

All user-facing docs are consolidated in **`README.md`** (Vietnamese) — do not create additional README-*.md files.

## Post-install (manual, after first `docker-compose up`)

Install plugins: **Redis Object Cache** (then click Enable Object Cache to create the `object-cache.php` drop-in) and **WPGraphQL** (if the frontend uses GraphQL).

## Git-ignored Files

`mysql-data/`, `public_html/wp-content/uploads/`, `public_html/wp-content/cache/`, `.env`, `*.conf` (nginx configs generated per-deploy by setup.sh) — not tracked in git.
