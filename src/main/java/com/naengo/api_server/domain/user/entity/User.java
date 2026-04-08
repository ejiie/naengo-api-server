package com.naengo.api_server.domain.user.entity;

import jakarta.persistence.*;
import lombok.*;

import java.time.ZonedDateTime;
import java.util.Map;

@Entity
@Table(name = "users")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@Builder
@AllArgsConstructor
public class User {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "user_id")
    private Long userId;

    @Column(nullable = false, unique = true, length = 255)
    private String email;

    @Column(name = "password_hash", nullable = false, length = 255)
    private String passwordHash;

    @Column(nullable = false, unique = true, length = 50)
    private String nickname;

    @Column(nullable = false, length = 20)
    @Builder.Default
    private String role = "USER";

    @Column(name = "is_blocked", nullable = false)
    @Builder.Default
    private boolean isBlocked = false;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(columnDefinition = "jsonb")
    private Map<String, Object> preferences;

    @Column(name = "created_at", updatable = false)
    @Builder.Default
    private ZonedDateTime createdAt = ZonedDateTime.now();

    // 차단 상태 변경 (관리자용)
    public void block() {
        this.isBlocked = true;
    }

    public void unblock() {
        this.isBlocked = false;
    }

    // 선호도 업데이트
    public void updatePreferences(Map<String, Object> preferences) {
        this.preferences = preferences;
    }
}
