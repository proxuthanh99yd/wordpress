<?php
/**
 * Redis Object Cache Configuration
 * 
 * Thêm các dòng này vào file wp-config.php của bạn
 * Đặt TRƯỚC dòng "/* That's all, stop editing! */"
 */

// Redis configuration
define('WP_REDIS_HOST', 'redis');
define('WP_REDIS_PORT', 6379);
define('WP_REDIS_DATABASE', 0);
// define('WP_REDIS_PASSWORD', ''); // Không cần password
define('WP_REDIS_TIMEOUT', 1);
define('WP_REDIS_READ_TIMEOUT', 1);
define('WP_REDIS_DISABLED', false);

// Optional: Redis prefix for cache keys
define('WP_REDIS_PREFIX', 'wp_');

// Optional: Enable Redis for object cache
define('WP_CACHE', true);

