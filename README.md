# WordPress Headless CMS — Docker

WordPress + MariaDB + Redis chạy bằng Docker Compose, làm **headless CMS** (API-first)
cho frontend Next.js. Đã cấu hình sẵn: CORS, reverse-proxy HTTPS, Redis object cache,
bảo mật headless.

## Quick start

```bash
./setup.sh    # mở dashboard — cài đặt và quản lý mọi thứ từ đây
```

Lần đầu: chọn **1) Cài đặt mới** (wizard) → **5) Khởi động** → **2) Cài WordPress
+ plugins**. Xong — WordPress chạy tại `http://127.0.0.1:9000` (hoặc port đã chọn).

### Dashboard

```
 ── Cài đặt ──────────────────        ── Vận hành ─────────────────
  1) Cài đặt mới (wizard)              5) Khởi động (up -d)
  2) Cài WordPress + plugins           6) Dừng (down)
  3) Nginx + SSL (certbot)             7) Restart
  4) Sửa cấu hình                      8) Logs
                                       9) Cập nhật images
 ── Dữ liệu / Công cụ ────────────────────────────────────────────
  b) Backup    r) Restore    w) WP-CLI    s) Trạng thái    0) Thoát
```

Panel đầu dashboard hiện health từng container (chấm màu), URL, CORS origin.
Chạy thẳng 1 tác vụ không vào menu (dùng cho script/cron):

```bash
./setup.sh wizard|up|down|restart|status|backup|init|nginx
```

### wp-init.sh làm gì

Chạy sau `docker-compose up -d`, idempotent (chạy lại an toàn):

1. Chờ container wordpress healthy
2. Cài WP-CLI vào container
3. `wp core install` — hỏi title/admin/email, password tự sinh nếu để trống
4. Đặt permalink `/%postname%/` — **bắt buộc cho headless**: permalink "plain"
   mặc định làm REST `/wp-json` trả 404
5. Cài + kích hoạt **Redis Object Cache** (tự enable drop-in) và **WPGraphQL**

### Wizard (menu 1) hỏi gì

| Câu hỏi | Dùng để |
|---|---|
| Tên project | Container names (`<project>`, `<project>-db`...), network, DB name/user, table prefix |
| Domain (vd `cms.domain.com.vn`) | Render nginx config `<domain>.conf`; bỏ trống nếu chỉ chạy local |
| Cổng host (mặc định 9000) | Port expose WordPress trên `127.0.0.1` |
| WP_SITE_URL | URL công khai của CMS (mặc định `https://<domain>`) |
| FRONTEND_ORIGIN | Origin Next.js được phép gọi API (CORS) |

**Mục nâng cao** (`Tuỳ chỉnh nâng cao? [y/N]` — Enter là dùng toàn bộ mặc định):
WordPress image tag, upload limit (đồng bộ PHP + nginx), PHP memory/timezone,
Redis maxmemory, table prefix, WP-Cron interval, có/không `www.` trong nginx+SSL.
Flow mặc định **không** đụng tới `php-uploads.ini`.

Mật khẩu DB + 8 salts sinh ngẫu nhiên. Trên VPS có nginx, wizard hỏi để tự:
copy conf vào `sites-available/`, symlink sang `sites-enabled/`, `nginx -t`,
reload, và chạy `certbot --nginx` cấp SSL (certbot tự thêm block 443).

> ⚠️ **Không ghi đè `.env` sau khi đã `up` lần đầu** — MariaDB chỉ nhận user/password
> ở lần khởi tạo `mysql-data/` đầu tiên; đổi mật khẩu sau đó sẽ gây lỗi đăng nhập DB.

### Restore (menu r)

Liệt kê backup trong `./backups/`, chọn bản → gõ `yes` xác nhận (ghi đè toàn bộ DB!)
→ tự flush Redis cache sau restore, hỏi restore kèm uploads.

## Workflow tạo site mới

### A. Local (dev)

```bash
# 1. Clone repo về thư mục mới (mỗi site = 1 thư mục riêng)
git clone <repo-url> my-new-site && cd my-new-site

# 2. Mở dashboard
./setup.sh
```

Trong dashboard:

| Bước | Menu | Nhập gì |
|---|---|---|
| 1 | `1) Cài đặt mới` | Tên project (vd `my-site`) → domain **bỏ trống** → port (vd `9001` nếu 9000 đã dùng) → Enter hết phần còn lại → nâng cao: `n` |
| 2 | `5) Khởi động` | Chờ 4 container healthy (~30s, lần đầu pull image lâu hơn) |
| 3 | `2) Cài WordPress + plugins` | Site title, admin user/email; password để trống sẽ tự sinh — **lưu lại ngay** |

Kiểm tra: Admin `http://127.0.0.1:9001/wp-admin/` · REST `/wp-json/` · GraphQL `/graphql`.
Next.js local (`http://localhost:3000`) gọi API được luôn — CORS mặc định trỏ về đó.

### B. Production (VPS)

