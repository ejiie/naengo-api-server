# API 서버 담당자 작업 정리

> 본 문서는 **API 서버(=naengo-api-server)** 담당자가 무엇을 해야 하는지 정리한 체크리스트다.
> AI 서버 / 프론트엔드 담당자는 자신의 영역과 인터페이스만 참고하면 된다.

> ### 🔗 외부 인터페이스 — AI 서버 API 문서 (필수 참조)
> - **AI 서버 OpenAPI/Swagger UI**: <http://43.201.62.254:8000/docs>
> - 본 문서에서 "AI 서버 호출" 이 등장하는 모든 지점(임베딩, 추천, 재료 분석 등)의 **요청/응답 스키마는 위 문서를 진실원본으로 본다**. tasks 문서 / 명세서 본문 / 코드 상의 가정과 위 문서가 어긋날 경우 **AI 서버 docs 가 우선**.
> - 새 명세 작성 또는 기존 명세 갱신 시 §4 "작업 절차" 의 0번 단계로 **이 URL 부터 확인** 한다.
> - 변경이 잦은 자원이므로 캡처 대신 **링크로 참조**. 끊어진 사실이 발견되면 곧장 본 문서 / 관련 명세 / `change-log` 에 기록.

---

## 0. 한 줄 정의

API 서버는 **"앱(프론트)과 1차로 마주하고, 도메인 데이터의 정본(source of truth)을 관리하며, AI 서버와 신뢰 가능한 채널로 통신하는 백엔드"** 다.
즉, 다음 세 가지가 핵심 책임이다.

1. **DB I/O 관리** — Users / Recipes / Scraps / Likes / Recipe_Stats / Fridge 등 정형 데이터의 CRUD를 단독 소유.
2. **인증/인가** — 자체 회원가입·소셜 로그인 → JWT 발급 → AI 서버까지 전달되는 토큰 체계의 출발점.
3. **AI 서버와의 통신** — 사용자 요청을 AI 서버에 위임하고, AI 서버가 만든 결과(추천 결과 / 임베딩 등)를 다시 DB에 반영.

> ### 인프라 진행 상황 (AWS)
> - **DB (PostgreSQL + pgvector)**: 현재 로컬 개발용만 구성. **실 AWS RDS 이관은 팀원 담당** — 담당자가 세팅 완료하면 이 섹션에 엔드포인트·접속 정보 주입 방식(IAM/Secret Manager/env) 업데이트.
> - **S3**: 이미지 업로드(presigned URL) 대상. **버킷 생성 및 IAM 권한 설정도 팀원 담당** — 생성 전까지 API 서버의 업로드 엔드포인트 구현은 **명세만 작성하고 코드 구현은 이연**.
> - **API 서버 자체 배포** (ECS/EC2): Step 8 에서 별도 결정.
> - 로컬 개발 기본값은 `application-local.yml` 에, 운영 주입 포맷은 `application-prod.yml` 에 env 자리표시자로 이미 준비됨.

---

## 1. 현재 코드베이스 인벤토리 (2026-05-02 갱신, Step 2 일부 완료 + V4 도입 결정)

### 이미 구현된 것

| 영역 | 파일 | 상태 |
|---|---|---|
| 부트스트랩 | `ApiServerApplication.java` | OK |
| 공통 응답 | `global/dto/ApiResponse.java` | OK |
| 보안 설정 | `global/config/SecurityConfig.java` | OK (`/health` permitAll 반영) |
| JWT | `global/auth/JwtTokenProvider.java`, `JwtAuthenticationFilter.java`, `CustomUserDetailsService.java` | OK |
| 예외 | `global/exception/{CustomException, GlobalExceptionHandler, ErrorCode}.java` | OK. 미사용 `ErrorCode` 는 **선언 시점에만 추가** 정책 도입 (ErrorCode.java 하단 주석 참조) |
| OAuth | `global/auth/oauth/{Kakao,Google}OAuthClient.java`, `KakaoTokenClient.java`, `OAuthUserInfo.java`, `DevOAuthController.java` | OK |
| User 도메인 | `domain/user/{entity,dto,repository,service,controller}/*` | OK (signup / login / social). 탈퇴·마이페이지는 Step 4 |
| 헬스체크 | `global/controller/HealthController.java` | OK (`GET /health`) |
| 설정 파일 | `application.yml` / `application-{local,prod}.yml` | OK (프로파일 분리, secret env 외부화, `aws.s3.*` 키 준비) |
| 마이그레이션 | `db/migration/V1__init.sql` (= 구 V4 가 V1 자리로 이동, fixes 적용), `V2__add_social_login_fields.sql`, `V3__add_user_deleted_at.sql` | **2026-05-02 V1 ↔ V4 통합 완료**. 구 `V1__init.sql` 폐기 + 구 `V4__fixed_schema.sql` 폐기. 새 V1 이 구 V4 의 설계를 흡수 (BIGSERIAL, fridge 보존, V2 와 충돌하던 unique 제약 제거 등). V2/V3 는 그대로 ALTER 로 누적. |
| 빌드 도구 | `build.gradle` | Flyway(core + pg) 추가됨 |
| Recipe 도메인 | `domain/recipe/{entity,repository,service,controller,dto}/*` | OK (create/read/delete + stats 동기화). 임베딩·승인 흐름은 Step 6/7 |
| 보조 유틸 | `global/auth/SecurityUtil`, `domain/user/support/AuthorDisplayName` | OK |
| 명세서 | `docs/spec/recipe-{create,read,delete}.md`, `docs/spec/upload-presigned-url.md`, `docs/spec/ai-server-contract.md` (2026-05-02 신설, AI 서버 OpenAPI 0.1.0 스냅샷·갭분석) | OK |
| 로컬 개발 환경 | `docker-compose.yml` (pgvector/pg16) | OK |
| 온보딩 / 가이드 | `README.md`, `docs/db-testing-guide.md` | OK |

### 아직 없는 것 (= 만들어야 할 것)

- ~~**V4 마이그레이션 통합**~~ — **2026-05-02 완료**. 옵션 (b) 변형 채택 (V1 폐기 + 구 V4 가 V1 자리로 이동, V2/V3 는 보존)
- **Upload (S3 presigned URL) 실제 구현** (명세 있음. 코드는 AWS S3 준비 후 — Step 2-4b)
- **Like / Scrap** (Step 3)
- **User 마이페이지 / 탈퇴 익명화** (Step 4)
- **Fridge / Chat (read-only)** (Step 5)
- **Admin 도메인** (Step 6)
- **AI 서버 연동 모듈** (Step 7)
- **통합 테스트 / 운영 준비** (Step 8) — `DemoApplicationTests` 는 `com.example.demo` 패키지에 있어 현재 컨텍스트 로딩 불가, Step 8 에서 재배치·재작성

