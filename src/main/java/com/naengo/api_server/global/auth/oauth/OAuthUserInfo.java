package com.naengo.api_server.global.auth.oauth;

/**
 * 소셜 제공자(카카오·구글)에서 가져온 사용자 정보 공통 포맷.
 *
 * @param providerId 제공자가 발급한 사용자 고유 ID
 * @param email      사용자 이메일 (제공자가 공개하지 않을 경우 placeholder 사용)
 */
public record OAuthUserInfo(String providerId, String email) {
}
