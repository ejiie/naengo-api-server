CREATE TABLE Users (
    user_id      BIGSERIAL PRIMARY KEY,
    email        VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    nickname     VARCHAR(50)  NOT NULL UNIQUE,
    role         VARCHAR(20)  NOT NULL DEFAULT 'USER',
    is_blocked   BOOLEAN      NOT NULL DEFAULT FALSE,
    preferences  JSONB,
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    provider     VARCHAR(20)  NOT NULL DEFAULT 'LOCAL',
    provider_id  VARCHAR(255),
    CONSTRAINT uq_provider_provider_id UNIQUE (provider, provider_id)
);

-- 1. pgvector 확장 기능 켜기
CREATE EXTENSION IF NOT EXISTS vector;

-- 2. 정적 데이터 table
CREATE TABLE Recipes (
    recipe_id SERIAL PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    full_content TEXT NOT NULL, 
    image_url VARCHAR(512),
    source VARCHAR(20) NOT NULL DEFAULT 'STANDARD' CHECK (source IN ('STANDARD', 'USER')),
    author_id INTEGER REFERENCES Users(user_id) ON DELETE SET NULL,
    status VARCHAR(20) DEFAULT 'PENDING' CHECK (status IN ('APPROVED', 'PENDING', 'REJECTED')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    embedding VECTOR(1536), 
    ingredients JSONB 
);

CREATE TABLE Recipe_Stats (
    recipe_id INTEGER PRIMARY KEY REFERENCES Recipes(recipe_id) ON DELETE CASCADE,
    likes_count INTEGER DEFAULT 0,
    scrap_count INTEGER DEFAULT 0
);

CREATE TABLE Scraps (
    scrap_id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES Users(user_id) ON DELETE CASCADE,
    recipe_id INTEGER NOT NULL REFERENCES Recipes(recipe_id) ON DELETE CASCADE, -- 레시피가 지워지면 스크랩 목록에서도 삭제!
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, recipe_id) -- 핵심! 똑같은 레시피를 여러 번 스크랩하는 거 방지
);

CREATE TABLE Likes (
    like_id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES Users(user_id) ON DELETE CASCADE,
    recipe_id INTEGER NOT NULL REFERENCES Recipes(recipe_id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP, -- 언제 좋아요 눌렀는지 (선택사항이지만 있으면 좋아!)
    UNIQUE(user_id, recipe_id) -- 한 번 누른 좋아요 또 못 누르게 방지!
);

CREATE TABLE Chat_Rooms (
    room_id VARCHAR(100) PRIMARY KEY, -- UUID로 생성
    user_id INTEGER NOT NULL REFERENCES Users(user_id) ON DELETE CASCADE,
    title VARCHAR(100) DEFAULT '새로운 레시피 상담', -- LLM이 지어줄 방 제목
    is_active BOOLEAN DEFAULT TRUE, -- 유저가 채팅방 삭제(숨김)할 때 쓸 플래그
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE Session_Logs (
    session_id VARCHAR(100) PRIMARY KEY,
    room_id VARCHAR(100) NOT NULL REFERENCES Chat_Rooms(room_id) ON DELETE CASCADE, -- ⭐️ 부모 채팅방 연결
    user_id INTEGER NOT NULL REFERENCES Users(user_id) ON DELETE CASCADE,
    
    extracted_ingredients JSONB, -- 분석된 재료들 (Context)
    user_feedback JSONB,         -- 대화 중 파악된 일회성 취향
    recommended_recipe_ids INTEGER[], -- 추천했던 레시피 ID 목록
    selected_recipe_id INTEGER REFERENCES Recipes(recipe_id), -- 최종 선택
    
    -- 이전 턴의 자잘한 채팅 텍스트들은 이 배열에 저장!
    chat_messages JSONB, 
    
    status VARCHAR(20) DEFAULT 'IN_PROGRESS' CHECK (status IN ('IN_PROGRESS', 'COMPLETED', 'ABORTED')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE Fridge (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES Users(user_id) ON DELETE CASCADE,
    ingredient_name VARCHAR(100) NOT NULL,
    amount VARCHAR(50), -- 두 가지 문제 존재. 하나, vision api가 양까지 잘 식별하는가. 둘, 양을 고려하면 ingredients로 하고 jsonb로 여러 개의 이름과 양을 담는 게 맞지 않은가.
    added_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