---

## 1.5 V1 ↔ V4 통합 — 완료 (2026-05-02)

> **결정 (2026-05-02, 사용자 지시)**: 운영 미배포 단계이므로 V4 가 V1 자리를 **완전히** 차지한다. 구 V1 / 구 V4 를 모두 폐기하고, 새 V1 이 구 V4 의 설계를 흡수한다. V2 / V3 는 그대로 보존되어 ALTER 로 누적된다.
>
> 이는 [`docs/changes/V4-integration-issues.md`](changes/V4-integration-issues.md) 의 **옵션 (b) 변형** 에 해당한다. 협업자별 로컬 DB 는 `docker compose down -v` 로 wipe 필요.

### 적용된 변경 요약

| 항목 | Before | After |
|---|---|---|
| 마이그레이션 파일 | V1__init.sql + V2 + V3 + V4__fixed_schema.sql | **V1__init.sql (= 구 V4 + fixes) + V2 + V3** |
| `users.user_id` 등 PK | `BIGSERIAL` (구 V1) / `SERIAL` (구 V4) | `BIGSERIAL` (JPA `Long` 정합) |
| `users.password_hash` | NOT NULL (구 V1, V2 가 nullable 화) | nullable (V1 단계에서 이미 nullable, V2 는 no-op) |
| `users.provider`/`provider_id` | V2 가 추가 | V1 이 이미 보유, V2 의 `IF NOT EXISTS` 가 no-op |
| `uq_provider_provider_id` UNIQUE | V1 / V2 둘 중 한 곳에서 추가 | V2 에서 단독 추가 (V1 에서는 제외 → 중복 정의 충돌 회피) |
| `users.is_active` | 없음 | V1 에 추가 (계정 활성/탈퇴 토글) |
| `users.deleted_at` | V3 가 추가 | V3 그대로 유지 |
| `recipes` 컬럼 | `full_content` + `source` + `status` + `ingredients` 등 (구 V1) | `description` + `content` + `ingredients{name,amount,unit,type,note}` + `ingredients_raw` + `instructions` + `servings` + `cooking_time` + `calories` + `difficulty` + `category` + `tags` + `tips` + `video_url` + `is_active` + `author_type` + `embedding` (AI contract 정합) |
| `pending_recipes` | 없음 | **신규** — 사용자 제출 → 관리자 승인 → recipes 로 이동 |
| `chat_messages` | 없음 (구 V1 은 `session_logs`) | **신규** — AI 의 per-message 모델 정합 |
| `session_logs` | 있음 | **제거** |
| `chat_rooms.room_id` | `VARCHAR(100)` (UUID) | `BIGSERIAL` (AI 응답 `room_id: integer` 정합) |
| `user_profiles` | 없음 (구 V1 은 `users.preferences JSONB`) | **신규** — preferences 를 풍부한 컬럼으로 분리 |
| `recipe_stats` 카운터 갱신 | 애플리케이션 코드 (RecipeStats.increment 등) | **DB 트리거** (`trigger_likes_count`, `trigger_scrap_count`). 추가로 `trigger_recipe_stats_create` 가 recipe INSERT 시 row(0,0) 자동 생성 |
| `fridge` | V1 에 있음 | V1 에 보존 (구 V4 에서 누락됐던 것 복원) |
| 인덱스 | 기본 | 추가: `idx_recipes_video_url` (PARTIAL), `idx_pending_recipes_user_id`, `idx_chat_messages_room_id`, 기타 |

### 적용된 코드 변경 요약 (2026-05-02 동시 PR)

- 엔티티
  - `User`: `preferences` 제거, `isActive` / `deletedAt` 추가 → `UserProfile` 은 미구현 (DB 만 준비, 엔티티는 Step 4 마이페이지 시점)
  - `Recipe`: 전면 재작성 — `source`/`status`/`fullContent` 폐기, `authorType` 신설, AI contract 의 11개 필드 모두 매핑
  - `RecipeStats`: 카운터 increment/decrement 메서드 제거 (DB 트리거가 처리). row 자체도 `trigger_recipe_stats_create` 가 자동 생성
  - 신규 `PendingRecipe` 엔티티 + `PendingRecipeRepository`
  - `Ingredient` record: `{name, amount}` → `{name, amount, unit, type, note}` (AI `IngredientItem` 정합)
- enum
  - `RecipeSource` 폐기 → `RecipeAuthorType` (ADMIN/USER) 신설
  - `RecipeStatus` 보존 — 이제 `PendingRecipe` 와 응답 DTO 에서만 사용
- 서비스
  - `RecipeService.create()` → `pending_recipes` INSERT
  - `RecipeService.listMine()` → `pending_recipes` 조회. 응답 DTO 도 `PendingRecipeListResponse` 신규
  - `RecipeService.listApproved()` → `recipes` 의 `is_active=true` 조회 (status 컬럼 없음)
  - `RecipeService.detail()` → `recipes` 만. PENDING 분기 / RECIPE_NOT_APPROVED 제거
  - `RecipeService.delete()` → 본인 `pending_recipe` hard delete (recipes 삭제는 admin Step 6)
  - `RecipeStats` 트랜잭션 INSERT 코드 제거, `session_logs` 선행 NULL 처리 코드 제거
- DTO 8개 갱신: `RecipeCreateRequest/Response`, `RecipeListItemResponse`, `RecipeDetailResponse`, 신규 `PendingRecipeListItemResponse`/`PendingRecipeListResponse`
- ErrorCode: `RECIPE_NOT_APPROVED` 제거, `PENDING_RECIPE_NOT_FOUND` 추가
- 빌드: `./gradlew build -x test` PASS

### 후속 작업

