CREATE TABLE Users (
    user_id SERIAL PRIMARY KEY, -- 자동으로 숫자 올라가는 고유 ID
    email VARCHAR(255) UNIQUE NOT NULL, -- 이메일 중복 불가, 필수 입력
    password_hash VARCHAR(255) NOT NULL, -- 암호화된 비밀번호
    nickname VARCHAR(50) UNIQUE NOT NULL, -- 닉네임 중복 불가! 필수 입력
    -- 권한 (기본값은 일반 유저)
    role VARCHAR(20) DEFAULT 'USER' CHECK (role IN ('USER', 'ADMIN')),
    is_active BOOLEAN NOT NULL DEFAULT true,  -- 계정 활성화 여부 (탈퇴, 이메일 인증 등)
    is_blocked BOOLEAN NOT NULL DEFAULT false, -- 악성 유저 차단 여부
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP, -- 가입 시간
    -- 소셜 로그인 테스트용
    provider VARCHAR(20) NOT NULL DEFAULT 'LOCAL',
    provider_id VARCHAR(255),
    CONSTRAINT uq_provider_provider_id UNIQUE (provider, provider_id)
);

CREATE TABLE User_Profiles (
    user_id INTEGER PRIMARY KEY REFERENCES Users(user_id) ON DELETE CASCADE,
    -- 유저 직접 입력 (문장 배열)
    user_input JSONB NOT NULL DEFAULT '[]', -- (예: ["새우 알레르기 있어요", "매운 음식 좋아해요"])
    -- AI 분석 데이터
    allergies JSONB,                         -- 감지된 알레르기/기피 식품
    dietary_restrictions JSONB,              -- 감지된 식이 제한 (채식, 비건 등)
    preferred_ingredients JSONB,             -- 선호 재료
    disliked_ingredients JSONB,              -- 기피 재료
    preferred_categories JSONB,              -- 선호 카테고리
    frequently_used_ingredients JSONB,       -- 자주 언급한 재료
    taste_keywords JSONB,                    -- 자주 언급한 맛 키워드 (예: ["매운", "담백한"])
    cooking_skill VARCHAR(10) CHECK (cooking_skill IN ('easy', 'normal', 'hard')),
    preferred_cooking_time INTEGER,          -- 선호 조리 시간 (분)
    serving_size NUMERIC(4, 1),              -- 주로 몇 인분
    recent_recipe_ids JSONB,                 -- 최근 추천받은 레시피 ID 목록
    ai_analyzed_at TIMESTAMP WITH TIME ZONE, -- 마지막 AI 분석 시간
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- pgvector 확장 기능 켜기
CREATE EXTENSION IF NOT EXISTS vector;

-- 승인된 레시피 테이블
CREATE TABLE Recipes (
    recipe_id SERIAL PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    ingredients JSONB NOT NULL,
    ingredients_raw TEXT NOT NULL,
    instructions JSONB NOT NULL,
    servings NUMERIC(4, 1) NOT NULL,                 -- 몇 인분 (예: 2.0)
    cooking_time INTEGER NOT NULL,                   -- 조리 시간 (분)
    calories INTEGER,                                -- 칼로리 (kcal)
    difficulty VARCHAR(10) NOT NULL CHECK (difficulty IN ('easy', 'normal', 'hard')),
    category JSONB NOT NULL,                         -- 음식 카테고리 배열
    tags JSONB NOT NULL DEFAULT '[]',                -- 태그 배열
    tips JSONB NOT NULL DEFAULT '[]',                -- 조리 팁 배열
    content TEXT,                                    -- 자유 형식 레시피 글 (선택)
    video_url VARCHAR(512),
    image_url VARCHAR(512),
    is_active BOOLEAN NOT NULL DEFAULT true,         -- 검색 노출 여부
    author_type VARCHAR(20) NOT NULL CHECK (author_type IN ('ADMIN', 'USER')) DEFAULT 'ADMIN',
    author_id INTEGER REFERENCES Users(user_id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    embedding VECTOR(1536)
);

-- 유저가 제출한 레시피 대기 테이블 (어드민 승인 후 Recipes로 이동)
CREATE TABLE Pending_Recipes (
    pending_recipe_id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES Users(user_id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    content TEXT NOT NULL,                                    -- 유저가 자유 형식으로 작성한 레시피 글
    ingredients JSONB,
    ingredients_raw TEXT,
    instructions JSONB,
    servings NUMERIC(4, 1),
    cooking_time INTEGER,
    calories INTEGER,
    difficulty VARCHAR(10) CHECK (difficulty IN ('easy', 'normal', 'hard')),
    category JSONB,
    tags JSONB,
    tips JSONB,
    video_url VARCHAR(512),
    image_url VARCHAR(512),
    is_active BOOLEAN NOT NULL DEFAULT true,         -- 유저가 취소/삭제할 때 쓸 플래그
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING'
        CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED')),
    admin_note TEXT,                                 -- 반려 사유 등 어드민 메모
    reviewed_at TIMESTAMP WITH TIME ZONE,            -- 승인/반려 처리 시간
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE Chat_Rooms (
    room_id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES Users(user_id) ON DELETE CASCADE,
    title VARCHAR(100) DEFAULT '새로운 레시피 상담', -- LLM이 지어줄 방 제목
    is_active BOOLEAN NOT NULL DEFAULT true,         -- 유저가 채팅방 삭제(숨김)할 때 쓸 플래그
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE Chat_Messages (
    message_id SERIAL PRIMARY KEY,
    room_id INTEGER NOT NULL REFERENCES Chat_Rooms(room_id) ON DELETE CASCADE,
    role VARCHAR(20) NOT NULL CHECK (role IN ('user', 'model')),
    content TEXT NOT NULL,
    recipe_ids JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE Likes (
    like_id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES Users(user_id) ON DELETE CASCADE,
    recipe_id INTEGER NOT NULL REFERENCES Recipes(recipe_id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, recipe_id)
);

CREATE TABLE Scraps (
    scrap_id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES Users(user_id) ON DELETE CASCADE,
    recipe_id INTEGER NOT NULL REFERENCES Recipes(recipe_id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, recipe_id)
);

CREATE TABLE Recipe_Stats (
    recipe_id INTEGER PRIMARY KEY
        REFERENCES Recipes(recipe_id) ON DELETE CASCADE,
    likes_count INTEGER NOT NULL DEFAULT 0,
    scrap_count INTEGER NOT NULL DEFAULT 0
);

-- Likes 트리거 함수
CREATE OR REPLACE FUNCTION update_likes_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE Recipe_Stats SET likes_count = likes_count + 1 WHERE recipe_id = NEW.recipe_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE Recipe_Stats SET likes_count = likes_count - 1 WHERE recipe_id = OLD.recipe_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_likes_count
AFTER INSERT OR DELETE ON Likes
FOR EACH ROW EXECUTE FUNCTION update_likes_count();

-- Scraps 트리거 함수
CREATE OR REPLACE FUNCTION update_scrap_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE Recipe_Stats SET scrap_count = scrap_count + 1 WHERE recipe_id = NEW.recipe_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE Recipe_Stats SET scrap_count = scrap_count - 1 WHERE recipe_id = OLD.recipe_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_scrap_count
AFTER INSERT OR DELETE ON Scraps
FOR EACH ROW EXECUTE FUNCTION update_scrap_count();
