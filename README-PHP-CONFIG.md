# Cấu hình PHP cho WordPress

## Tăng giới hạn upload và memory

File `php-uploads.ini` đã được cấu hình với các giá trị tối ưu:

### Upload Settings
- **upload_max_filesize**: `128M` - Tăng từ 2M mặc định (cho upload file lớn)
- **post_max_size**: `128M` - Phải lớn hơn hoặc bằng upload_max_filesize
- **max_file_uploads**: `20` - Cho phép upload tối đa 20 file cùng lúc

### Memory Settings
- **memory_limit**: `512M` - Tăng từ 128M mặc định (tốt cho plugin nặng và large sites)
- **max_execution_time**: `600` giây (10 phút) - Tăng từ 30s mặc định (cho processing lớn)

### WordPress Optimizations
- **max_input_vars**: `3000` - Tăng từ 1000 mặc định (tốt cho theme với nhiều tùy chọn)
- **realpath_cache_size**: `4096k` - Cải thiện performance
- **OPCache**: Đã bật với cấu hình tối ưu

## Cách sử dụng

### 1. Khởi động containers
```bash
docker-compose up -d
```

### 2. Kiểm tra cấu hình PHP
```bash
docker exec -it wordpress php -i | grep -E "(upload_max_filesize|post_max_size|memory_limit|max_execution_time|max_input_vars)"
```

### 3. Kiểm tra từ WordPress Admin
Vào WordPress Admin → Media → Add New → Kiểm tra "Maximum upload file size"

## Tùy chỉnh thêm

### Thay đổi giá trị
Sửa file `php-uploads.ini` và restart container:

```bash
docker-compose restart wordpress
```

### Ví dụ: Tăng upload size lên 128MB
```ini
upload_max_filesize = 128M
post_max_size = 128M
```

### Thêm cấu hình mới
Thêm vào cuối file `php-uploads.ini` và restart container.

## Lưu ý

- File được mount vào `/usr/local/etc/php/conf.d/uploads.ini` trong container
- Cấu hình sẽ override các setting mặc định của WordPress image
- Không cần sửa file `wp-config.php` hoặc `.htaccess`
- Restart container để áp dụng thay đổi mới
