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

- **`setup.sh`** — Entrypoint only: sets `set -euo pipefail`, `cd`s to its dir, sources `lib/*.sh`, then dispatches the `case "${1:-}"` (subcommands `wizard|up|down|restart|status|health|backup|init|plugins|nginx|ui`, no arg = dashboard). All logic lives in **`lib/`** modules (sourced — function defs + default vars only, never run standalone):
  - `lib/ui.sh` — colors + `err/ok/info/step/ask/confirm/pause/rand/banner` + a **gum layer**: `has_gum` (gum present **and** interactive TTY, cached) gates `ask`/`confirm`/`banner`/`ui_menu` (arrow-key `gum choose`) to gum, else they fall back to the plain-ANSI path. `ensure_gum` offers to install gum via brew / Charm apt repo / Charm yum repo (subcommand `ui`)
  - `lib/status.sh` — `svc_dot/detect_project/detect_port/env_get/panel`
  - `lib/wizard.sh` — `*_DEFAULT` vars + `wizard/write_env/write_compose/write_php_ini`
  - `lib/nginx.sh` — `render_nginx/ensure_certbot/install_nginx/nginx_menu` (`ensure_certbot` auto-installs certbot via apt/dnf/yum when missing during SSL setup)
  - `lib/ops.sh` — `require_config/do_up/do_down/do_restart/do_update/do_logs/do_status`
  - `lib/health.sh` — `check_url/check_ssl/do_healthcheck` (curl REST `/wp-json/` + WPGraphQL `/graphql` against `WP_SITE_URL`; on a VPS also checks `certbot.timer` auto-renew + live cert expiry via `openssl`, auto-skipped locally)
  - `lib/data.sh` — `do_backup_menu/do_restore/wpexec/wpcli/ensure_wpcli/require_wp/do_wpcli` (`require_wp` = config + container running + wp-cli phar ready, shared guard)
  - `lib/plugins.sh` — `do_plugins` (WP-CLI plugin manager: list/search/install[+activate]/activate/deactivate/delete/update)
  - `lib/config.sh` — `set_env_var/do_cors/do_config` (quick-edit `FRONTEND_ORIGIN`/`WP_SITE_URL` via shared `set_env_var`, offers `up -d` to apply)
  - `lib/menu.sh` — `menu_text/dashboard/usage` (+ `DASH_LABELS`; dashboard uses `ui_menu` when gum is present, else the lettered `menu_text` prompt — both feed one `case` via the `<code>) ` label prefix)
  - Modules share one shell namespace; sourcing order doesn't matter (no top-level execution). Edit the relevant module, not `setup.sh`.
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

`mysql-data/`, `public_html/wp-content/uploads/`, `public_html/wp-content/cache/`, `.env`, `docker-compose.yml`, `*.conf` — generated per-deploy by the wizard (`.env`/`docker-compose.yml` via `write_env`/`write_compose`, nginx `*.conf` via `render_nginx`), so they are git-ignored. `env.example` is the tracked reference template. The repo tracks only the tool (setup.sh, lib/, wp-init.sh, backup.sh, php-uploads.ini, mu-plugins/), so `git pull` updates the tool without touching a deployment's config.
