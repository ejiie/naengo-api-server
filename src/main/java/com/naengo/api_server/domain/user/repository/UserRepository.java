package com.naengo.api_server.domain.user.repository;

import com.naengo.api_server.domain.user.entity.AuthProvider;
import com.naengo.api_server.domain.user.entity.User;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface UserRepository extends JpaRepository<User, Long> {
    Optional<User> findByEmail(String email);

    boolean existsByEmail(String email);

    boolean existsByNickname(String nickname);

    // 소셜 로그인: 제공자 + 제공자 고유 ID로 사용자 조회
    Optional<User> findByProviderAndProviderId(AuthProvider provider, String providerId);
}
