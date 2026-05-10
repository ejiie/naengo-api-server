# 세션 핸드오프 — 2026-05-08

> 본 문서는 컨텍스트 윈도우 종료 전 작업 상태를 캡처한 **다음 세션용 primer**.
> 빠른 catch-up: §1 (현 상태) → §3 (즉시 의사결정 필요) → §4 (다음 액션 후보) 순으로.

## 0. 메타

| 항목 | 값 |
|---|---|
| 핸드오프 시점 | 2026-05-08 |
| 시작 상태 | master @ commit `3af9124` (PR #5 머지 직후) |
| 종료 상태 | master @ commit `<PR #6 머지 SHA>` (사용자가 머지 완료) |
| 본 세션 PR | [#6](https://github.com/ejiie/naengo-api-server/pull/6) — 14 commits, 머지됨 |
| 작업 브랜치 | `claude/update-migrations-api-docs-7Y4fU` (계속 사용) |

---

## 1. 본 세션에서 완료된 일 (PR #5 → PR #6)

### 도메인 구현
| Step | 내용 | spec 수 |
|---|---|---|
| **3** Like / Scrap | 토글 endpoint + `/api/scraps/my`. DB 트리거가 카운터 자동 갱신 | 3 |
| **4** 마이페이지 | 조회 / 닉네임 수정 / 비밀번호 변경 / 회원 탈퇴(익명화) | 4 |
| **4 후속** 선호도 | `user_profiles` 직접 입력 4필드 PUT, AI 분석 영역은 read-only | 2 |
| **5** Chat read-only | 채팅방 목록 + 메시지 시간순 (AI 서버가 primary writer, 우리는 SELECT 만) | 2 |
| **6** Admin | pending 검토 / 승인·반려 (`pending_recipes → recipes` 이동) / 사용자 차단·해제 | 3 |

### 인증 / 보안
- `JwtAuthenticationEntryPoint` + `JwtAccessDeniedHandler` — 미인증 → **401 + ApiResponse 일관**
- JWT **HttpOnly Cookie** 발급/만료 + Authorization 헤더 병행 (`SPEC-20260507-01`)
- `POST /api/auth/logout` 신설

### 운영 (Step 8 부분 완료)
- **8-1** CORS — `allowCredentials=true` (쿠키 호환), env 분리
- **8-2** secret 외부화 점검 — `application-prod.yml` 의 `CORS_ALLOWED_ORIGINS` 등 강제, README env 표 갱신
- **8-3** 로깅 정책 — `RequestIdFilter` + MDC `requestId`/`userId` + PII 금지 정책 (`docs/changes/logging-policy.md`)
- **8-4** 통합 테스트 — Testcontainers + Spring Boot 4 RestClient. **19/19 PASS**

### 품질 / 정리
- Hibernate 경고 2건 제거 (`dialect` 명시 / `open-in-view: false`)
- 문서·코드 정합 audit + stale 영역 정리 (db-testing-guide §6~9 V4 정합 갱신)
- 구글 OAuth 미실현 명시 (`docs/changes/oauth-google-status.md`)

### 산출물 누계
- **22 specs** (v1 4 + v2 3 + 신규 15)
- **5 change-logs** + **2 새 change-logs** (auth-entry-point, logging-policy, oauth-google-status)
- 통합 테스트 **5 클래스 19건** (`src/test/java/com/naengo/api_server/integration/`)

---

## 2. 핵심 정책 결정 사항 (이 세션에서 확정)

| 결정 | 근거 / 위치 |
|---|---|
| 사용자 제출 → `pending_recipes`, 관리자 승인 시 `recipes` 로 **테이블 간 이동** (구 plan 의 status UPDATE 가 아님) | `SPEC-20260504-02 admin-recipe-review` |
| `recipe_stats` 카운터는 **DB 트리거 단독 책임** (애플리케이션이 inc/dec 안 함) | V1 trigger + Step 3 spec |
| 탈퇴 시 `users` 행 **보존** + PII nullify + 닉네임 꼬리표 + flag 토글. 본인의 `scraps`/`likes`/`pending_recipes`/`user_profiles` DELETE. `chat_*` **AI 합의 보류** | `SPEC-20260503-07 user-withdraw` |
| JWT 쿠키 + 헤더 양쪽 지원 — 헤더 우선, 쿠키 fallback. `allowCredentials=true` 고정 → CORS origin 와일드카드 불가 | `SPEC-20260507-01 auth-cookie` |
| 미인증 → **401**, 미인가 → **403** (Spring 기본 403 동작 정정) | `docs/changes/auth-entry-point.md` |
| 임베딩 채우기는 옵션 B (AI 자체 cron) **잠정 채택** | Phase 0-3 + `tasks.md §1.5` |
| 구글 OAuth 코드는 placeholder, **운영 비활성** | `docs/changes/oauth-google-status.md` |
| `fridge` 도메인 폐기 (Step 5 범위는 Chat 만) | `tasks.md §1.5` |

---

## 3. 즉시 의사결정 필요 (외부 합의)

마지막 사용자 질의 (AI 팀 합의 항목) 의 답변. 자세한 내용은 [`docs/spec/ai-server-contract.md §4`](../spec/ai-server-contract.md), [`tasks.md §5`](../api-server-tasks.md). 핵심만:

### 3.1 임베딩 옵션 A vs B
- **A (push)**: AI 서버가 `POST /internal/embed` 신설, API 서버가 admin 승인 시 호출 → 즉시 반영
- **B (pull, 잠정 채택)**: AI 자체 cron 으로 `embedding IS NULL AND is_active=true` 처리 → 지연 있음
- 결정 후 → Step 7 진행 가능

### 3.2 chat_rooms / chat_messages write 권한
- 현재 가정: AI 서버 = primary writer (Phase 0-2 합의)
- 미합의:
  - 같은 DB role 공유 vs 분리 role (운영 안정화 후)
  - 채팅방 숨김 토글: AI 서버 `DELETE` vs API 서버 `DELETE /api/chat/rooms/{id}` 신설 (**Step 5-2 보류**)
  - 탈퇴 시 chat 데이터 파기: webhook 통보 vs 직접 DELETE vs AI cron

### 3.3 그 외
- DB 인스턴스 공유 vs 분리 (Phase 0-5 가 "공유" 였으나 배포 시 재확인 필요)
- AI 서버 인증 도입 시점 (현재 `user_id=1` 고정) → JWT secret 공유 일정 결정
- JWT secret 회전 정책 (kid 지원 여부)
- 재료 분석 이미지 흐름 (프론트 → AI 직통 vs S3 임시 경유)

---

## 4. 다음 작업 후보 (우선순위 순)

| 종류 | 작업 | 의존 |
|---|---|---|
| **합의 후** | Step 7 AI 서버 연동 — 옵션 A 선택 시 `EmbeddingClient` 신설 | AI 팀 |
| **합의 후** | Step 5-2 채팅방 숨김 토글 endpoint | AI 팀 |
| **합의 후** | 탈퇴 시 chat 파기 동기화 | AI 팀 |
| **인프라 후** | Step 2-4b S3 presigned URL 실 구현 | AWS 인프라 |
| **인프라 후** | Step 8-5 AWS 배포 파일럿 | 인프라 담당자 |
| **즉시 가능** | 새 도메인 (검색 / 필터 / 댓글 등 미정 기능) | — |
| **즉시 가능** | refresh token + blacklist 도입 (보안 강화) | — |
| **즉시 가능** | 운영 시 file appender / log aggregation 결정 | — |
| **즉시 가능** | ArchUnit 으로 PII 로그 enforcement | — |

---

## 5. 다음 세션 시작 가이드

1. **상태 확인**:
   ```bash
   git checkout master && git pull
   docker compose down -v && docker compose up -d  # V4 schema 가 새 master 에 반영됨
   ./gradlew test  # 19/19 PASS — 안 통과하면 Docker daemon 확인
   ```
2. **읽을 문서 (이 순서로)**:
   - `docs/api-server-tasks.md` — §1 인벤토리 + §6 Step 진행 표
   - `docs/spec/ai-server-contract.md` — AI 서버와의 contract / 미합의 항목
   - 본 문서 §3 — 즉시 의사결정 필요 항목
3. **AI 서버 contract 변경 시**: `docs/api-1.json` 도 같이 갱신해야 (정책)
4. **로컬 DB wipe 필요한 경우**: V1 schema 변경 시. PR #5 / #6 머지 직후 한 번 wipe 권장.

---

## 6. 알려진 미흡 / 향후 개선

- 미인증 응답이 401 로 정합되었지만, **차단된 사용자(`is_blocked=true`) 가 살아있는 토큰으로 호출** 시도 401 — 명세상 403 USER_BLOCKED 와 다름. `JwtAuthenticationFilter` 가 catch 후 SecurityContext clear → EntryPoint 가 401 발화. 방어 in depth 로 수용 (사용자는 동일하게 차단됨)
- 비밀번호 변경 시 기존 토큰 강제 무효화 미적용 (stateless JWT 한계)
- 통합 테스트가 Docker 환경 의존 (CI 에서 Docker available 필요)

---

## 7. 본 세션 산출 commit graph (master 기준)

PR #6 머지 후 master 의 가장 최근 commit (위에서 아래로 시간 순):
- `chore(step8-2)` — secret 외부화 점검 + 구글 미실현 명시
- `feat(step8-3)` — 로깅 정책 + RequestIdFilter
- `feat(step8-1)` — CORS
- `test(step8-4)` — 통합 테스트 11건
- `chore(jpa)` — Hibernate 경고 정리
- `feat(auth-cookie)` — JWT 쿠키 + logout
- `docs(audit)` — 문서·코드 정합 audit
- `feat` — 선호도 endpoint + AuthEntryPoint
- `feat(step6)` — Admin
- `feat(step5)` — Chat read-only
- `feat(step4)` — 마이페이지 + 탈퇴
- `feat(step3)` — Like/Scrap
- `docs(step1.5-c)` — 로컬 DB 검증 완료 표기
- `docs` — AI 서버 docs 로컬 스냅샷 명시
