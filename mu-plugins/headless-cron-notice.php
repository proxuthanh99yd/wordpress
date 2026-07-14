<?php
/**
 * Plugin Name: Headless Cron Notice
 * Description: Stack này cố tình đặt DISABLE_WP_CRON = true; service `wpcron` gọi
 *              wp-cron.php định kỳ thay cho WP-Cron mặc định. Plugin bên thứ ba chỉ
 *              nhìn thấy hằng số đó rồi cảnh báo "your normal WP Cron is disabled" —
 *              cảnh báo sai ngữ cảnh, mu-plugin này gỡ nó khỏi màn hình admin.
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

if ( ! is_admin() ) {
	return;
}

/**
 * Chuỗi nhận diện notice cần gỡ (so khớp trên text đã strip tag, lowercase).
 * Bản tiếng Anh của mọi plugin đều chứa cụm này.
 */
const HEADLESS_CRON_NOTICE_NEEDLE = 'cron is disabled';

/**
 * Mở buffer trước khi các plugin khác in notice.
 */
function headless_cron_notice_open() {
	ob_start();
}

/**
 * Đóng buffer, gỡ những khối <div> có chứa cảnh báo WP-Cron, in lại phần còn lại.
 */
function headless_cron_notice_close() {
	$html = ob_get_clean();

	if ( ! is_string( $html ) || false === strpos( strtolower( $html ), HEADLESS_CRON_NOTICE_NEEDLE ) ) {
		echo $html; // phpcs:ignore WordPress.Security.EscapeOutput -- HTML do plugin khác sinh, trả nguyên trạng.
		return;
	}

	// Regex đệ quy: khớp một khối <div>...</div> cân bằng (kể cả div lồng nhau).
	$filtered = preg_replace_callback(
		'~<div\b[^>]*>(?:[^<]++|<(?!/?div\b)|(?R))*</div>~is',
		static function ( $m ) {
			$text = strtolower( wp_strip_all_tags( $m[0] ) );
			return false !== strpos( $text, HEADLESS_CRON_NOTICE_NEEDLE ) ? '' : $m[0];
		},
		$html
	);

	// preg_* trả null khi vượt backtrack limit — khi đó giữ nguyên output, thà thấy
	// notice thừa còn hơn nuốt mất mọi notice khác của admin.
	echo ( null === $filtered ) ? $html : $filtered; // phpcs:ignore WordPress.Security.EscapeOutput
}

foreach ( array( 'admin_notices', 'all_admin_notices', 'network_admin_notices', 'user_admin_notices' ) as $hook ) {
	add_action( $hook, 'headless_cron_notice_open', PHP_INT_MIN );
	add_action( $hook, 'headless_cron_notice_close', PHP_INT_MAX );
}
