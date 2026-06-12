<?php
/**
 * Plugin Name: Headless CORS
 * Description: Gửi CORS headers cho REST API và WPGraphQL để frontend Next.js gọi cross-origin.
 *
 * Origin được phép lấy từ hằng HEADLESS_FRONTEND_ORIGIN (define qua WORDPRESS_CONFIG_EXTRA
 * từ biến môi trường FRONTEND_ORIGIN). KHÔNG dùng wildcard '*'.
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

/**
 * Origin frontend được phép, hoặc '' nếu chưa cấu hình.
 */
function headless_allowed_origin() {
	return defined( 'HEADLESS_FRONTEND_ORIGIN' ) ? HEADLESS_FRONTEND_ORIGIN : '';
}

/**
 * Origin của request hiện tại có khớp frontend không.
 */
function headless_origin_matches() {
	$allowed = headless_allowed_origin();
	if ( ! $allowed ) {
		return false;
	}
	$request_origin = isset( $_SERVER['HTTP_ORIGIN'] ) ? $_SERVER['HTTP_ORIGIN'] : '';
	return $request_origin === $allowed;
}

/**
 * Gửi CORS headers cho REST/HTTP request và trả sớm cho preflight OPTIONS.
 */
function headless_send_cors_headers() {
	if ( ! headless_origin_matches() ) {
		return;
	}

	$origin = headless_allowed_origin();
	header( 'Access-Control-Allow-Origin: ' . $origin );
	header( 'Access-Control-Allow-Credentials: true' );
	header( 'Access-Control-Allow-Methods: GET, POST, OPTIONS, PUT, PATCH, DELETE' );
	header( 'Access-Control-Allow-Headers: Authorization, Content-Type, X-WP-Nonce' );
	header( 'Vary: Origin' );

	if ( isset( $_SERVER['REQUEST_METHOD'] ) && 'OPTIONS' === $_SERVER['REQUEST_METHOD'] ) {
		status_header( 204 );
		exit;
	}
}

// REST API: ghi đè CORS mặc định của core.
add_filter(
	'rest_pre_serve_request',
	function ( $value ) {
		headless_send_cors_headers();
		return $value;
	},
	0
);

// WPGraphQL (/graphql): dùng hook riêng để gắn headers vào response.
add_filter(
	'graphql_response_headers_to_send',
	function ( $headers ) {
		if ( headless_origin_matches() ) {
			$headers['Access-Control-Allow-Origin']      = headless_allowed_origin();
			$headers['Access-Control-Allow-Credentials'] = 'true';
			$headers['Access-Control-Allow-Headers']     = 'Authorization, Content-Type';
			$headers['Vary']                             = 'Origin';
		}
		return $headers;
	}
);
