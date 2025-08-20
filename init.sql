CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    avatar_url TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_seen TIMESTAMP
);

CREATE TABLE IF NOT EXISTS rooms (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    is_private BOOLEAN DEFAULT FALSE,
    created_by INTEGER REFERENCES users(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS room_members (
    id SERIAL PRIMARY KEY,
    room_id INTEGER REFERENCES rooms(id) ON DELETE CASCADE,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    role VARCHAR(20) DEFAULT 'member', -- admin, moderator, member
    joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(room_id, user_id)
);

CREATE TABLE IF NOT EXISTS messages (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    room_id INTEGER REFERENCES rooms(id) DEFAULT 1,
    username VARCHAR(50) NOT NULL,
    content TEXT NOT NULL,
    message_type VARCHAR(20) DEFAULT 'text', -- text, image, file, system
    reply_to INTEGER REFERENCES messages(id),
    edited_at TIMESTAMP,
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS attachments (
    id SERIAL PRIMARY KEY,
    message_id INTEGER REFERENCES messages(id) ON DELETE CASCADE,
    filename VARCHAR(255) NOT NULL,
    file_url TEXT NOT NULL,
    file_type VARCHAR(100),
    file_size INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS message_reactions (
    id SERIAL PRIMARY KEY,
    message_id INTEGER REFERENCES messages(id) ON DELETE CASCADE,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    emoji VARCHAR(10) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(message_id, user_id, emoji)
);

CREATE INDEX IF NOT EXISTS idx_messages_created_at ON messages(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_user_id ON messages(user_id);
CREATE INDEX IF NOT EXISTS idx_messages_room_id ON messages(room_id);
CREATE INDEX IF NOT EXISTS idx_messages_content_gin ON messages USING gin(content gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_last_seen ON users(last_seen);
CREATE INDEX IF NOT EXISTS idx_room_members_room_user ON room_members(room_id, user_id);
CREATE INDEX IF NOT EXISTS idx_message_reactions_message ON message_reactions(message_id);

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_rooms_updated_at BEFORE UPDATE ON rooms
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

INSERT INTO rooms (id, name, description, is_private, created_by) 
VALUES (1, 'Общий чат', 'Основная комната для общения', FALSE, NULL)
ON CONFLICT (id) DO NOTHING;

INSERT INTO users (username, email) VALUES 
    ('admin', 'admin@example.com'),
    ('user1', 'user1@example.com'),
    ('user2', 'user2@example.com')
ON CONFLICT (username) DO NOTHING;

INSERT INTO room_members (room_id, user_id, role)
SELECT 1, id, CASE WHEN username = 'admin' THEN 'admin' ELSE 'member' END
FROM users
ON CONFLICT (room_id, user_id) DO NOTHING;

INSERT INTO messages (user_id, room_id, username, content, message_type)
SELECT 1, 1, 'admin', 'Добро пожаловать в чат! 👋', 'system'
WHERE NOT EXISTS (SELECT 1 FROM messages WHERE content = 'Добро пожаловать в чат! 👋');

CREATE OR REPLACE VIEW messages_with_details AS
SELECT 
    m.id,
    m.user_id,
    m.room_id,
    m.username,
    m.content,
    m.message_type,
    m.reply_to,
    m.edited_at,
    m.is_deleted,
    m.created_at,
    u.avatar_url,
    u.is_active as user_active,
    rm.name as reply_content,
    rm.username as reply_username,
    COUNT(mr.id) as reaction_count
FROM messages m
LEFT JOIN users u ON m.user_id = u.id
LEFT JOIN messages rm ON m.reply_to = rm.id
LEFT JOIN message_reactions mr ON m.id = mr.message_id
WHERE m.is_deleted = FALSE
GROUP BY m.id, u.avatar_url, u.is_active, rm.content, rm.username;

CREATE OR REPLACE FUNCTION search_messages(search_term TEXT, room_id_param INTEGER DEFAULT NULL, limit_param INTEGER DEFAULT 50)
RETURNS TABLE (
    id INTEGER,
    user_id INTEGER,
    room_id INTEGER,
    username VARCHAR(50),
    content TEXT,
    created_at TIMESTAMP,
    rank REAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        m.id,
        m.user_id,
        m.room_id,
        m.username,
        m.content,
        m.created_at,
        similarity(m.content, search_term) as rank
    FROM messages m
    WHERE 
        m.is_deleted = FALSE
        AND (room_id_param IS NULL OR m.room_id = room_id_param)
        AND (m.content ILIKE '%' || search_term || '%' OR similarity(m.content, search_term) > 0.1)
    ORDER BY 
        similarity(m.content, search_term) DESC,
        m.created_at DESC
    LIMIT limit_param;
END;
$$ LANGUAGE plpgsql;