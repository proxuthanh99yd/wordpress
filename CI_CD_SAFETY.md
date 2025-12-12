# An toàn khi Deploy - Không ảnh hưởng Container khác

## ✅ Các điểm AN TOÀN (không ảnh hưởng container khác)

### 1. **Docker Compose Down**
- ✅ Chỉ dừng/xóa container được định nghĩa trong `docker-compose.yml` hiện tại
- ✅ Không ảnh hưởng container khác chạy độc lập
- ✅ Không ảnh hưởng container của docker-compose file khác

### 2. **Docker Network**
- ✅ Network `360home` là external network
- ✅ Nếu network đã tồn tại, sẽ dùng lại (không tạo mới)
- ✅ Container khác có thể join network này nếu cần

### 3. **Image Prune**
- ✅ Chỉ xóa image "dangling" (không tag, không dùng)
- ✅ Không xóa image đang được container khác sử dụng
- ✅ An toàn với container đang chạy

## ⚠️ Các điểm CẦN LƯU Ý

### 1. **Container Name Conflict**
- ⚠️ Nếu có container khác tên `360home` → sẽ bị thay thế
- ✅ **Giải pháp**: Đảm bảo không có container nào khác dùng tên `360home`

**Kiểm tra:**
```bash
docker ps -a | grep 360home
```

### 2. **Port Conflict**
- ⚠️ Port `3000` đã được container khác dùng → Deployment sẽ fail
- ✅ **Giải pháp**: 
  - Đổi port trong `docker-compose.yml` (ví dụ: `3001:3000`)
  - Hoặc dừng container đang dùng port 3000 trước

**Kiểm tra port:**
```bash
docker ps --format 'table {{.Names}}\t{{.Ports}}' | grep 3000
netstat -tulpn | grep 3000
```

### 3. **Network Name Conflict**
- ⚠️ Nếu network `360home` đã tồn tại và có container khác đang dùng
- ✅ **Giải pháp**: 
  - Dùng network riêng (đổi tên network)
  - Hoặc dùng network hiện có (an toàn)

## 🔒 Best Practices

### 1. **Isolation hoàn toàn (khuyến nghị)**

Nếu muốn hoàn toàn tách biệt, đổi tên:

```yaml
# docker-compose.yml
services:
  next-app:
    container_name: 360home-app  # Tên riêng
    networks:
      - 360home-network  # Network riêng

networks:
  360home-network:
    name: 360home-network  # Tên network riêng
    external: false  # Tạo mới, không dùng chung
```

### 2. **Kiểm tra trước khi deploy**

Thêm vào script deploy:
```bash
# Check container name
if docker ps -a --format '{{.Names}}' | grep -q '^360home$'; then
  echo "Container 360home exists - will be replaced"
fi

# Check port
if docker ps --format '{{.Ports}}' | grep -q ':3000->'; then
  echo "Port 3000 in use - check for conflicts"
fi
```

### 3. **Backup trước khi deploy**

```bash
# Backup container hiện tại (nếu cần)
docker commit 360home 360home-backup:$(date +%Y%m%d)
```

## 📋 Checklist trước khi deploy

- [ ] Kiểm tra không có container khác tên `360home`
- [ ] Kiểm tra port 3000 không bị chiếm
- [ ] Kiểm tra network `360home` (nếu cần dùng chung)
- [ ] Backup dữ liệu quan trọng (nếu có volume)
- [ ] Test trên môi trường staging trước

## 🛡️ Các lệnh an toàn

```bash
# Chỉ xem, không thay đổi
docker ps                    # Xem container đang chạy
docker ps -a                 # Xem tất cả container
docker network ls            # Xem network
docker images                # Xem images

# Kiểm tra conflict
docker ps --format '{{.Names}}' | grep 360home
docker ps --format '{{.Ports}}' | grep 3000
```

## ⚡ Tóm tắt

**CI/CD hiện tại AN TOÀN** với container khác vì:
- ✅ Chỉ thao tác với container trong docker-compose.yml
- ✅ Image prune chỉ xóa image không dùng
- ✅ Network external có thể dùng chung an toàn

**Chỉ cần lưu ý:**
- ⚠️ Container name `360home` không trùng
- ⚠️ Port 3000 không bị chiếm
- ⚠️ Nếu có volume quan trọng, backup trước