- [x] 1.5-a. AI 서버 docs 정독 → 갭분석 (`docs/spec/ai-server-contract.md`)
- [x] 1.5-b. V4 1차 작성 → 통합 이슈 12건 발견 → 옵션 (b) 변형 채택 → V1 자리로 이동 + fixes
- [x] 1.5-b'. ~~V4 재작성~~ — 본 PR 에서 V1 으로 흡수 완료
- [ ] 1.5-c. **로컬 DB 재기동 검증**: `docker compose down -v && docker compose up -d && ./gradlew bootRun` 으로 V1→V2→V3 자동 적용 + Hibernate `validate` 통과 확인
- [x] 1.5-d. `docs/db-testing-guide.md` Flyway 기대값 표 갱신 (V1~V3, V4 제거)
- [x] 1.5-e. `README.md` 의 마이그레이션 문구 갱신 (V1~V3)
- [x] 1.5-f. 본 문서 §1 인벤토리 갱신
- [x] 1.5-g. 엔티티·서비스·DTO 갱신 — 위 "코드 변경 요약" 참조
- [ ] 1.5-h. `SPEC-20260422-02/03/04` v2 명세 발행 (입력/응답 schema 가 V4 기반으로 바뀜) — change-log 메모는 이미 `docs/changes/SPEC-20260422-02-CL01.md`
- [ ] 1.5-i. AI 서버 팀과 §5 보류 항목 합의 회의
- [ ] 1.5-j. Step 6 (Admin 승인) 구현 시 `pending_recipes → recipes` 이동 트랜잭션 설계
- [ ] 1.5-k. AI 서버가 우리 `recipes.embedding` 을 채우는 메커니즘 합의 (옵션 B 잠정)

---

## 2. 내가(=API 서버 담당자) 해야 할 일 — 단계별

### Phase 0. 사전 결정 (2026-04-22 확정)

다른 파트(AI 서버, 프론트)와 같이 결정해야 결과적으로 재작업이 줄어드는 항목.

- [x] **AI 서버 ↔ API 서버 인증 방식** — 옵션 A (JWT secret 공유) 채택
  - 플로우:
    1. (자체) 프론트가 `/api/auth/login` 호출 → API 서버가 자체 JWT 발급
    2. (소셜) 프론트가 카카오/구글 SDK 로 access token 획득 → API 서버 `/api/auth/social/*` 로 전달 → API 서버가 검증 후 **동일한 형식의 자체 JWT 발급**
    3. 프론트는 로그인 방식과 무관하게 `Authorization: Bearer <API서버 JWT>` 하나만 사용
    4. AI 서버는 같은 secret 으로 JWT 검증 → `sub(=user_id)` 만 꺼내 사용. 사용자 정보가 더 필요하면 API 서버 조회 엔드포인트 호출.
  - **소셜 로그인이든 자체 로그인이든 AI 서버 입장에서는 동일한 JWT** 이므로 AI 서버는 로그인 방식을 알 필요가 없다(단일 검증 경로).
  - secret 은 환경변수로 양 서버가 공유. **회전 시 양 서버 동시 배포 또는 kid(key id) 기반 멀티 키 지원** 을 미리 설계해둘 것.
  - 서비스-투-서비스 호출(사용자 컨텍스트 없이 API 서버 → AI 서버 트리거, 예: 관리자 승인 후 임베딩 요청)은 사용자 JWT 가 없으므로 **별도 내부 토큰 또는 API Key** 헤더로 처리 → 이건 Phase 3 에서 구현 시점에 다시 정한다 (지금은 "존재한다"만 명시).
- [x] **Chat_Rooms / Session_Logs 의 쓰기 권한자** — AI 서버가 primary writer, API 서버는 read-only
  - AI 서버: INSERT / UPDATE (채팅 세션 생성, 메시지 누적, 추천 결과 기록, status 전이)
  - API 서버: SELECT 만. 제공 엔드포인트 — 내 채팅방 목록 / 특정 세션 조회 / 채팅방 숨김(`is_active=false`) 토글 정도
  - **DDL(테이블 생성·컬럼 추가·인덱스)은 API 서버가 Flyway 로 단독 관리** — AI 서버는 읽기/쓰기만, 스키마 변경은 하지 않음
  - AI 서버 팀과 **컬럼 시멘틱 변경이 필요할 때** 는 Flyway 마이그레이션 전 합의 필요 (공유 자원이므로)
- [x] **레시피 임베딩** — `VECTOR(1536)`, 관리자 승인 시점에 생성
  - 스키마: `recipes.embedding VECTOR(1536)` (OpenAI `text-embedding-3-small` 기준 또는 동급)
  - 원안 (2026-04-22 결정):
    1. 사용자 레시피 작성 → `status = 'PENDING'`, `embedding = NULL`
    2. 관리자 승인 API 호출 → API 서버 트랜잭션에서 `status = 'APPROVED'` 변경
    3. 트랜잭션 **커밋 후** AI 서버 `/internal/embed` 호출 (내부 토큰 사용) → vector 반환
    4. API 서버가 `UPDATE recipes SET embedding = ? WHERE recipe_id = ?`
  - 3번 실패 시 승인 자체는 유지 (사용자 체감 우선). 실패 건은 재시도 큐 or cron 으로 `embedding IS NULL AND status = 'APPROVED'` 조회 후 재생성.
  - **대안 논의**: AI 서버가 DB 에 직접 UPDATE 하는 것도 가능하지만, `recipes` 테이블 쓰기 권한자를 API 서버로 한정하기 위해 이 방식을 택함(책임 경계 명확화).
  - 🟡 **2026-05-02 갱신 — 재합의 필요**: AI 서버 OpenAPI(`docs/api-1.json`) 에 `/internal/embed` endpoint 가 부재. 현 시점에서 위 3~4 단계는 동작 불가. 두 갈래로 진행:
    - 옵션 (A) AI 서버에 `/internal/embed` 신설 요청 → 원안 그대로 진행
    - 옵션 (B) AI 서버가 자체 cron 으로 `WHERE embedding IS NULL AND status='APPROVED'` 조회 후 채움 — 즉 `embedding` 의 책임을 AI 서버에 완전 이양 (`§0 테이블별 책임` 표가 이미 그렇게 되어 있어 일관성 있음). API 서버 코드는 임베딩에 손대지 않음.
    - **잠정 채택**: 옵션 (B). AI 서버 팀 회신 시 변경 가능. Step 7 본 구현 시 재확인.
- [x] **이미지 업로드 — AWS S3 + presigned URL 방식**
  - 전제: 인프라를 AWS 로 올릴 예정 → S3 기본 사용. API 서버 인스턴스가 대용량 바이너리를 중계하는 구조는 처음부터 피한다.
  - 플로우 (레시피 사진):
    1. 프론트가 API 서버 `POST /api/uploads/presigned-url?type=recipe` 호출 → API 서버가 S3 presigned PUT URL + 최종 접근 URL 생성해 반환
    2. 프론트가 S3 에 직접 PUT 업로드
    3. 프론트가 레시피 생성 API 호출 시 최종 S3 URL 을 `image_url` 로 전달
    4. API 서버는 URL 프리픽스가 우리 버킷인지 검증만 하고 저장
  - 플로우 (재료 분석 사진):
    - 1안: 프론트 → AI 서버에 직접 업로드 (AI 서버가 분석 후 즉시 버림) → 이 흐름은 **AI 서버 책임이라 API 서버는 관여 안 함**
    - 2안: S3 임시 버킷 경유 (lifecycle rule 로 N시간 후 자동 삭제) → AI 서버가 키만 받아 분석
    - 선택은 AI 서버 팀이 결정하되, API 서버는 **재료 분석 이미지 저장을 하지 않는다** 는 것만 확정
  - S3 관련 설정(bucket, region, IAM role, CORS): `application.yml` 에 환경변수로 외부화. 로컬 개발에서는 LocalStack 또는 실 버킷(개발용) 사용.
  - 제한: MIME 화이트리스트(jpeg/png/webp), 최대 크기(예: 5MB), presigned URL 유효 시간(5분).
