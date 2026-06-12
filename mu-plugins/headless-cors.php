<?php
/**
 * Plugin Name: Headless CORS
 * Description: Gửi CORS headers cho REST API và WPGraphQL để frontend Next.js gọi cross-origin.
 *
 * Origin được phép lấy từ hằng HEADLESS_FRONTEND_ORIGIN (define qua WORDPRESS_CONFIG_EXTRA
 * từ biến môi trường FRONTEND_ORIGIN). Hỗ trợ NHIỀU origin phân cách dấu phẩy:
 *   FRONTEND_ORIGIN=https://food.example.com,https://staging.food.example.com
 * KHÔNG dùng wildcard '*'.
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

/**
 * Danh sách origin được phép (đã trim, bỏ phần tử rỗng).
 *
 * @return string[]
 */
function headless_allowed_origins() {
	if ( ! defined( 'HEADLESS_FRONTEND_ORIGIN' ) || ! HEADLESS_FRONTEND_ORIGIN ) {
		return array();
	}
	return array_values( array_filter( array_map( 'trim', explode( ',', HEADLESS_FRONTEND_ORIGIN ) ) ) );
}

/**
 * Origin của request hiện tại nếu nằm trong danh sách cho phép, ngược lại ''.
 */
function headless_request_origin_if_allowed() {
	$request_origin = isset( $_SERVER['HTTP_ORIGIN'] ) ? $_SERVER['HTTP_ORIGIN'] : '';
	if ( $request_origin && in_array( $request_origin, headless_allowed_origins(), true ) ) {
		return $request_origin;
	}
	return '';
}

/**
 * Gửi CORS headers cho REST request và trả sớm cho preflight OPTIONS.
 */
function headless_send_cors_headers() {
	$origin = headless_request_origin_if_allowed();
	if ( ! $origin ) {
		return;
	}

	header( 'Access-Control-Allow-Origin: ' . $origin );
	header( 'Access-Control-Allow-Credentials: true' );
	header( 'Access-Control-Allow-Methods: GET, POST, OPTIONS, PUT, PATCH, DELETE' );
	header( 'Access-Control-Allow-Headers: Authorization, Content-Type, X-WP-Nonce' );
	// Cho frontend đọc các header phân trang của REST (thay core rest_send_cors_headers)
	header( 'Access-Control-Expose-Headers: X-WP-Total, X-WP-TotalPages, Link' );
	header( 'Vary: Origin' );

	if ( isset( $_SERVER['REQUEST_METHOD'] ) && 'OPTIONS' === $_SERVER['REQUEST_METHOD'] ) {
		status_header( 204 );
		exit;
	}
}

// Gỡ CORS mặc định của core: rest_send_cors_headers cho phép MỌI origin
// (Access-Control-Allow-Origin: <origin> + Allow-Credentials: true) — quá mở.
// Lưu ý: core đăng ký hook này trong rest_api_default_filters() chạy ở
// rest_api_init (SAU khi mu-plugins load) → phải gỡ sau thời điểm đó.
add_action(
	'rest_api_init',
	function () {
		remove_filter( 'rest_pre_serve_request', 'rest_send_cors_headers' );
	},
	20
);

// REST API: chỉ gửi CORS cho origin nằm trong danh sách cho phép.
add_filter(
	'rest_pre_serve_request',
	function ( $value ) {
		headless_send_cors_headers();
		return $value;
	},
	0
);

// WPGraphQL (/graphql): mặc định plugin gửi Access-Control-Allow-Origin: *
// → LUÔN ghi đè khi đã cấu hình: origin của request nếu hợp lệ, ngược lại
// origin đầu tiên trong danh sách (origin lạ sẽ fail CORS check phía browser).
add_filter(
	'graphql_response_headers_to_send',
	function ( $headers ) {
		$origins = headless_allowed_origins();
		if ( $origins ) {
			$matched = headless_request_origin_if_allowed();
			$headers['Access-Control-Allow-Origin']      = $matched ? $matched : $origins[0];
			$headers['Access-Control-Allow-Credentials'] = 'true';
			$headers['Access-Control-Allow-Headers']     = 'Authorization, Content-Type';
			$headers['Vary']                             = 'Origin';
		}
		return $headers;
	}
);
