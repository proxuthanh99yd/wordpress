<?php
/**
 * Plugin Name: Headless Hardening
 * Description: Bảo mật cơ bản cho WordPress chạy headless — tắt XML-RPC, chặn user
 *              enumeration qua REST, ẩn version WP, gỡ pingback header.
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

// Tắt XML-RPC (không cần cho headless, hay bị brute-force/pingback DDoS).
add_filter( 'xmlrpc_enabled', '__return_false' );

// Gỡ X-Pingback header.
add_filter(
	'wp_headers',
	function ( $headers ) {
		unset( $headers['X-Pingback'] );
		return $headers;
	}
);

// Ẩn <meta name="generator"> (lộ version WP).
remove_action( 'wp_head', 'wp_generator' );

// Chặn liệt kê users qua REST cho khách chưa đăng nhập (chống user enumeration).
add_filter(
	'rest_endpoints',
	function ( $endpoints ) {
		if ( is_user_logged_in() ) {
			return $endpoints;
		}
		unset( $endpoints['/wp/v2/users'] );
		unset( $endpoints['/wp/v2/users/(?P<id>[\d]+)'] );
		return $endpoints;
	}
);