- [x] **마이그레이션 도구** — Flyway 확정
  - 이미 `V2__add_social_login_fields.sql` 이 존재 → Flyway 네이밍을 그대로 따라감
  - Phase 1 에서 `V1__init.sql` 을 작성(현재 운영 스키마 포함)하고 `mainFields.sql` 은 개발 레퍼런스로만 유지
- [x] **DB 공유** — AWS RDS PostgreSQL (pgvector 확장) 공유 DB
  - 같은 DB, 같은 스키마. AI 서버와 API 서버가 같은 데이터베이스에 접속.
  - 테이블별 책임:
    | 테이블 | Write | Read | DDL |
    |---|---|---|---|
    | `users` | API | API, AI | API |
    | `recipes` (embedding 컬럼 제외) | API | API, AI | API |
    | `recipes.embedding` | **AI** | AI (RAG 검색) | API |
    | `recipe_stats`, `scraps`, `likes` | API | API | API |
    | `chat_rooms`, `session_logs` | **AI** | API, AI | API |
    | `fridge` | API | API, AI | API |
  - MVP 에서는 양 서버가 **같은 DB role** 공유. 운영 안정화 후 별도 role 로 권한 최소화 검토(예: AI 서버 role 은 `users` UPDATE 불가).

### Phase 1. 기반 정리 — **완료 (Step 1, 2026-04-22)**

§6 Step 1 에서 세부 실행. 요약:

- [x] `mainFields.sql` 정리 (후에 Step 1 에서 **제거**. V1~V3 이 진실원본)
- [x] Flyway 의존성 추가 + `spring.flyway.locations: classpath:db/migration`
- [x] `V1__init.sql` 작성 (소셜 로그인 **이전** 스키마, BIGINT 통일, 인덱스 포함)
- [x] `V2__add_social_login_fields.sql` `db/migration/` 으로 이동 (V1 → V2 체인)
- [x] `V3__add_user_deleted_at.sql` (익명화용 컬럼)
- [x] `application.properties` 제거, `application.yml` 단일화
- [x] `application-local.yml` / `application-prod.yml` 분리
- [x] `GET /health` 엔드포인트 + SecurityConfig `permitAll`

### Phase 2. 도메인 구현 (의존성 순서)

순서대로 가는 게 안전. 위→아래로 의존.

1. [ ] **Recipe** (entity / repo / service / controller)
   - 등록(작성) → 상태 PENDING, `embedding = NULL`, `image_url` 은 S3 URL 문자열만 저장 (Phase 0-4)
   - 단건 조회 (APPROVED 만 일반 사용자에게)
   - 목록 조회 (페이징 + 정렬: 최신순 / 인기순)
   - 본인 작성 레시피 목록 (PENDING 포함)
   - 본인 작성 레시피 삭제
   - **수정 API 없음** (정책 확정: 영구 불가. 오탈자도 삭제 후 재작성)
   - 응답 DTO 에서 작성자 닉네임은 `users.nickname` 을 그대로 쓰되, 탈퇴 사용자(`deleted_at IS NOT NULL`)는 `"탈퇴한 사용자"` 로 치환
2. [ ] **Recipe_Stats**
   - Recipe 와 1:1, 좋아요/스크랩 수 캐시
   - Like / Scrap 트랜잭션에서 같이 증감
3. [ ] **Like**
   - 토글식: POST /api/recipes/{id}/like 한 번에 좋아요/취소
   - 중복 방지는 DB UNIQUE + 애플리케이션 처리
4. [ ] **Scrap**
   - 토글식
   - 사용자 스크랩 목록 조회
5. [ ] **User 마이페이지**
   - 내 정보 조회 / 수정 (닉네임)
   - 선호도(JSONB) 조회 / 수정
   - 비밀번호 변경 (LOCAL provider 한정)
   - **회원 탈퇴 (익명화 방식, 결정 사항 §5 참고)**
     * `DELETE /api/users/me` — 한 트랜잭션에서 처리
     * PII 필드 nullify + `nickname = '탈퇴한 사용자_<user_id>'` + `is_blocked = true` + `deleted_at = now()`
     * 본인의 `scraps`/`likes` 삭제, 해당 레시피들의 `recipe_stats` 카운터 감소
     * `chat_rooms` / `session_logs` 삭제는 **AI 서버와 합의 후 결정** (현재 보류)
     * 작성 레시피(`recipes.author_id`)는 유지, 표시 시점에 탈퇴 플래그로 닉네임 치환
6. [ ] **Chat_Rooms / Session_Logs (조회 전용)**
   - 내 채팅방 목록
   - 특정 채팅방의 세션 로그 조회
   - **쓰기는 AI 서버가 담당 (위 Phase 0 합의 기준)**
7. [ ] **Fridge**
   - 추가 / 조회 / 삭제
   - "사진 업로드 → 재료 추출" 자체는 AI 서버 책임. API 서버는 추출 결과를 받아 저장만.
8. [ ] **Admin**
   - 관리자 로그인 (User.role=ADMIN 으로 분기, 별도 로그인 화면은 프론트 책임)
   - 레시피 승인/반려 (PENDING → APPROVED/REJECTED)
   - 사용자 차단/차단 해제 (`User.block()` / `unblock()` 이미 있음)
   - 레시피 승인 시 흐름 (Phase 0-3 확정):
     1. 트랜잭션: `status = 'APPROVED'` UPDATE 후 커밋
     2. 커밋 이후 AI 서버 `/internal/embed` 호출 → vector(1536) 반환
     3. `UPDATE recipes SET embedding = ? WHERE recipe_id = ?`
     4. 실패 시 승인은 유지, 재시도 큐 또는 스케줄러가 `status='APPROVED' AND embedding IS NULL` 를 주기 재처리
9. [ ] **Upload (S3 presigned URL)**
   - `POST /api/uploads/presigned-url` → type(recipe/...) 을 받아 presigned PUT URL + 최종 접근 URL 반환
   - MIME 화이트리스트(jpeg/png/webp), 최대 크기, 유효 시간(5분)
   - 인증 필수 (USER)