```bash
# 0. Chuẩn bị: DNS trỏ cms.domain.com.vn về IP VPS TRƯỚC (certbot cần)
ssh vps && cd /opt && git clone <repo-url> my-new-site && cd my-new-site
./setup.sh
```

| Bước | Menu | Nhập gì |
|---|---|---|
| 1 | `1) Cài đặt mới` | Tên project → **domain** `cms.domain.com.vn` → port (vd `9001`) → `WP_SITE_URL` Enter (tự ra `https://<domain>`) → `FRONTEND_ORIGIN` = origin Next.js thật |
| 2 | *(wizard tự tiếp)* | Bước 5/5: cài nginx conf + symlink + reload → `y`; chạy certbot → `y` |
| 3 | `5) Khởi động` | Chờ healthy |
| 4 | `2) Cài WordPress + plugins` | Như local |
| 5 | Thoát dashboard | Thêm cron backup: `crontab -e` → `0 3 * * * /opt/my-new-site/backup.sh --uploads >> /var/log/wp-backup.log 2>&1` |

### Những thứ KHÔNG phải làm (đã tự động)

- ❌ Tạo DB/user/password — wizard sinh ngẫu nhiên
- ❌ Sửa wp-config (Redis, salts, proxy HTTPS, CORS) — inject qua compose
- ❌ Đổi permalink để `/wp-json` chạy — wp-init tự đặt `/%postname%/`
- ❌ Cài/enable Redis Object Cache, WPGraphQL — wp-init tự cài
- ❌ Cấu hình WP-Cron — sidecar `wpcron` tự gọi
- ❌ Tắt XML-RPC, chặn user enumeration — mu-plugins tự active

### Nhiều site trên 1 VPS

1. Mỗi site 1 thư mục, 1 port riêng (`9000`, `9001`...) — tên project khác nhau nên
   container/network không đụng nhau.
2. **DNS trỏ xong mới chạy certbot** — fail thì wizard không chết, chạy lại sau bằng
   menu `3) Nginx + SSL`.
3. Không ghi đè `.env` sau lần `up` đầu (wizard có cảnh báo sẵn).
4. Vận hành về sau: `cd /opt/my-new-site && ./setup.sh` → menu (status, logs, backup,
   update images...).

> Tóm gọn: **local = 3 lựa chọn menu (1 → 5 → 2)**; **VPS = thêm domain ở wizard +
> `y` cho nginx/certbot + 1 dòng crontab backup**.

## Kiến trúc

```
┌───────────────────────── <project>-network (bridge) ─────────────────────────┐
│                                                                               │
│  wordpress (<project>)     db (<project>-db)    redis (<project>-redis)       │
│  127.0.0.1:<port> → :80   internal :3306        internal :6379                │
│  ./public_html             ./mysql-data          (cache, không persist)       │
│                                                                               │
│  wpcron (<project>-wpcron) — gọi wp-cron.php mỗi 5 phút (DISABLE_WP_CRON)    │
└───────────────────────────────────────────────────────────────────────────────┘
```

