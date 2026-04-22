# API 서버 담당자 작업 정리

> 본 문서는 **API 서버(=naengo-api-server)** 담당자가 무엇을 해야 하는지 정리한 체크리스트다.
> AI 서버 / 프론트엔드 담당자는 자신의 영역과 인터페이스만 참고하면 된다.

---

## 0. 한 줄 정의

API 서버는 **"앱(프론트)과 1차로 마주하고, 도메인 데이터의 정본(source of truth)을 관리하며, AI 서버와 신뢰 가능한 채널로 통신하는 백엔드"** 다.
즉, 다음 세 가지가 핵심 책임이다.

1. **DB I/O 관리** — Users / Recipes / Scraps / Likes / Recipe_Stats / Fridge 등 정형 데이터의 CRUD를 단독 소유.
2. **인증/인가** — 자체 회원가입·소셜 로그인 → JWT 발급 → AI 서버까지 전달되는 토큰 체계의 출발점.
3. **AI 서버와의 통신** — 사용자 요청을 AI 서버에 위임하고, AI 서버가 만든 결과(추천 결과 / 임베딩 등)를 다시 DB에 반영.

---

## 1. 현재 코드베이스 인벤토리 (2026-04-22 기준)

### 이미 구현된 것

| 영역 | 파일 | 상태 |
|---|---|---|
| 부트스트랩 | `ApiServerApplication.java` | OK |
| 공통 응답 | `global/dto/ApiResponse.java` | OK |
| 보안 설정 | `global/config/SecurityConfig.java` | OK |
| JWT | `global/auth/JwtTokenProvider.java`, `JwtAuthenticationFilter.java`, `CustomUserDetailsService.java` | OK |
| 예외 | `global/exception/{CustomException, GlobalExceptionHandler, ErrorCode}.java` | OK (Recipe/Chat ErrorCode는 선언만 되어 있고 사용처 없음) |
| OAuth | `global/auth/oauth/{Kakao,Google}OAuthClient.java`, `KakaoTokenClient.java`, `OAuthUserInfo.java`, `DevOAuthController.java` | OK |
| User 도메인 | `domain/user/{entity,dto,repository,service,controller}/*` | OK (signup / login / social) |
| DB 스키마(초안) | `src/main/resources/db/mainFields.sql` | **정리 필요** (Users 테이블 중복 정의 등) |
| 마이그레이션 | `src/main/resources/db/V2__add_social_login_fields.sql` | **V1이 없음. Flyway/Liquibase 도입 결정 필요** |

### 아직 없는 것 (= 우리가 만들어야 할 것)

- **Recipe 도메인** (Entity / Repository / Service / Controller)
- **Recipe_Stats / Scrap / Like 도메인**
- **Chat_Rooms / Session_Logs 도메인** ← AI 서버와 공유 — *소유권 합의 먼저*
- **Fridge 도메인**
- **User 추가 기능** (마이페이지 / 선호도 수정 / 내가 쓴 글 / 내 스크랩 목록)
- **Admin 도메인** (레시피 승인·반려 / 사용자 차단)
- **AI 서버 통신 모듈** (HTTP 클라이언트, 서비스-투-서비스 인증, DTO 매핑)
- **DB 마이그레이션 도구 도입** (Flyway 권장)

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
  - 플로우:
    1. 사용자 레시피 작성 → `status = 'PENDING'`, `embedding = NULL`
    2. 관리자 승인 API 호출 → API 서버 트랜잭션에서 `status = 'APPROVED'` 변경
    3. 트랜잭션 **커밋 후** AI 서버 `/internal/embed` 호출 (내부 토큰 사용) → vector 반환
    4. API 서버가 `UPDATE recipes SET embedding = ? WHERE recipe_id = ?`
  - 3번 실패 시 승인 자체는 유지 (사용자 체감 우선). 실패 건은 재시도 큐 or cron 으로 `embedding IS NULL AND status = 'APPROVED'` 조회 후 재생성.
  - **대안 논의**: AI 서버가 DB 에 직접 UPDATE 하는 것도 가능하지만, `recipes` 테이블 쓰기 권한자를 API 서버로 한정하기 위해 이 방식을 택함(책임 경계 명확화).
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

