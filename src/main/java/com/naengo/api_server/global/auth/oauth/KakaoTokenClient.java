package com.naengo.api_server.global.auth.oauth;

import com.naengo.api_server.global.exception.CustomException;
import com.naengo.api_server.global.exception.ErrorCode;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

/**
 * 카카오 인가 코드(Authorization Code)를 액세스 토큰으로 교환하는 클라이언트.
 *
 * <p>용도: 개발·테스트 환경에서 OAuth 콜백을 처리할 때만 사용.
 * 실제 모바일 앱은 SDK가 직접 액세스 토큰을 발급하므로 이 클래스가 불필요하다.
 */
@Slf4j
@Component
public class KakaoTokenClient {

    private final RestClient restClient = RestClient.create();

    @Value("${oauth.kakao.token-url}")
    private String tokenUrl;

    @Value("${oauth.kakao.rest-api-key:}")
    private String restApiKey;

    @Value("${oauth.kakao.redirect-uri}")
    private String redirectUri;

    /**
     * 인가 코드를 카카오 액세스 토큰으로 교환한다.
     *
     * @param authCode 카카오 인가 코드 (redirect_uri 로 전달된 code 파라미터)
     * @return 카카오 액세스 토큰
     */
    public String exchangeCodeForToken(String authCode) {
        if (restApiKey == null || restApiKey.isBlank()) {
            throw new CustomException(ErrorCode.SOCIAL_AUTH_FAILED);
        }

        String body = "grant_type=authorization_code"
                + "&client_id=" + restApiKey
                + "&redirect_uri=" + redirectUri
                + "&code=" + authCode;

        try {
            KakaoTokenResponse response = restClient.post()
                    .uri(tokenUrl)
                    .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                    .body(body)
                    .retrieve()
                    .body(KakaoTokenResponse.class);

            if (response == null || response.accessToken() == null) {
                throw new CustomException(ErrorCode.SOCIAL_AUTH_FAILED);
            }

            return response.accessToken();

        } catch (RestClientException e) {
            log.warn("카카오 토큰 교환 실패: {}", e.getMessage());
            throw new CustomException(ErrorCode.SOCIAL_AUTH_FAILED);
        }
    }

    // ─── 카카오 토큰 응답 내부 DTO ─────────────────────────────────────────

    private record KakaoTokenResponse(
            @com.fasterxml.jackson.annotation.JsonProperty("access_token") String accessToken,
            @com.fasterxml.jackson.annotation.JsonProperty("token_type")   String tokenType,
            @com.fasterxml.jackson.annotation.JsonProperty("expires_in")   Integer expiresIn
    ) {}
}
