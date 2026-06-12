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

Run `./setup.sh` to generate `docker-compose.yml` + `.env` for a new project (prompts for a
project name, derives container/network/DB names and a table prefix from it, and generates
random DB passwords). It preserves the headless optimizations baked into the compose file.

Alternatively, copy `env.example` to `.env` manually before starting. Required variables:

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

- **`setup.sh`** — Generator: prompts for project name + domain, renders `docker-compose.yml`, `.env` (random passwords), nginx `<domain>.conf`; on a VPS optionally installs the nginx conf (sites-available + symlink) and runs certbot
- **`docker-compose.yml`** — Service definitions, volumes, network. `WORDPRESS_CONFIG_EXTRA` injects: `WP_REDIS_*` constants (Redis Object Cache plugin), X-Forwarded-Proto trust (no redirect loop behind HTTPS proxy), `WP_HOME`/`WP_SITEURL` from `WP_SITE_URL`, `DISALLOW_FILE_EDIT`
- **`php-uploads.ini`** — PHP tuning: 512M upload/post/memory limit, 600s max execution, OPCache enabled
- **`mu-plugins/`** — Must-use plugins mounted read-only into the container: `headless-cors.php` (CORS for REST + WPGraphQL, driven by `FRONTEND_ORIGIN`) and `headless-hardening.php` (disable XML-RPC, block REST user enumeration, hide WP version)

All user-facing docs are consolidated in **`README.md`** (Vietnamese) — do not create additional README-*.md files.

## Post-install (manual, after first `docker-compose up`)

Install plugins: **Redis Object Cache** (then click Enable Object Cache to create the `object-cache.php` drop-in) and **WPGraphQL** (if the frontend uses GraphQL).

## Git-ignored Files

`mysql-data/`, `public_html/wp-content/uploads/`, `public_html/wp-content/cache/`, `.env`, `*.conf` (nginx configs generated per-deploy by setup.sh) — not tracked in git.
