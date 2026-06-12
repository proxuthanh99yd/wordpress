# Hướng dẫn cấu hình Redis cho WordPress

## Cách 1: Sử dụng Plugin (Khuyến nghị)

### Bước 1: Cài đặt Plugin
1. Vào WordPress Admin → Plugins → Add New
2. Tìm và cài đặt plugin: **Redis Object Cache** (bởi Till Krüss)
3. Kích hoạt plugin

### Bước 2: Cấu hình trong wp-config.php
Thêm các dòng sau vào file `wp-config.php` (trước dòng `/* That's all, stop editing! */`):

```php
// Redis configuration
define('WP_REDIS_HOST', 'redis');
define('WP_REDIS_PORT', 6379);
define('WP_REDIS_DATABASE', 0);
define('WP_REDIS_TIMEOUT', 1);
define('WP_REDIS_READ_TIMEOUT', 1);
```

### Bước 3: Kích hoạt Object Cache
1. Vào WordPress Admin → Settings → Redis
2. Click nút "Enable Object Cache"
3. Kiểm tra trạng thái kết nối

## Cách 2: Cấu hình thủ công (Advanced)

### Bước 1: Cài đặt Redis Object Cache Drop-in
1. Tải file `object-cache.php` từ plugin Redis Object Cache
2. Copy vào thư mục `wp-content/` của WordPress

### Bước 2: Cấu hình wp-config.php
Sử dụng file `wp-config-redis.example.php` làm tham khảo và thêm vào `wp-config.php`

## Kiểm tra kết nối

### Từ WordPress container:
```bash
docker exec -it food-inno bash
redis-cli -h redis -p 6379 ping
# Kết quả: PONG (nếu kết nối thành công)
```

### Kiểm tra cache keys:
```bash
docker exec -it food-inno-redis redis-cli
> KEYS *
> GET wp_:key_name
> INFO memory   # maxmemory = 256mb, policy allkeys-lru
```

## Troubleshooting

### Lỗi: "Connection refused"
- Kiểm tra Redis container đang chạy: `docker ps`
- Kiểm tra network: Cả WordPress và Redis phải cùng network `food-inno-network`
- Kiểm tra hostname: Phải dùng `redis` (tên service trong docker-compose)

### Lỗi: "Plugin không thấy Redis"
- Đảm bảo đã thêm cấu hình vào `wp-config.php`
- Kiểm tra file `wp-content/object-cache.php` có tồn tại
- Xem log: `docker logs wordpress-redis`

## Lưu ý

- **Hostname**: Trong Docker, dùng tên service `redis` (không phải `localhost` hay `127.0.0.1`)
- **Port**: Mặc định là `6379`
- **Password**: Nếu không cấu hình password thì không cần define `WP_REDIS_PASSWORD`
- **Network**: Cả WordPress và Redis phải cùng một Docker network

## Headless CMS — plugin & cấu hình cần thiết

Sau khi WordPress chạy lần đầu, cần cài thêm:

- **Redis Object Cache** (Till Krüss) → cài + **Enable Object Cache** để tạo drop-in
  `wp-content/object-cache.php`. wp-config đã có sẵn hằng Redis nhưng **chưa có drop-in
  thì object cache chưa thực sự bật**.
- **WPGraphQL** (nếu dùng GraphQL) → endpoint `/graphql`.

CORS và bảo mật headless đã được xử lý sẵn bằng mu-plugins (mount từ `./mu-plugins`):

- `headless-cors.php` — gửi CORS headers cho REST + WPGraphQL theo biến `FRONTEND_ORIGIN`.
- `headless-hardening.php` — tắt XML-RPC, chặn user enumeration REST, ẩn version WP.

URL công khai (`WP_SITE_URL`) và origin frontend (`FRONTEND_ORIGIN`) khai báo trong `.env`.
Reverse proxy phải truyền header `X-Forwarded-Proto` để WordPress sinh URL `https://`
(đã cấu hình trong `WORDPRESS_CONFIG_EXTRA` của docker-compose).