### Phase 3. AI 서버 연동 모듈

- [ ] `global/client/ai/` 패키지 신설
- [ ] AI 서버 베이스 URL, 타임아웃, 재시도 설정 → `application.yml`
- [ ] WebClient 또는 RestClient (Spring Boot 3.2+) 채택
- [ ] 호출별 클라이언트:
  - `EmbeddingClient.requestEmbedding(recipeId, fullContent)` → `float[1536]` — **내부 토큰** 사용 (사용자 컨텍스트 없음, 관리자 승인 트리거)
  - `RagClient.recommend(userId, fridge, preferences, feedback)` — *필요 시*. 현재 설계상 프론트가 AI 서버로 직접 호출하고 결과만 세션 로그로 AI 서버가 DB 에 기록하므로 API 서버 경유 불필요할 수 있음 → AI 서버 팀과 최종 합의
  - 재료 이미지 분석은 **API 서버 경유하지 않음** (Phase 0-4 확정)
- [ ] 헤더 전략:
  - 사용자 요청 대리 호출: `Authorization: Bearer <user JWT 그대로 전달>`
  - 서비스-투-서비스 트리거(임베딩 요청 등): `X-Internal-Token: <공유 내부 토큰>` 혹은 서비스 전용 JWT (Phase 3 구현 시점에 최종 결정)
- [ ] 실패 시 fallback / 사용자에게 보일 에러코드 정의 (`ErrorCode`에 `AI_SERVER_UNAVAILABLE`, `EMBEDDING_FAILED` 등 추가)

### Phase 4. 운영 준비

- [ ] 통합 테스트 (`@SpringBootTest`) — 로그인/레시피 작성/스크랩 happy path 1개씩만이라도
- [ ] CORS 설정 (프론트 도메인 화이트리스트)
- [ ] 운영 환경 변수 분리 (`application-prod.yml`, secret 외부화)
- [ ] 로깅 정책 (요청 ID, 사용자 ID 마스킹)

---

## 3. 내가 **하지 않는** 일 (경계선 명확화)

오버리치를 막기 위해 명시.

- ❌ 재료 사진 → 재료 추출 모델 호출 자체 (= AI 서버)
- ❌ RAG 인덱스 빌드 / 벡터 검색 알고리즘 (= AI 서버)
- ❌ LLM 프롬프트 엔지니어링 (= AI 서버)
- ❌ 챗봇 대화 상태 머신 (= AI 서버, API 서버는 결과만 저장)
- ❌ 프론트엔드 화면, 소셜 로그인 SDK 호출 (= 프론트)
- ❌ 카카오/구글에서 access token 받기까지 (= 프론트가 받아 API 서버에 전달)

내가 하는 건: **그 결과물을 받아 검증·저장·재가공하고, 다시 정형화된 응답으로 내보내는 것**.

---

## 4. 작업 절차 (코드를 짜기 전에 매번 거치는 루틴)

0. **AI 서버 / 외부 인터페이스 확인** — 본 작업이 AI 서버 / S3 / OAuth 등 외부와 닿는다면 먼저 <http://43.201.62.254:8000/docs> 를 열어 **현재 시점의 contract** 를 확인한다. 이 단계 없이 명세를 쓰면 재작업이 거의 확실.
1. **무엇을 만들지** `docs/spec/` 아래에 `spec-template.md` 형식으로 명세서 작성. AI 서버 호출이 포함되는 명세는 §6 "외부 의존성" 에 호출하는 AI 서버 endpoint 경로·요청 모델·응답 모델을 docs URL 기반으로 명시한다.
2. 명세서를 LLM(또는 본인)에게 전달 → 코드 생성
3. 받은 코드 검토, 수정 사항이 생기면 `docs/changes/` 아래에 `change-log-template.md` 형식으로 변경 이력 기록
4. 테스트 → 커밋 → 푸시
5. **문서 최신화 (필수 루틴)**: 매 작업 후 아래 항목을 확인·갱신하고 같은 PR/커밋 또는 직후 커밋으로 반영한다.
   - `api-server-tasks.md §1 인벤토리` — 새 파일·새 영역이 생기면 한 줄 추가
   - `api-server-tasks.md §6 작업 순서` — 해당 Step/체크박스 상태 반영
   - `api-server-tasks.md §5 보류 항목` — 새로 파생된 결정 보류 사항이 생기면 추가
   - `README.md` — 새 환경변수·새 엔드포인트·새 전제 조건이 생기면 반영
   - 명세를 벗어난 구현 디테일은 `docs/changes/` 에 기록
   - **AI 서버 docs 와 어긋난 가정을 발견했다면** §1.5 V4 후보 항목에 추가하거나 별도 마이그레이션 / 명세 발행

이렇게 하면 "왜 이렇게 짰지?" 가 사라지고, 다음 사람(또는 미래의 본인)이 명세서만 봐도 의도를 복원할 수 있다.

---

## 5. 의사결정 보류 항목 (TODO: 팀 논의)

- [x] ~~위 Phase 0 항목 전부~~ — 2026-04-22 확정
- [ ] **서비스-투-서비스 인증 구체안** (Phase 0-1 에서 "존재한다"까지만 결정. 내부 토큰 포맷·회전 주기는 Phase 3 구현 시 확정)
- [ ] **JWT secret 회전 정책** (kid 지원 여부 / 동시 배포 방식)
- [ ] **재료 분석 이미지 흐름 최종안** (프론트 → AI 직통 vs S3 임시 경유) — AI 서버 팀 결정 대기
- [x] ~~통계(인기 레시피 / 스크랩 수 / 검색 실패율) 집계~~ — **우선순위 최하**. MVP 에서 제외하고, 도입 필요성이 확인되면 그때 별도 명세로 처리. `recipe_stats` 는 좋아요·스크랩 수 캐시 목적으로만 유지.
- [x] ~~회원 탈퇴 시 작성 레시피·스크랩 처리~~ — **익명화** 확정
  - User 테이블에 `deleted_at TIMESTAMPTZ NULL` 컬럼 추가 (마이그레이션 필요)
  - 탈퇴 API 호출 시:
    * `email`, `password_hash`, `provider_id`, `preferences` → `NULL` 로 초기화 (PII 제거)
    * `nickname` → `"탈퇴한 사용자"` 같은 고정 문자열. `UNIQUE` 제약 때문에 내부적으로는 `"탈퇴한 사용자_<user_id>"` 형태로 저장하고 응답 DTO 에서 꼬리표 제거하여 반환
    * `is_blocked = true` (재로그인 방지)
    * `deleted_at = now()`
  - 기존 `recipes.author_id` (`ON DELETE SET NULL`), `scraps`/`likes` (`CASCADE`) 는 익명화 모델과 맞지 않음 → **탈퇴 시 유저 row 는 삭제하지 않으므로 FK 트리거는 작동하지 않음**. 즉 author_id 는 그대로 유지되고, 조회 시 닉네임만 `"탈퇴한 사용자"` 로 보인다.
  - 탈퇴한 사용자의 스크랩/좋아요는 어떻게 할지: **삭제**(의미 없는 기록). 탈퇴 트랜잭션 안에서 `DELETE FROM scraps WHERE user_id = ?` / `DELETE FROM likes WHERE user_id = ?` + `recipe_stats` 카운터 보정.
  - 탈퇴한 사용자의 채팅 기록(`chat_rooms`, `session_logs`): PII 포함 가능성 높음 → **삭제**. AI 서버 팀과 "탈퇴 이벤트 발생 시 AI 서버도 이 사용자 관련 데이터 파기" 합의 필요 (정책 보류 항목).
