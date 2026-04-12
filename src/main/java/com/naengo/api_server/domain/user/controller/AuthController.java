package com.naengo.api_server.domain.user.controller;

import com.naengo.api_server.domain.user.dto.AuthResponse;
import com.naengo.api_server.domain.user.dto.LoginRequest;
import com.naengo.api_server.domain.user.dto.SignUpRequest;
import com.naengo.api_server.domain.user.dto.SocialLoginRequest;
import com.naengo.api_server.domain.user.service.AuthService;
import com.naengo.api_server.domain.user.service.SocialAuthService;
import com.naengo.api_server.global.dto.ApiResponse;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/auth")
@RequiredArgsConstructor
public class AuthController {

    private final AuthService authService;
    private final SocialAuthService socialAuthService;

    // ─── 자체 회원가입 / 로그인 ───────────────────────────────────────────

    @PostMapping("/signup")
    public ResponseEntity<ApiResponse<AuthResponse>> signUp(@Valid @RequestBody SignUpRequest request) {
        AuthResponse response = authService.signUp(request);
        return ResponseEntity
                .status(HttpStatus.CREATED)
                .body(ApiResponse.ok(response));
    }

    @PostMapping("/login")
    public ResponseEntity<ApiResponse<AuthResponse>> login(@Valid @RequestBody LoginRequest request) {
        AuthResponse response = authService.login(request);
        return ResponseEntity.ok(ApiResponse.ok(response));
    }

    // ─── 소셜 로그인 ────────────────────────────────────────────────────
    // 클라이언트가 카카오·구글에서 받은 액세스 토큰을 전달하면,
    // 서버가 검증 후 자체 JWT를 발급한다.

    @PostMapping("/social/kakao")
    public ResponseEntity<ApiResponse<AuthResponse>> kakaoLogin(@Valid @RequestBody SocialLoginRequest request) {
        AuthResponse response = socialAuthService.kakaoLogin(request);
        return ResponseEntity.ok(ApiResponse.ok(response));
    }

    @PostMapping("/social/google")
    public ResponseEntity<ApiResponse<AuthResponse>> googleLogin(@Valid @RequestBody SocialLoginRequest request) {
        AuthResponse response = socialAuthService.googleLogin(request);
        return ResponseEntity.ok(ApiResponse.ok(response));
    }
}
