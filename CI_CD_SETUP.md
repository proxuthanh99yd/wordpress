# Hướng dẫn Setup CI/CD

## Bước 1: Tạo GitLab Personal Access Token (PAT)

1. Vào GitLab → User Settings → Access Tokens (hoặc: https://gitlab.com/-/user_settings/personal_access_tokens)
2. Đặt tên token (ví dụ: `CI_CD_360home`)
3. Chọn expiration date (khuyến nghị: 1 năm hoặc không hết hạn)
4. Chọn scopes (quan trọng):
   - ✅ **`write_registry`** - Bắt buộc: Để push image lên GitLab Container Registry
   - ✅ **`read_registry`** - Bắt buộc: Để pull image từ GitLab Container Registry
   - ✅ **`read_repository`** - Khuyến nghị: Để clone code (nếu cần)
   - ✅ **`read_api`** - Tùy chọn: Để truy cập API (nếu cần)
5. Click "Create personal access token"
6. **Lưu token ngay** (chỉ hiển thị 1 lần)

## Bước 2: GitLab Container Registry

GitLab Container Registry tự động có sẵn cho mỗi project:
- Registry URL: `registry.gitlab.com`
- Image path: `registry.gitlab.com/NAMESPACE/PROJECT_NAME/IMAGE_NAME`

## Bước 3: Thiết lập biến môi trường trong GitLab CI/CD

Vào GitLab project → **Settings → CI/CD → Variables** → Expand

### Biến bắt buộc:

1. **GITLAB_REGISTRY_USER**
   - Key: `GITLAB_REGISTRY_USER`
   - Value: GitLab username của bạn (ví dụ: `git.okhub` hoặc `root`)
   - Protected: ❌
   - Masked: ❌

2. **GITLAB_REGISTRY_TOKEN**
   - Key: `GITLAB_REGISTRY_TOKEN`
   - Value: GitLab Personal Access Token đã tạo ở bước 1 (với scopes: `read_registry`, `write_registry`)
   - Protected: ✅
   - Masked: ✅ (quan trọng!)
   - **Lưu ý**: Đây là token bạn đã tạo ở bước 1 (ví dụ)

3. **VPS_HOST**
   - Key: `VPS_HOST`
   - Value: Địa chỉ IP hoặc domain VPS (ví dụ: `123.456.789.0`)
   - Protected: ❌
   - Masked: ✅
   - **Lưu ý**: SSH port mặc định là 8686 (không phải 22)

4. **VPS_USER**
   - Key: `VPS_USER`
   - Value: `root` (hoặc user SSH của bạn)
   - Protected: ❌
   - Masked: ❌

5. **VPS_PASS**
   - Key: `VPS_PASS`
   - Value: Password SSH của VPS
   - Protected: ✅
   - Masked: ✅ (quan trọng!)

### Biến môi trường ứng dụng (bắt buộc):

6. **NEXT_PUBLIC_CMS**
   - Value: `https://cms.360home.okhub-tech.com`

7. **NEXT_PUBLIC_API**
   - Value: `/wp-json/`

8. **GOOGLE_CLIENT_ID**
   - Value: `YOUR_GOOGLE_CLIENT_ID.apps.googleusercontent.com`

9. **GOOGLE_CLIENT_SECRET**
   - Value: `YOUR_GOOGLE_CLIENT_SECRET`
   - Masked: ✅

10. **AUTH_SECRET**
    - Value: `AVA_SECRET` (hoặc secret key mạnh hơn)
    - Masked: ✅

11. **NEXT_PUBLIC_API_CF7**
    - Value: `https://cms.360home.okhub-tech.com/wp-json/contact-form-7/v1/contact-forms`

12. **NEXT_PUBLIC_DOMAIN**
    - Value: `https://cms.360home.okhub-tech.com`

13. **AUTH_TRUST_HOST**
    - Value: `true`

14. **AUTH_URL**
    - Value: `https://360home.okhub-tech.com` (domain production với HTTPS)
    - **Lưu ý**: Phải dùng HTTPS và domain thực tế, không dùng localhost

15. **AUTH_REDIRECT_PROXY_URL**
    - Value: `https://360home.okhub-tech.com/api/auth` (domain production với HTTPS)
    - **Lưu ý**: Phải khớp với AUTH_URL và có path `/api/auth`

### Biến tùy chọn:

16. **ALLOW_SEARCH_ENGINE_INDEX**
    - Key: `ALLOW_SEARCH_ENGINE_INDEX`
    - Value: `true` hoặc `false` (mặc định: `false`)
    - Protected: ❌
    - Masked: ❌
    - **Mô tả**: Điều khiển việc cho phép Google và các search engine khác index website
      - `true`: Cho phép index (hiển thị trên Google)
      - `false`: Chặn index (không hiển thị trên Google)
    - **Lưu ý**: Nếu không set biến này, mặc định sẽ là `false` (chặn index)

## Bước 4: Setup trên VPS

SSH vào VPS và chạy các lệnh sau:

```bash
# 1. Cài đặt Docker (nếu chưa có)
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# 2. Cài đặt Docker Compose (nếu chưa có)
# Cách 1: Docker Compose v2 (khuyến nghị)
# Đã có sẵn trong Docker Desktop hoặc Docker Engine mới

# Cách 2: Docker Compose v1 (nếu cần)
sudo curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# 3. Tạo thư mục cho project
mkdir -p /opt/360home
cd /opt/360home

# 4. Tạo Docker network
docker network create 360home

# 5. Đăng nhập GitLab Container Registry (lần đầu)
# Thay YOUR_GITLAB_TOKEN bằng token đã tạo ở bước 1
# Thay YOUR_GITLAB_USERNAME bằng GitLab username của bạn
# Thay registry.gitlab.com bằng registry URL của GitLab instance (nếu self-hosted)
echo "YOUR_GITLAB_TOKEN" | docker login registry.gitlab.com -u YOUR_GITLAB_USERNAME --password-stdin

# Ví dụ:
# echo "" | docker login registry.gitlab.com -u git.okhub --password-stdin
```

## Bước 5: Test CI/CD Pipeline

1. **Commit và push code lên GitLab:**
   ```bash
   git add .
   git commit -m "Setup CI/CD"
   git push origin dev  # hoặc main, tamle
   ```

2. **Kiểm tra pipeline:**
   - Vào GitLab → CI/CD → Pipelines
   - Stage `build` sẽ tự động chạy
   - Stage `deploy` cần manual trigger (click nút ▶️)

3. **Kiểm tra logs:**
   - Click vào job để xem logs chi tiết
   - Nếu có lỗi, kiểm tra:
     - Biến môi trường đã set đúng chưa
     - VPS có thể SSH được không
     - Docker đã cài trên VPS chưa

## Bước 6: Verify Deployment

Sau khi deploy thành công:

```bash
# SSH vào VPS (port 8686)
ssh -p 8686 root@YOUR_VPS_HOST

# Kiểm tra container đang chạy
docker ps | grep 360home

# Kiểm tra logs
docker logs 360home

# Kiểm tra ứng dụng
curl http://localhost:3000
```

## Troubleshooting

### Lỗi: "Cannot connect to Docker daemon"
- Kiểm tra Docker service: `systemctl status docker`
- Khởi động Docker: `systemctl start docker`

### Lỗi: "Permission denied" khi SSH
- Kiểm tra password trong GitLab variables
- Thử SSH thủ công: `ssh -p 8686 root@VPS_HOST`
- **Lưu ý**: SSH port là 8686, không phải 22 mặc định

### Lỗi: "Image not found" hoặc "Unauthorized"
- Kiểm tra GHCR_TOKEN có quyền `write:packages`
- Kiểm tra GHCR_USERNAME đúng chưa
- Thử login thủ công: `docker login ghcr.io`

### Lỗi: "Network not found"
- Tạo network: `docker network create 360home`

### Lỗi: "502 Bad Gateway" khi truy cập website
Lỗi này xảy ra khi Nginx không thể kết nối đến container Next.js. Kiểm tra theo các bước sau:

1. **Kiểm tra container có đang chạy:**
   ```bash
   docker ps | grep 360home
   # Nếu không thấy, kiểm tra tất cả containers (kể cả stopped)
   docker ps -a | grep 360home
   ```

2. **Kiểm tra logs của container:**
   ```bash
   docker logs 360home
   # Xem logs real-time
   docker logs -f 360home
   ```

3. **Kiểm tra container có listen trên port 3000:**
   ```bash
   # Test từ trong VPS
   curl http://localhost:3000
   # Hoặc
   curl http://127.0.0.1:3000
   ```

4. **Kiểm tra health check:**
   ```bash
   docker inspect 360home | grep -A 10 Health
   # Nếu unhealthy, xem logs để biết lý do
   ```

5. **Kiểm tra container có listen đúng interface:**
   ```bash
   # Xem logs khi container start
   docker logs 360home | grep -i "local\|network"
   # Phải thấy: "Local: http://0.0.0.0:3000" hoặc "Network: http://0.0.0.0:3000"
   # Nếu thấy container hostname (như 808ee07acc7e), container chưa listen đúng
   ```

6. **Restart container nếu cần:**
   ```bash
   docker compose down
   docker compose up -d
   # Hoặc
   docker restart 360home
   ```

7. **Kiểm tra Nginx error logs:**
   ```bash
   sudo tail -f /var/log/nginx/360home-error.log
   # Xem có lỗi gì khi proxy đến container
   ```

8. **Kiểm tra firewall:**
   ```bash
   # Đảm bảo không block localhost
   sudo iptables -L -n | grep 3000
   ```

**Nguyên nhân thường gặp:**
- Container chưa khởi động xong (đợi thêm 1-2 phút)
- Container crash do lỗi code hoặc thiếu env vars
- Container listen trên container hostname thay vì 0.0.0.0 (cần rebuild image với HOSTNAME=0.0.0.0)
- Nginx config sai proxy_pass URL

## Bước 7: Cấu hình Nginx Reverse Proxy (Tùy chọn)

Nginx reverse proxy giúp:
- Truy cập ứng dụng qua domain thay vì IP:port
- Load balancing và caching
- SSL/TLS termination (khi cần)
- Bảo mật tốt hơn (ẩn port 3000)

### Cài đặt Nginx

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install nginx -y

# CentOS/RHEL
sudo yum install nginx -y

# Khởi động Nginx
sudo systemctl start nginx
sudo systemctl enable nginx
```

### Cấu hình Reverse Proxy

1. **Copy file config mẫu:**
   ```bash
   # Copy file nginx.example.conf từ project
   sudo cp nginx.example.conf /etc/nginx/sites-available/360home
   ```

2. **Chỉnh sửa domain:**
   ```bash
   sudo nano /etc/nginx/sites-available/360home
   # Thay đổi your-domain.com thành domain thực tế của bạn
   ```

3. **Tạo symlink để enable:**
   ```bash
   sudo ln -s /etc/nginx/sites-available/360home /etc/nginx/sites-enabled/
   ```

4. **Xóa default config (nếu cần):**
   ```bash
   sudo rm /etc/nginx/sites-enabled/default
   ```

5. **Test cấu hình:**
   ```bash
   sudo nginx -t
   ```

6. **Reload Nginx:**
   ```bash
   sudo systemctl reload nginx
   ```

### Kiểm tra

```bash
# Kiểm tra Nginx status
sudo systemctl status nginx

# Kiểm tra logs
sudo tail -f /var/log/nginx/360home-access.log
sudo tail -f /var/log/nginx/360home-error.log

# Test từ browser hoặc curl
curl http://your-domain.com
```

### Lưu ý

- Đảm bảo container đang chạy trên port 3000
- Đảm bảo firewall cho phép port 80 (HTTP)
- Nếu dùng domain, cần trỏ DNS A record về IP VPS
- File config mẫu: `nginx.example.conf` trong project root

### Cài đặt SSL với Certbot (Let's Encrypt)

1. **Cài đặt Certbot:**
   ```bash
   # Ubuntu/Debian
   sudo apt update
   sudo apt install certbot python3-certbot-nginx -y

   # CentOS/RHEL
   sudo yum install certbot python3-certbot-nginx -y
   ```

2. **Đảm bảo domain đã trỏ về VPS:**
   ```bash
   # Kiểm tra DNS
   dig your-domain.com
   # Hoặc
   nslookup your-domain.com
   ```

3. **Đảm bảo firewall cho phép port 80 và 443:**
   ```bash
   # Ubuntu/Debian (UFW)
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
   sudo ufw reload

   # Hoặc iptables
   sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
   sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT
   ```

4. **Chạy Certbot để cài SSL:**
   ```bash
   # Tự động cấu hình SSL cho Nginx
   sudo certbot --nginx -d your-domain.com -d www.your-domain.com

   # Hoặc chỉ domain chính (không có www)
   sudo certbot --nginx -d your-domain.com
   ```

5. **Làm theo hướng dẫn:**
   - Nhập email để nhận thông báo (khuyến nghị)
   - Đồng ý với điều khoản (A)
   - Chọn có redirect HTTP sang HTTPS (2 - khuyến nghị)

6. **Kiểm tra SSL:**
   ```bash
   # Test SSL
   sudo certbot certificates

   # Test từ browser
   curl https://your-domain.com
   ```

7. **Tự động gia hạn SSL:**
   ```bash
   # Test auto-renewal
   sudo certbot renew --dry-run

   # Certbot tự động tạo cron job để gia hạn
   # Kiểm tra cron job
   sudo systemctl status certbot.timer
   ```

8. **Cập nhật Nginx config (nếu cần chỉnh sửa thủ công):**
   ```bash
   # Certbot tự động cập nhật config, nhưng có thể chỉnh sửa thêm
   sudo nano /etc/nginx/sites-available/360home
   
   # Sau khi chỉnh sửa, test và reload
   sudo nginx -t
   sudo systemctl reload nginx
   ```

### Cấu hình SSL nâng cao (Tùy chọn)

Thêm vào Nginx config sau khi có SSL:

```nginx
# Redirect HTTP to HTTPS
server {
    listen 80;
    server_name your-domain.com www.your-domain.com;
    return 301 https://$server_name$request_uri;
}

# HTTPS server
server {
    listen 443 ssl http2;
    server_name your-domain.com www.your-domain.com;

    # SSL certificates (Certbot tự động thêm)
    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;

    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # ... rest of your config ...
}
```

### Troubleshooting SSL

- **Lỗi "Failed to obtain certificate":**
  - Kiểm tra DNS đã trỏ đúng chưa
  - Kiểm tra port 80 có mở không
  - Kiểm tra firewall không chặn Certbot

- **Lỗi "Connection refused":**
  - Đảm bảo Nginx đang chạy: `sudo systemctl status nginx`
  - Kiểm tra config: `sudo nginx -t`

- **SSL hết hạn:**
  - Gia hạn thủ công: `sudo certbot renew`
  - Kiểm tra auto-renewal: `sudo certbot renew --dry-run`

## Lưu ý quan trọng

1. ✅ **Bảo mật**: Tất cả token và password phải được đánh dấu "Masked" trong GitLab
2. ✅ **Backup**: Lưu lại các token ở nơi an toàn
3. ✅ **Firewall**: Đảm bảo port 3000 mở trên VPS (nếu cần truy cập từ ngoài)
4. ✅ **SSL**: Đã có hướng dẫn cài đặt SSL với Certbot (Let's Encrypt) ở Bước 7
5. ✅ **Nginx**: Nếu dùng Nginx, có thể đóng port 3000 trên firewall và chỉ mở port 80/443
6. ✅ **SSL Auto-renewal**: Certbot tự động tạo cron job để gia hạn SSL, kiểm tra định kỳ