- [x] ~~레시피 수정 불가 정책~~ — **영구 불가** 확정. 작성 후 어떤 경우에도 수정 API 를 제공하지 않는다. 오탈자 등도 삭제 후 재작성으로만 정정.
- [ ] 임베딩 재시도 메커니즘 (DB 폴링 vs 메시지 큐 SQS)
- [ ] AWS 운영 세부: RDS 인스턴스 타입, S3 버킷 분리(prod/dev), CloudFront 사용 여부
- [ ] **탈퇴 시 AI 서버 데이터 파기 정책** (위 익명화 결정에서 파생됨)
- [x] ~~**AI 서버 docs 와의 정합 점검 결과**~~ — 2026-05-02 완료. `docs/spec/ai-server-contract.md` 발행. 합의 필요한 항목은 아래로 분리.
- [ ] **AI 서버 contract 미합의 항목 (V4 범위 외, V5/V6 후보)** — `docs/spec/ai-server-contract.md §4` 발췌:
  - `chat_rooms.room_id` 타입 (현재 `VARCHAR(100)` vs AI 응답 `integer`) 정합
  - `session_logs` 폐기 + AI per-message 모델(`chat_messages`)로 수렴 여부
  - `recipes.status` (PENDING/APPROVED/REJECTED) 와 AI RAG 검색의 정합 (RAG 가 PENDING 까지 노출하는지)
  - `recipes.source` ('STANDARD'/'USER') ↔ AI `author_type` ('ADMIN'/'USER') 매핑 (현재 잠정: 응답 매퍼에서 `STANDARD → ADMIN`)
  - AI 서버에 `/internal/embed` 신설 여부 (Phase 0-3 옵션 B 잠정 채택)
  - AI 서버가 우리 DB 와 동일한 Postgres 인스턴스를 쓰는지 / 별도 DB 인지 (Phase 0-5 가 "공유" 였으나 contract 상 모델 차이가 커서 재확인 필요)
  - AI 서버 인증 도입 시점 — 현재 `user_id=1` 고정. Phase 0-1 JWT secret 공유는 그 이후
- [ ] **AI 서버 docs URL 의 운영/스테이지 분리** — 현재 `43.201.62.254:8000` 단일 호스트. 운영 분리 시점에 `application-prod.yml` 의 `ai.server.base-url` 갱신 필요

---

## 6. 작업 순서 (즉시 착수 가능한 순)

모든 Phase 0 결정이 끝난 현재, 다음 순서대로 진행한다. **각 스텝은 "AI 서버 docs 확인 → 명세서 작성 → LLM 코드 생성 → 검토·수정 → 커밋"** 루틴을 그대로 따른다 (§4).
의존성이 있는 스텝은 앞 스텝 완료 전에는 착수하지 않는다.

> ### 🎯 재조정된 우선순위 (2026-05-02)
> AI 서버 docs (`http://43.201.62.254:8000/docs`) 가 실제로 떠 있고 계약이 가시화됨에 따라 다음과 같이 우선순위를 재조정한다.
>
> | 순위 | 작업 | 비고 |
> |---|---|---|
> | **즉시** | **Step 1.5 — V4 마이그레이션** (V1 보정본) | AI 서버 docs 와 스키마 정합부터 맞춰야 이후 Step 5/6/7 의 계약이 흔들리지 않는다. 본 PR / 본 브랜치(`claude/update-migrations-api-docs-7Y4fU`) 의 1차 산출물. |
> | 1 | Step 7 일부 — **AI 서버 contract 검토 산출물** | docs URL 의 endpoint 표를 `docs/spec/ai-server-contract.md` 등으로 정리. 코드 작성보다 먼저. **Step 6 / Step 7 본 구현의 전제** 가 됨. |
> | 2 | Step 3 — Like / Scrap | Recipe 도메인 완성도 끝맺기. AI 서버 의존 없음. |
> | 3 | Step 4 — User 마이페이지 / 탈퇴 | Step 3 결과(스크랩/좋아요 삭제 대상) 필요. |
> | 4 | Step 5 — Fridge / Chat read-only | **Chat 의 read 모델이 V4 에서 결정될 가능성** 이 있어 Step 1.5 후로 미룸. |
> | 5 | Step 6 — Admin (승인 흐름) | Step 7 의 임베딩 endpoint 가 명확해진 이후. |
> | 6 | Step 7 본 구현 — AI 서버 클라이언트 | Step 1.5 와 "AI 서버 contract 검토 산출물" 완료 후. |
> | 7 | Step 2-4b — Upload 실 구현 | AWS S3 버킷 준비 시점에. 변동 없음. |
> | 마지막 | Step 8 — 운영 준비 / 통합 테스트 | 변동 없음. |
>
> **즉시 착수 항목 = Step 1.5**. 이후 일정은 위 표에 따른다.

### Step 1. 인프라 기반 정리 (선행, 다른 모든 스텝의 전제) — **완료 (실 기동 검증 포함)**
- [x] 1-1. `build.gradle` 에 Flyway 의존성 추가 (`spring-boot-starter-flyway` + `flyway-database-postgresql`. Spring Boot 4 는 `flyway-core` 만으로는 오토컨피그가 걸리지 않음)
- [x] 1-2. `application.properties` 제거 → `application.yml` 로 단일화
- [x] 1-3. 프로파일 분리: `application-local.yml`(기본), `application-prod.yml`(env 주입)
- [x] 1-4. `src/main/resources/db/migration/V1__init.sql` 작성 — 소셜 로그인 **이전** 스키마 (BIGINT 통일, 인덱스 포함, `embedding VECTOR(1536)`)
- [x] 1-5. 기존 V2 는 `db/migration/` 으로 이동하여 V1 → V2 체인 유지 (V2 는 그대로 소셜 로그인 필드 추가)
- [x] 1-6. `V3__add_user_deleted_at.sql` 작성
- [x] 1-7. `GET /health` 엔드포인트 추가 + SecurityConfig 에서 `permitAll`
- [x] 1-8. `./gradlew build` 통과 (테스트 제외 — 통합 테스트 DB 연동은 Step 8)
- [x] 1-9. **실 Postgres(pgvector/pg16, host 5434) 기동 검증 완료 (2026-04-29)**
  - Flyway V1→V2→V3 자동 적용
  - Hibernate `validate` 통과 (엔티티-스키마 정합)
  - `GET /health` → `{"status":"UP"}`

