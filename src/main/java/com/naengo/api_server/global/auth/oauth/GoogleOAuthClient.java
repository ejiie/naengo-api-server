package com.naengo.api_server.global.auth.oauth;

import com.naengo.api_server.global.exception.CustomException;
import com.naengo.api_server.global.exception.ErrorCode;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

/**
 * 구글 API를 호출하여 액세스 토큰으로 사용자 정보를 조회하는 클라이언트.
 *
 * <p>흐름: 클라이언트 앱 → (구글 토큰) → 우리 서버 → 구글 API 검증 → OAuthUserInfo 반환
 */
@Slf4j
@Component
public class GoogleOAuthClient {

    private static final String USER_INFO_URL = "https://www.googleapis.com/oauth2/v3/userinfo";

    private final RestClient restClient;

    public GoogleOAuthClient(RestClient.Builder builder) {
        this.restClient = builder.build();
    }

    /**
     * 구글 액세스 토큰으로 사용자 정보 조회.
     *
     * @param accessToken 클라이언트가 구글로부터 발급받은 액세스 토큰
     * @return 구글 사용자 고유 ID(sub)와 이메일
     */
    public OAuthUserInfo getUserInfo(String accessToken) {
        try {
            GoogleApiResponse response = restClient.get()
                    .uri(USER_INFO_URL)
                    .header("Authorization", "Bearer " + accessToken)
                    .retrieve()
                    .body(GoogleApiResponse.class);

            if (response == null || response.sub() == null) {
                throw new CustomException(ErrorCode.SOCIAL_AUTH_FAILED);
            }

            String email = response.email() != null
                    ? response.email()
                    : "google_" + response.sub() + "@social.naengo.com";

            return new OAuthUserInfo(response.sub(), email);

        } catch (RestClientException e) {
            log.warn("구글 API 호출 실패: {}", e.getMessage());
            throw new CustomException(ErrorCode.SOCIAL_AUTH_FAILED);
        }
    }

    // ─── 구글 API 응답 내부 DTO ────────────────────────────────────────────

    private record GoogleApiResponse(
            String sub,    // 구글 사용자 고유 ID
            String email
    ) {}
}
