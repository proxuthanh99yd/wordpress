# WordPress Headless CMS — Docker

WordPress + MariaDB + Redis chạy bằng Docker Compose, làm **headless CMS** (API-first)
cho frontend Next.js. Đã cấu hình sẵn: CORS, reverse-proxy HTTPS, Redis object cache,
bảo mật headless.

## Quick start

```bash
# 1. Sinh cấu hình theo tên project (tạo .env + docker-compose.yml + nginx conf)
./setup.sh

# 2. Khởi động
docker-compose up -d

# 3. Kiểm tra cả 3 service đều healthy
docker-compose ps
```

WordPress chạy tại `http://127.0.0.1:9000` (hoặc port bạn chọn trong setup.sh).

### setup.sh làm gì

Script hỏi lần lượt rồi tự sinh toàn bộ cấu hình:

| Câu hỏi | Dùng để |
|---|---|
| Tên project | Container names (`<project>`, `<project>-db`, `<project>-redis`), network, DB name/user, table prefix |
| Domain (vd `cms.domain.com.vn`) | Render nginx config `<domain>.conf`; bỏ trống nếu chỉ chạy local |
| Cổng host (mặc định 9000) | Port expose WordPress trên `127.0.0.1` |
| WP_SITE_URL | URL công khai của CMS (mặc định `https://<domain>`) |
| FRONTEND_ORIGIN | Origin Next.js được phép gọi API (CORS) |

Mật khẩu DB được sinh ngẫu nhiên. Trên VPS có nginx, script sẽ hỏi để tự:
copy conf vào `sites-available/`, symlink sang `sites-enabled/`, `nginx -t`,
reload, và chạy `certbot --nginx` cấp SSL (certbot tự thêm block 443).

> ⚠️ **Không ghi đè `.env` sau khi đã `up` lần đầu** — MariaDB chỉ nhận user/password
> ở lần khởi tạo `mysql-data/` đầu tiên; đổi mật khẩu sau đó sẽ gây lỗi đăng nhập DB.

## Sau khi WordPress chạy lần đầu

1. Cài đặt WordPress qua trình duyệt như bình thường.
2. Cài plugin **Redis Object Cache** (Till Krüss) → Settings → Redis → **Enable Object Cache**.
   Các hằng `WP_REDIS_*` đã được inject sẵn qua `WORDPRESS_CONFIG_EXTRA`, chỉ cần Enable
   để tạo drop-in `object-cache.php`. Kiểm tra trạng thái "Connected".
3. Cài **WPGraphQL** nếu frontend dùng GraphQL (endpoint `/graphql`).

## Kiến trúc

```
┌──────────────────── <project>-network (bridge) ─────────────────────┐
│                                                                      │
│  wordpress (<project>)     db (<project>-db)    redis (<project>-redis)
│  127.0.0.1:<port> → :80   internal :3306        internal :6379       │
│  ./public_html             ./mysql-data          (cache, không persist)
└──────────────────────────────────────────────────────────────────────┘
```

- Chỉ WordPress expose ra host (bind `127.0.0.1`); DB và Redis internal-only.
- Redis chạy chế độ object cache: `maxmemory 256mb`, evict `allkeys-lru`, không AOF.
- Healthcheck đủ 3 service; WordPress chỉ start sau khi DB + Redis healthy.

## Headless — CORS & bảo mật

Hai mu-plugin trong `mu-plugins/` được mount read-only vào container (tự active,
không cần bật trong admin):

- **`headless-cors.php`** — gửi CORS headers cho REST API (`/wp-json`) và WPGraphQL
  (`/graphql`) theo biến `FRONTEND_ORIGIN` trong `.env`. Không dùng wildcard `*`.
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
| `WP_SITE_URL` | URL công khai → `WP_HOME`/`WP_SITEURL` |
| `FRONTEND_ORIGIN` | Origin Next.js được phép CORS |

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
`.env`, `*.conf` — dữ liệu persistent / per-deploy, không track trong git.