- Image theo [official WordPress](https://hub.docker.com/_/wordpress): `wordpress:7.0-php8.3-apache`
  (pin minor — patch release tự cập nhật khi pull).
- Chỉ WordPress expose ra host (bind `127.0.0.1`); DB và Redis internal-only.
- Redis chạy chế độ object cache: `maxmemory 256mb`, evict `allkeys-lru`, không AOF.
- Healthcheck đủ 3 service chính; WordPress chỉ start sau khi DB + Redis healthy.
- **WP-Cron**: đã tắt khỏi request người dùng (`DISABLE_WP_CRON`) — sidecar `wpcron`
  (alpine) gọi `wp-cron.php` mỗi 5 phút, scheduled posts/cron jobs chạy đúng giờ
  kể cả khi site không có traffic.

## Headless — CORS & bảo mật

Hai mu-plugin trong `mu-plugins/` được mount read-only vào container (tự active,
không cần bật trong admin):

- **`headless-cors.php`** — gửi CORS headers cho REST API (`/wp-json`) và WPGraphQL
  (`/graphql`) theo biến `FRONTEND_ORIGIN` trong `.env`. Không dùng wildcard `*`.
  Hỗ trợ nhiều origin phân cách dấu phẩy: `FRONTEND_ORIGIN=https://prod.com,https://staging.com`.
  Đồng thời gỡ CORS mặc định quá mở của core (`rest_send_cors_headers` cho phép mọi origin).
- **`headless-hardening.php`** — tắt XML-RPC, chặn liệt kê users qua REST
  (`/wp/v2/users` với khách chưa đăng nhập), ẩn version WordPress, gỡ pingback header.

Ngoài ra `WORDPRESS_CONFIG_EXTRA` (trong docker-compose.yml) đã:

- Trust `X-Forwarded-Proto` → WordPress sinh URL `https://` đúng sau reverse proxy,
  không bị redirect loop.
- Set `WP_HOME`/`WP_SITEURL` từ `WP_SITE_URL`.
- `DISALLOW_FILE_EDIT` — chặn sửa file plugin/theme từ admin.

## Biến môi trường (`.env`)

| Biến | Mục đích |
|---|---|
| `MYSQL_ROOT_PASSWORD` | Mật khẩu root MariaDB |
| `MYSQL_DATABASE` / `MYSQL_USER` / `MYSQL_PASSWORD` | Database WordPress |
| `WORDPRESS_TABLE_PREFIX` | Prefix bảng (vd `foodinno_`) |
| `WORDPRESS_AUTH_KEY` … `WORDPRESS_NONCE_SALT` | 8 salts/keys — **bắt buộc**, sinh bởi `setup.sh` (compose từ chối start nếu thiếu). Cố định qua `.env` để session không bị invalidate khi recreate container |
| `WORDPRESS_DEBUG` | Đặt `1` để bật `WP_DEBUG` (mặc định tắt) |
| `WP_SITE_URL` | URL công khai → `WP_HOME`/`WP_SITEURL` |
| `FRONTEND_ORIGIN` | Origin Next.js được phép CORS — nhiều origin phân cách dấu phẩy |

## Cấu hình PHP (`php-uploads.ini`)

Mount vào `/usr/local/etc/php/conf.d/uploads.ini`, override mặc định của image:

- `upload_max_filesize = 512M`, `post_max_size = 512M`
- `memory_limit = 512M`, `max_execution_time = 600`, `max_input_vars = 3000`
- OPCache bật, realpath cache 4096k

Sửa file rồi `docker-compose restart wordpress` để áp dụng. Kiểm tra:

```bash
docker exec -it <project> php -i | grep -E "upload_max_filesize|post_max_size|memory_limit"
```

## Nginx + SSL (production)

`setup.sh` render sẵn `<domain>.conf` (block `:80`, đầy đủ `X-Forwarded-*` headers).
Nếu cài thủ công trên VPS:

```bash
sudo cp <domain>.conf /etc/nginx/sites-available/
sudo ln -s /etc/nginx/sites-available/<domain>.conf /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
sudo certbot --nginx -d <domain> -d www.<domain>   # tự thêm block 443 + redirect
```

## Backup

```bash
./backup.sh             # dump database vào ./backups/db-<timestamp>.sql.gz
./backup.sh --uploads   # + tar wp-content/uploads
KEEP=30 ./backup.sh     # giữ 30 bản gần nhất (mặc định 14, tự xoá bản cũ hơn)
```

Dump được verify (`gzip -t` + kích thước) trước khi báo thành công. Chạy định kỳ
trên VPS:

```bash
# crontab -e — backup 3h sáng hàng ngày
0 3 * * * /opt/<project>/backup.sh --uploads >> /var/log/wp-backup.log 2>&1
```

Khôi phục:

```bash
gunzip -c backups/db-<timestamp>.sql.gz | docker compose exec -T db sh -c \
  'mariadb -u root -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"'
tar -xzf backups/uploads-<timestamp>.tar.gz -C public_html/wp-content/
```

## Lệnh thường dùng

```bash
docker-compose up -d              # khởi động
docker-compose down               # dừng
docker-compose ps                 # trạng thái + healthcheck
docker-compose logs -f            # logs
docker exec -it <project> bash    # shell WordPress
docker exec -it <project>-db mysql -u $MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE
docker exec -it <project>-redis redis-cli ping        # PONG
docker exec -it <project>-redis redis-cli info memory # maxmemory 256mb, lru
docker stats <project> <project>-db <project>-redis   # resource
```

## Kiểm tra headless hoạt động

```bash
# CORS: phải thấy Access-Control-Allow-Origin = FRONTEND_ORIGIN
curl -i -H "Origin: https://<frontend>" http://127.0.0.1:9000/wp-json/ | grep -i access-control

# Bảo mật: users bị chặn với khách, XML-RPC tắt
curl -s http://127.0.0.1:9000/wp-json/wp/v2/users     # → 404 rest_no_route
curl -s http://127.0.0.1:9000/xmlrpc.php              # → XML-RPC disabled
```

## Troubleshooting

| Lỗi | Nguyên nhân / cách xử lý |
|---|---|
| Redis "Connection refused" | Kiểm tra `docker ps`; hostname phải là `redis` (tên service), không phải `localhost` |
| Plugin Redis báo "Not connected" | Chưa bấm Enable Object Cache (thiếu drop-in `wp-content/object-cache.php`) |
| Redirect loop sau khi có SSL | Reverse proxy thiếu header `X-Forwarded-Proto` (conf do setup.sh sinh đã có sẵn) |
| DB "Access denied" sau khi đổi `.env` | MariaDB chỉ nhận password ở lần init đầu — reset `mysql-data/` hoặc đổi password trong DB |
| Frontend bị chặn CORS | `FRONTEND_ORIGIN` trong `.env` phải khớp chính xác origin (scheme + host + port), sau đó `docker-compose up -d` lại |

## Dữ liệu (git-ignored)

`mysql-data/`, `public_html/wp-content/uploads/`, `public_html/wp-content/cache/`,
`backups/`, `.env`, `*.conf` — dữ liệu persistent / per-deploy, không track trong git.
