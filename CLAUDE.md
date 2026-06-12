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
│  ./public_html            ./mysql-data          ./redis-data        │
│  depends_on: db, redis                          --appendonly yes    │
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

- **`docker-compose.yml`** — Service definitions, volumes, network
- **`php-uploads.ini`** — PHP tuning: 512M upload/memory limit, 600s max execution, OPCache enabled
- **`wp-config-redis.example.php`** — Redis object cache config to add to `wp-config.php`
- **`nginx-wordpress.conf.example`** — Optional Nginx reverse proxy for production (domain: food.innojsc.com)
- **`mu-plugins/`** — Must-use plugins mounted read-only into the container: `headless-cors.php` (CORS for REST + WPGraphQL, driven by `FRONTEND_ORIGIN`) and `headless-hardening.php` (disable XML-RPC, block REST user enumeration, hide WP version)

## Git-ignored Data Directories

`mysql-data/`, `redis-data/`, `public_html/wp-content/uploads/`, `public_html/wp-content/cache/` — these are persistent Docker volumes, not tracked in git.

## Deployment

Build and deploy docs are in `BUILD.md` (Vietnamese) and `CI_CD_SETUP.md`. Deployment target is a VPS at `/opt/360home/` using GitLab Container Registry, with SSH on port 8686. See `CI_CD_SAFETY.md` for container safety guidelines.
