# SPEC-20260502-01: AI 서버 API contract 스냅샷

## 0. 메타

| 항목 | 값 |
|---|---|
| 명세서 ID | `SPEC-20260502-01` |
| 도메인 | (외부 contract — AI 서버) |
| 기능명 | AI 서버 OpenAPI 0.1.0 의 우리 시스템과 닿는 부분 정리 |
| 작성자 | API 서버 담당자 |
| 작성일 | 2026-05-02 |
| 우선순위 | P0 (다른 모든 Step 의 입력) |
| 관련 명세서 | `SPEC-20260422-02~05` (Recipe / Upload), `api-server-tasks.md §1.5` (V4) |
| 원본 | `docs/api-1.json` (AI 서버가 제공한 OpenAPI 3.1.0 dump) |
| 스냅샷 시점 | AI 서버 OpenAPI `info.version = 0.1.0`, 본 문서 작성 시각 기준 |

> ⚠️ **본 문서는 명세 작성용이 아니라 "외부 contract 의 사실관계 캡처"**. 변경되면 새 SPEC 을 발행하지 말고 본 문서를 직접 갱신하고 영향받는 명세에 change-log 를 남긴다.

---

## 1. 목적 (Why)

AI 서버 docs (<http://43.201.62.254:8000/docs>, raw: `docs/api-1.json`) 와 우리 DB / API 의 가정이 어긋나는 지점을 한눈에 보기 위함. V4 마이그레이션 후보(`api-server-tasks.md §1.5`) 와 Step 5/6/7 명세 작성의 입력이 된다.

---

## 2. AI 서버 endpoint 표

| Method | Path | 인증 | 설명 | 요청 | 응답 |
|---|---|---|---|---|---|
| `GET` | `/` | 없음 | 헬스 | — | `{status, message}` |
| `GET` | `/api/v1/chat/rooms` | (없음, `user_id=1` 고정) | 활성 채팅방 목록 (updated_at DESC, `is_active=true`만) | — | `ChatRoomResponse[]` |
| `POST` | `/api/v1/chat/rooms` | 없음 | 새 채팅방 + 첫 메시지 (SSE) | `ChatRequest` | `text/event-stream` (`room`, `message`, `recipes` 이벤트) |
| `GET` | `/api/v1/chat/rooms/{room_id}` | 없음 | 메시지 시간순 목록 | path: `room_id: integer` | `ChatMessageResponse[]` |
| `POST` | `/api/v1/chat/rooms/{room_id}` | 없음 | 기존 채팅방 메시지 (SSE, 직전 10개 컨텍스트) | path: `room_id: integer` + `ChatRequest` | SSE |
| `DELETE` | `/api/v1/chat/rooms/{room_id}` | 없음 | 소프트 삭제 (`is_active=false`) | path: `room_id: integer` | `{message}` |
| `GET` | `/api/v1/recipes?ids=1&ids=2&...` | 없음 | ID 목록으로 레시피 일괄 조회 | query: `ids: integer[]` | `RecipeResponse[]` |
| `GET` | `/api/v1/admin/recipes?video_url=...` | 없음 | `video_url` 로 단건 조회 (등록 전 중복 확인) | query: `video_url: string` | `RecipeResponse` |

> **부재 항목**: `/internal/embed`, 추천 단독 endpoint, 재료 분석 단독 endpoint, 인증 endpoint. 추천은 모두 `POST /api/v1/chat/rooms*` SSE 안에 묶여 있다.

---

## 3. 컴포넌트 스키마 — 요약

### 3.1 `RecipeResponse` (RAG / 채팅 응답에서 사용)
| 필드 | 타입 | 필수 | 비고 |
|---|---|---|---|
| `id` | int | ✓ | `recipes.recipe_id` 와 동일하게 매핑되어야 함 |
| `title` | string | ✓ | |
| `description` | string | ✓ | **현재 우리 스키마에 없음** |
| `ingredients` | `IngredientItem[]` | (default `[]`) | element schema 확장됨 (§3.3) |
| `ingredients_raw` | string | ✓ | **현재 없음** |
| `instructions` | string[] | (default `[]`) | **현재 없음** (우리는 `full_content TEXT` 한 덩어리) |
| `servings` | number(float) | ✓ | **현재 없음** |
| `cooking_time` | int | ✓ | **현재 없음** (단위: 분) |
| `calories` | int \| null | optional | **현재 없음** |
| `difficulty` | enum `easy`/`normal`/`hard` | ✓ | **현재 없음** |
| `category` | string[] | (default `[]`) | **현재 없음** |
| `tags` | string[] | (default `[]`) | **현재 없음** |
| `tips` | string[] | (default `[]`) | **현재 없음** |
| `video_url` | string \| null | optional | **현재 없음** (그러나 `/api/v1/admin/recipes?video_url=` 가 이를 키로 검색하므로 인덱스 필요) |
| `image_url` | string \| null | optional | 우리 `recipes.image_url VARCHAR(512)` 와 일치 |
| `author_type` | enum `ADMIN`/`USER` | ✓ | **우리 `source ('STANDARD'/'USER')` 와 의미 충돌** — §4-1 참조 |

### 3.2 `ChatMessageResponse`
| 필드 | 타입 | 필수 |
|---|---|---|
| `message_id` | int | ✓ |
| `role` | string (`user`/`model`) | ✓ |
| `content` | string | ✓ |
| `recipes` | `RecipeResponse[]` \| null | optional |
| `created_at` | datetime | ✓ |

> 우리 `session_logs` 의 컬럼들(`extracted_ingredients`, `user_feedback`, `recommended_recipe_ids`, `selected_recipe_id`, `chat_messages JSONB`, `status`) 은 AI 응답 어디에도 매핑되지 않음. AI 측은 **per-message 테이블** (가칭 `chat_messages`) 을 쓰는 것으로 보임. §4-3 참조.

### 3.3 `IngredientItem`
| 필드 | 타입 | 필수 |
|---|---|---|
| `name` | string | ✓ |
| `amount` | string | ✓ |
| `unit` | string | ✓ |
| `type` | string | ✓ (메인/부재료 등) |
| `note` | string \| null | optional (default `""`) |

> 우리 `recipes.ingredients JSONB` 의 element 는 `{name, amount}` 만 받게 명세됨(`SPEC-20260422-02 §3.2`). AI 응답을 그대로 저장하려면 element schema 확장 필요.

### 3.4 `ChatRoomResponse`
| 필드 | 타입 |
|---|---|
| `room_id` | **int** |
| `title` | string |
| `created_at` / `updated_at` | datetime |

> 현재 우리 `chat_rooms.room_id` 는 `VARCHAR(100)`. **타입 불일치 → V4 후보**.

### 3.5 `ChatRequest`
| 필드 | 타입 | 필수 |
|---|---|---|
| `prompt` | string | ✓ |
| `image` | string \| null | optional (`data:image/jpeg;base64,...`) |

---

## 4. 우리 DB / 명세 와의 정합 갭

### 4-1. `recipes` — 컬럼 다수 누락 + `author_type` ↔ `source` 의미 충돌
- 누락 컬럼 (RecipeResponse 가 SSE 와 RAG 결과로 그대로 노출하므로 DB 보유 필요): `description`, `ingredients_raw`, `instructions`(text[] 또는 JSONB), `servings`(numeric), `cooking_time`(int), `calories`(int null), `difficulty`(enum/check), `category`(text[]), `tags`(text[]), `tips`(text[]), `video_url`(varchar) + index
- `IngredientItem` 의 `unit`/`type`/`note` 도 누락 → JSONB element schema 확장
- `source` 와 `author_type`:
  - 우리 `source`: `STANDARD`(운영자 시드) / `USER`(사용자 업로드)
  - AI 의 `author_type`: `ADMIN`(관리자가 등록) / `USER`(사용자 업로드)
  - 의미가 거의 같지만 **이름·값이 다름**. V4 에서 정합 결정 필요. 후보:
    - 옵션 (a) `source` 그대로 두고 응답 매핑 시 `STANDARD → ADMIN` 으로 변환
    - 옵션 (b) `recipes` 에 `author_type VARCHAR(20)` 컬럼을 새로 두고 점진적으로 `source` 를 deprecate
    - 옵션 (c) `source` 를 rename + check 제약 변경 (가장 큰 변경)
  - **추천**: 옵션 (a) 가 가장 작은 변경. V4 에 컬럼 변경 없이 매핑 레이어로 흡수. 단, AI 서버가 우리 DB 에 직접 INSERT/UPDATE 하는 경우는 대응 안됨 → AI 측이 우리 DB 를 직접 쓰는지 합의가 필요.

### 4-2. `chat_rooms.room_id` 타입 불일치
- 현재: `VARCHAR(100) PRIMARY KEY` (UUID 를 AI 서버가 생성한다고 가정)
- AI 응답: `room_id: integer`
- AI 서버는 자체 BIGSERIAL/INTEGER PK 를 쓰는 것으로 보임. 우리 스키마가 이를 따라가야 한다면:
  - `chat_rooms.room_id` → `BIGSERIAL PRIMARY KEY`
  - 의존하는 `session_logs.room_id` 도 BIGINT 로 함께 변경
- **단, 데이터 마이그레이션은 V4 가 신규 환경 기준이므로 0건 → 1줄 ALTER 로 충분**. 운영 환경에 데이터가 이미 있으면 별도 백필 필요 (현재 운영 미배포 상태이므로 부담 없음).

### 4-3. `session_logs` 가 AI 의 per-message 모델과 불일치
AI 의 `ChatMessageResponse` 는 명백히 다음 구조의 테이블 위에 있음:
```
chat_messages
  message_id   BIGSERIAL PK
  room_id      BIGINT FK → chat_rooms
  role         VARCHAR(10) CHECK (role IN ('user','model'))
  content      TEXT
  recipes      JSONB  -- RecipeResponse[] 캐시 또는 recipe_ids BIGINT[]
  created_at   TIMESTAMPTZ
```
- 우리 `session_logs` 의 `extracted_ingredients` / `user_feedback` / `recommended_recipe_ids` / `selected_recipe_id` / `chat_messages JSONB` / `status` 컬럼들은 **현재 AI API 에 등장하지 않음**. AI 측이 내부적으로 더 가질 가능성이 있으나 우리가 read 하는 구조는 위 6컬럼.
- 결정 필요: V4 에서
  - 옵션 (A) `session_logs` 를 폐기하고 `chat_messages` 테이블을 새로 만든다 (AI 서버가 실제 쓰는 테이블 이름과 합의 필요)
  - 옵션 (B) `session_logs` 는 그대로 두고, AI 가 별도로 `chat_messages` 를 만들도록 권한 위임 (혼재)
  - 옵션 (C) AI 와 합의 후 두 모델 중 하나로 수렴
- **현 시점 추천**: AI 서버 팀과 합의 전이므로 **V4 에는 포함하지 않고 §1.5 후보로만 유지**. 합의 후 V5/V6 로 분리 적용.

### 4-4. `recipes.status` (PENDING/APPROVED/REJECTED) 가 AI 측 contract 에 부재
- AI 의 RAG 검색 / `GET /api/v1/recipes` / `GET /api/v1/admin/recipes` 어디에도 `status` 필터 없음.
- 우리 `recipes.status` 는 우리 "노출 가시성" 정책 (PENDING 은 일반 목록에서 제외, ADMIN 만 승인) 에 종속. AI 가 이를 무시하고 RAG 검색 결과로 PENDING 을 넘길 가능성.
- 결정 필요:
  - 옵션 (A) AI 서버가 RAG 인덱스 빌드 시 `status='APPROVED' AND embedding IS NOT NULL` 만 포함하도록 합의
  - 옵션 (B) API 서버가 AI 응답을 받은 뒤 `status` 필터를 한 번 더 적용 (소프트 정합)
  - 옵션 (C) `status` 개념 자체를 폐기하고 "전부 노출" 로 정책 변경
- **V4 범위 외** — 합의 사항. `api-server-tasks.md §5 보류 항목` 에 등록.

### 4-5. `/internal/embed` endpoint 부재
- 현재 AI API 에 임베딩 단독 endpoint 없음. 모든 추천은 SSE 채팅 흐름 안.
- 우리 Phase 0-3 의 "관리자 승인 → AI `/internal/embed` 호출 → `recipes.embedding` UPDATE" 흐름은 **현 시점 동작 불가**.
- 옵션:
  - 옵션 (A) AI 서버가 `/internal/embed` 신설하기 전까지 `recipes.embedding` 을 NULL 로 두고, AI 서버가 RAG 인덱스를 빌드할 때 자체적으로 channel 외 임베딩 (예: 주기 cron 으로 우리 DB 의 `embedding IS NULL AND status='APPROVED'` 를 찾아 채움)
  - 옵션 (B) `embedding` 컬럼의 책임을 AI 서버에 완전 이양 — `api-server-tasks.md §0 테이블별 책임` 표는 이미 그렇게 되어 있음. 즉 AI 가 알아서 채우는 게 원안.
- **결정**: 원안(옵션 B)이 유지된다면 우리 코드에는 임베딩 호출 흔적 없이 그저 NULL 로 두면 됨. Phase 0-3 의 "API 서버 트랜잭션 커밋 후 AI 호출" 문구를 **"AI 서버가 자체 스케줄로 채움. API 서버는 임베딩에 손대지 않음"** 으로 수정 필요.

### 4-6. 인증 미구현
- AI docs `info.description` 명시: *"현재 사용자 인증이 구현되어 있지 않습니다. 모든 API는 임시로 user_id = 1 사용자를 기준으로 동작합니다."*
- Phase 0-1 (JWT secret 공유) 은 AI 서버 미구현 → 양 서버 토큰 통일은 차후. 현재 AI 서버를 직접 호출할 일이 있다면 user_id 가 무의미.
- 영향:
  - **API 서버가 AI 서버를 호출할 일이 사실상 없음** (관리자 승인 → 임베딩 호출 흐름이 위 §4-5 로 인해 사라졌으므로)
  - 프론트가 AI 서버를 직접 호출하는 SSE 채팅 흐름이 메인. user_id 는 추후 인증 도입 시 실 사용자로 치환되어야 함

---

## 5. 결론 — V4 가 처리할 것 / 처리하지 않을 것

### V4 에 포함 (= 즉시 처리, 본 PR / 후속 PR 의 1차 목표)
1. `recipes` 컬럼 추가:
   - `description TEXT`
   - `ingredients_raw TEXT`
   - `instructions JSONB` (string[])
   - `servings NUMERIC(4,1)`
   - `cooking_time INTEGER`
   - `calories INTEGER`
   - `difficulty VARCHAR(10) CHECK (difficulty IN ('easy','normal','hard'))`
   - `category JSONB` (string[])
   - `tags JSONB` (string[])
   - `tips JSONB` (string[])
   - `video_url VARCHAR(512)` + `CREATE INDEX ... ON recipes(video_url) WHERE video_url IS NOT NULL`
2. `recipes.ingredients JSONB` element schema 확장: `{name, amount, unit, type, note}` (DB 단 schema 강제는 없으나 우리 명세 / DTO / 응답 매핑을 정렬). DDL 변경 없음 — 명세 갱신만.
3. `session_logs.selected_recipe_id` FK → `ON DELETE SET NULL`

### V4 에 포함하지 않음 (합의·재설계 필요)
- `chat_rooms.room_id` 타입 변경 (VARCHAR → BIGINT/BIGSERIAL) — AI 서버가 우리 DB 와 같은 DB 인스턴스를 쓰는지 / 별도 DB 인지 합의 후 V5
- `session_logs` 폐기 / `chat_messages` 신설 — AI 서버 팀과 데이터 모델 합의 후 V5/V6
- `recipes.status` 와 AI RAG 의 정합 — 정책 합의 (보류 항목으로 등록)
- `recipes.source` ↔ `author_type` 정합 — 매핑 레이어로 처리, V4 컬럼 변경 없음
- `/internal/embed` 흐름 — Phase 0-3 결정 재확인 (옵션 B 원안 유지하면 V4 변경 없음)

---

## 6. 후속 작업 체크리스트

- [ ] 본 문서를 AI 서버 팀과 공유 → §4-2 / §4-3 / §4-4 / §4-5 합의
- [ ] V4 마이그레이션 `V4__align_recipe_with_ai_contract.sql` 작성 (§5 "V4 에 포함" 항목)
- [ ] `recipes` 엔티티 / DTO / 매퍼 갱신 — 새 컬럼 노출, `author_type` 매핑
- [ ] `SPEC-20260422-02` Recipe 작성 명세에 새 필드 반영 (Body 가 받을 필드 결정)
- [ ] `SPEC-20260422-03` Recipe 조회 명세의 응답 필드 갱신 (AI 응답과 같은 형태로 노출 결정 시)
- [ ] `api-server-tasks.md §0` 테이블별 책임 표 갱신 — 임베딩이 정말 AI 단독 작성이라면 명시 강화
- [ ] `api-server-tasks.md §5` 에 위 미합의 항목 등록

---

## 7. 변경 추적

본 문서가 갱신되면 영향받은 명세별 `change-log` 를 발행. 변경 시 `0. 메타` 의 "스냅샷 시점" 도 함께 갱신.