**산출물**: `build.gradle`, `application{,-local,-prod}.yml`, `db/migration/V1~V3.sql`, `HealthController`, `SecurityConfig` 업데이트

---

### Step 1.5. V4 마이그레이션 — V1 보정본 (**즉시 착수, 2026-05-02 신설**)
의존: Step 1 완료. **이후 모든 Step 의 전제**.

상세 결정·후보 항목은 §1.5 참조. 요약:

- [ ] 1.5-1. AI 서버 OpenAPI/Swagger (<http://43.201.62.254:8000/docs>) 정독 → `recipes` / `chat_rooms` / `session_logs` / `users` / `fridge` 와의 컬럼·타입·참조 정합 점검
- [ ] 1.5-2. 점검 결과를 `docs/spec/ai-server-contract.md` (신규, 임시) 에 표 형태로 캡처 — endpoint 목록 + 우리 DB 와 닿는 모델만
- [ ] 1.5-3. 정합되지 않는 항목을 `V4__correct_initial_schema.sql` 로 작성 (또는 더 좁은 이름으로 분할)
  - 알려진 첫 항목: `session_logs.selected_recipe_id` 에 `ON DELETE SET NULL` 부여 (`docs/spec/recipe-delete.md §4-5` 메모)
  - 추가 항목은 1.5-1 결과로 결정
- [ ] 1.5-4. `docker compose down -v && docker compose up -d && ./gradlew bootRun` 으로 V1→V2→V3→V4 자동 적용 검증
- [ ] 1.5-5. Hibernate `validate` 통과 확인 (엔티티 변경이 동반됐다면 함께 PR)
- [ ] 1.5-6. `docs/db-testing-guide.md` Flyway 기대값 표 4행으로 갱신 + V4 가 만지는 컬럼/제약 검증 항목 추가
- [ ] 1.5-7. `README.md` 의 "V1~V3" 문구 갱신, 본 문서 §1 인벤토리 갱신

**산출물**: `db/migration/V4__*.sql`, `docs/spec/ai-server-contract.md`, 갱신된 `db-testing-guide.md` / `README.md` / 본 문서

---

### Step 2. Recipe 도메인 + S3 업로드 — **부분 완료 (2026-04-22)**
의존: Step 1 완료.

- [x] 2-1. `docs/spec/recipe-create.md` (SPEC-20260422-02) 작성 + Recipe 작성 엔드포인트 구현
- [x] 2-2. `docs/spec/recipe-read.md` (SPEC-20260422-03) 작성 + 목록/단건/내 레시피 조회 구현
- [x] 2-3. `docs/spec/recipe-delete.md` (SPEC-20260422-04) 작성 + 본인 삭제 구현 (session_logs 참조 선행 NULL 처리 포함)
- [x] 2-4a. `docs/spec/upload-presigned-url.md` (SPEC-20260422-05) 작성
- [ ] 2-4b. **Upload 엔드포인트 실제 구현 — AWS S3 버킷 생성 후로 이연** (§0 인프라 메모)
- [x] 2-5. Recipe 작성 트랜잭션에서 `recipe_stats` INSERT (`RecipeService.create`)
- [x] 2-6. 작성자 닉네임 치환: `AuthorDisplayName` 공통 유틸 (`"탈퇴한 사용자_<id>"` → `"탈퇴한 사용자"`)

**구현 산출물**:
- `domain/recipe/entity/*` — Recipe, RecipeStats, RecipeSource, RecipeStatus, Ingredient
- `domain/recipe/repository/*` — RecipeRepository(JPQL 페치조인), RecipeStatsRepository
- `domain/recipe/dto/*` — Create/List/Detail DTO
- `domain/recipe/service/RecipeService`
- `domain/recipe/controller/RecipeController`
- `domain/user/support/AuthorDisplayName`
- `global/auth/SecurityUtil` — currentUserIdOrNull / hasRole
- `global/config/SecurityConfig` — `/api/recipes/my` 를 permitAll 규칙보다 먼저 `authenticated()` 로 보강
- `application.yml` — `aws.s3.*` 설정 키 (버킷 미설정 시 프리픽스 검증 스킵)

**검증**: `./gradlew build -x test` 통과. 실 DB 기동 테스트는 팀원의 AWS RDS 준비 후.

---

### Step 3. Engagement (Like, Scrap)
의존: Step 2 완료.

- [ ] 3-1. 명세서 `docs/spec/like-toggle.md` 작성 → 구현 (`POST /api/recipes/{id}/like` 토글)
- [ ] 3-2. 명세서 `docs/spec/scrap-toggle.md` + `docs/spec/scrap-list.md` 작성 → 구현
- [ ] 3-3. Like/Scrap 트랜잭션 안에서 `recipe_stats.likes_count` / `scrap_count` 증감
- [ ] 3-4. 동시성: `recipe_stats` UPDATE 에 낙관적 락 또는 `SELECT ... FOR UPDATE` 중 택 1

**산출물**: 명세서 3건, `domain/like/*`, `domain/scrap/*`

---

### Step 4. User 마이페이지 + 회원 탈퇴(익명화)
의존: Step 1 (deleted_at 마이그레이션) + Step 3 (스크랩/좋아요 삭제 대상).

- [ ] 4-1. 명세서 `docs/spec/user-me-get.md`, `docs/spec/user-me-update.md` 작성 → 구현 (닉네임·선호도)
- [ ] 4-2. 명세서 `docs/spec/user-password-change.md` 작성 → 구현 (LOCAL provider 한정)
- [ ] 4-3. 명세서 `docs/spec/user-withdraw.md` 작성 → 구현 (`DELETE /api/users/me`, 익명화 트랜잭션)
  - PII nullify + `nickname = '탈퇴한 사용자_<user_id>'` + `is_blocked = true` + `deleted_at = now()`
  - `scraps` / `likes` 삭제 + `recipe_stats` 카운터 보정
  - `chat_rooms` / `session_logs` 삭제는 AI 서버 합의 전까지 **보류**

**산출물**: 명세서 4건, `domain/user/*` 확장

---

### Step 5. Fridge + Chat (read-only)
의존: Step 4 완료 (사용자 컨텍스트 정비 후).

- [ ] 5-1. 명세서 `docs/spec/fridge-crud.md` → 구현 (추가·조회·삭제)
- [ ] 5-2. 명세서 `docs/spec/chat-room-list.md`, `docs/spec/chat-session-get.md` → 구현 (read-only)
- [ ] 5-3. 채팅방 숨김 토글 (`is_active=false`) — 필요 여부 확인 후 결정

**산출물**: 명세서 2~3건, `domain/fridge/*`, `domain/chat/*` (read-only)

---

### Step 6. Admin
의존: Step 2 완료 (승인 대상 Recipe 존재).

- [ ] 6-1. 명세서 `docs/spec/admin-recipe-approve.md` → 승인/반려 엔드포인트. 승인 시 AI 서버 임베딩 호출은 **Step 7 완료 후** 연동 (우선 DB 상태만 변경해도 OK — 임베딩은 NULL 인 채로 남음)
- [ ] 6-2. 명세서 `docs/spec/admin-user-block.md` → 차단/해제
- [ ] 6-3. 관리자 권한 가드 (`ADMIN` 역할 필수 어노테이션 또는 시큐리티 설정)

**산출물**: 명세서 2건, `domain/admin/*`

---

### Step 7. AI 서버 연동 모듈
의존: **Step 1.5 (V4)** 완료 + AI 서버 팀과 §0 phase 0-3 옵션 결정.

> **2026-05-02 갱신**: AI 서버 OpenAPI 스냅샷 (`docs/spec/ai-server-contract.md`) 작성 완료. **현 시점 AI 서버에 `/internal/embed` 가 부재** → Phase 0-3 옵션 (B) (AI 자체 cron) 잠정 채택. 옵션 (B) 가 유지되면 Step 7 에서 API 서버가 호출할 AI endpoint 가 사실상 없으므로 본 Step 의 산출물도 가벼워진다.

- [x] 7-0. **AI 서버 contract 문서화** — 완료. `docs/spec/ai-server-contract.md` 참조
- [ ] 7-1. (옵션 B 유지 시) **본 Step 보류** — API 서버가 AI 서버를 호출할 일이 없음. Step 6 승인 워크플로는 `embedding` 에 손대지 않고 `status` 만 변경
- [ ] 7-1'. (옵션 A 채택 시) `global/client/ai/` 패키지 신설, WebClient(또는 RestClient) Bean 등록
- [ ] 7-2. `application.yml` 에 AI 서버 base URL / 타임아웃 (호출 endpoint 가 생긴 시점에)
  - `ai.server.base-url: ${AI_SERVER_BASE_URL:http://43.201.62.254:8000}` (현재 dev 인스턴스 호스트)
  - 실제 path 는 `/api/v1/...` prefix (OpenAPI 기준) — `/internal/*` 가 신설되면 그 path 를 따른다
- [ ] 7-3. (옵션 A) `EmbeddingClient.requestEmbedding(recipeId, fullContent)` 구현. 실제 endpoint·요청·응답 schema 는 AI 측 신설 결과 따라감
- [ ] 7-4. (옵션 A) Admin 레시피 승인 트랜잭션 커밋 후 `EmbeddingClient` 호출 → `recipes.embedding` UPDATE (Step 6-1 과 연결)
- [ ] 7-5. (옵션 A·B 공통) `status='APPROVED' AND embedding IS NULL` 모니터링 (옵션 B 면 단순 메트릭, 옵션 A 면 재시도 잡)
- [ ] 7-6. `ErrorCode` 에 `AI_SERVER_UNAVAILABLE`, `EMBEDDING_FAILED` 추가 (옵션 A 시점에)

**산출물**: `global/client/ai/*`, 승인 흐름 완결, 재시도 잡

---

### Step 8. 운영 준비 (배포 직전)
의존: Step 1~7 완료.

- [ ] 8-1. CORS 설정 (프론트 도메인 화이트리스트)
- [ ] 8-2. 운영 secret 외부화 (JWT secret, DB 접속정보, AWS 키, 내부 토큰)
- [ ] 8-3. 로깅 정책 정리 (요청 ID, 사용자 ID 마스킹, PII 로그 금지)
- [ ] 8-4. 통합 테스트: 로그인 → 레시피 작성 → 관리자 승인 → 임베딩 생성 → 스크랩 → 탈퇴, 이 end-to-end 1개
- [ ] 8-5. AWS 배포 파일럿 (RDS + S3 + EC2/ECS 중 택일, 인프라 담당자와 합의)

**산출물**: 운영 가능 상태의 서버 + 최소 1개의 통합 테스트

---

### 병렬 처리 가능한 잡일 (언제든 가능)
스텝 의존성과 무관하게 시간 생기면 소화.

- [x] ~~README 에 로컬 개발 환경 구축 가이드 작성~~ — `README.md` + `docker-compose.yml` (pgvector/pg16) 커밋
- [x] ~~`.gitignore` 점검~~ — 공백 구분 버그 수정, `.env*` / `*.log` / `.DS_Store` 추가. `application-{local,prod}.yml` 은 **버전 관리에 포함** (env 자리표시자만 보유, 실 secret 은 환경변수)
- [x] ~~DB 관련 수동 검증 절차 문서화~~ — `docs/db-testing-guide.md` (Step 8 에서 JUnit 자동화 전까지 사용)
- [x] ~~`ErrorCode` 선언만 있고 쓰이지 않는 Recipe/Chat 코드 정리~~ — `RECIPE_ALREADY_LIKED/SCRAPPED`(토글 설계상 불필요), `CHAT_ROOM_NOT_FOUND/SESSION_NOT_FOUND`(Step 5 에서 재도입) 4건 제거. 정책: "사용되는 시점에 추가"
- [ ] 예외 메시지 i18n 필요 여부 검토
- [ ] pre-commit 훅 또는 Spotless 같은 포맷터 도입 검토
- [ ] 기동 시 표시되는 사소한 경고 2건 정리 (Step 1 검증 시 발견)
  - `HHH90000025: PostgreSQLDialect does not need to be specified explicitly` → `application.yml` 의 `spring.jpa.properties.hibernate.dialect` 라인 제거 (Hibernate 7 자동 선택)
  - `spring.jpa.open-in-view is enabled by default` → `application.yml` 에 `spring.jpa.open-in-view: false` 명시 (REST API 서버 정석)