### Phase 1. 기반 정리

- [x] `mainFields.sql` 의 **Users 테이블 중복 정의 제거 + `embedding VECTOR(3072) → VECTOR(1536)`**
- [ ] Flyway 의존성 추가(`build.gradle`) + 설정(`spring.flyway.*`)
- [ ] `V1__init.sql` 작성 — 현재 운영 스키마(정리 후 `mainFields.sql`) 기준. 기존 `V2__add_social_login_fields.sql` 와의 순서/중복 정합성 확인 (V1 에 provider 컬럼이 이미 들어있으면 V2 는 소셜 로그인 이전 구버전 DB 용이 됨 — 필요 시 분리/재작성)
- [ ] `application.yml` / `application.properties` 중복 정리 (둘 다 있음)
- [ ] 프로파일 분리 (`application-local.yml`, `application-prod.yml`) — AWS 배포 대비
- [ ] `ApiServerApplication.java` 구동 확인 + 헬스체크 엔드포인트 (`GET /health`)

### Phase 2. 도메인 구현 (의존성 순서)

순서대로 가는 게 안전. 위→아래로 의존.

1. [ ] **Recipe** (entity / repo / service / controller)
   - 등록(작성) → 상태 PENDING, `embedding = NULL`, `image_url` 은 S3 URL 문자열만 저장 (Phase 0-4)
   - 단건 조회 (APPROVED 만 일반 사용자에게)
   - 목록 조회 (페이징 + 정렬: 최신순 / 인기순)
   - 본인 작성 레시피 목록 (PENDING 포함)
   - 본인 작성 레시피 삭제
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

1. **무엇을 만들지** `docs/spec/` 아래에 `spec-template.md` 형식으로 명세서 작성
2. 명세서를 LLM(또는 본인)에게 전달 → 코드 생성
3. 받은 코드 검토, 수정 사항이 생기면 `docs/changes/` 아래에 `change-log-template.md` 형식으로 변경 이력 기록
4. 테스트 → 커밋 → 푸시

이렇게 하면 "왜 이렇게 짰지?" 가 사라지고, 다음 사람(또는 미래의 본인)이 명세서만 봐도 의도를 복원할 수 있다.

---

## 5. 의사결정 보류 항목 (TODO: 팀 논의)

- [x] ~~위 Phase 0 항목 전부~~ — 2026-04-22 확정
- [ ] **서비스-투-서비스 인증 구체안** (Phase 0-1 에서 "존재한다"까지만 결정. 내부 토큰 포맷·회전 주기는 Phase 3 구현 시 확정)
- [ ] **JWT secret 회전 정책** (kid 지원 여부 / 동시 배포 방식)
- [ ] **재료 분석 이미지 흐름 최종안** (프론트 → AI 직통 vs S3 임시 경유) — AI 서버 팀 결정 대기
- [ ] 통계(인기 레시피 / 스크랩 수 / 검색 실패율) 집계 — API 서버에서 할지, 별도 분석 파이프라인을 둘지
- [ ] 회원 탈퇴 시 작성 레시피·스크랩 처리 (하드 삭제 vs 익명화) — 현재 스키마는 `ON DELETE SET NULL` / `CASCADE` 로 갈려 있음
- [ ] 레시피 수정 불가 정책 — 정말 영구 불가인지, 작성자가 5분 이내 수정 가능 등 완화 여지가 있는지
- [ ] 임베딩 재시도 메커니즘 (DB 폴링 vs 메시지 큐 SQS)
- [ ] AWS 운영 세부: RDS 인스턴스 타입, S3 버킷 분리(prod/dev), CloudFront 사용 여부
