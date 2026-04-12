package com.naengo.api_server.domain.user.dto;

import jakarta.validation.constraints.NotBlank;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Getter
@NoArgsConstructor
public class SocialLoginRequest {

    // 클라이언트(앱/웹)가 카카오·구글로부터 발급받은 액세스 토큰
    @NotBlank(message = "액세스 토큰은 필수입니다.")
    private String accessToken;

    // 서버 내부(테스트 콜백)에서 직접 생성할 때 사용
    public SocialLoginRequest(String accessToken) {
        this.accessToken = accessToken;
    }
}
