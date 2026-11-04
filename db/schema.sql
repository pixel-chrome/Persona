-- Schéma de la base "persona" (partie utilisateurs / sécurité / envoi).

-- Schéma "n8n" : N8N y range ses propres tables, séparées des nôtres (schéma "public").
CREATE SCHEMA IF NOT EXISTS n8n;

-- pgcrypto : hash de mots de passe (bcrypt) et octets aléatoires, directement dans Postgres.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE users (
    id             INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    username       TEXT NOT NULL,
    email          TEXT NOT NULL,
    password_hash  TEXT NOT NULL,                  -- bcrypt : le sel est inclus dans le hash
    role           TEXT NOT NULL DEFAULT 'user' CHECK (role IN ('user', 'admin')),
    consent_at     TIMESTAMPTZ NOT NULL,           -- RGPD : preuve du consentement
    unsubscribed   BOOLEAN NOT NULL DEFAULT FALSE, -- RGPD : plus d'envoi
    failed_logins  INTEGER NOT NULL DEFAULT 0,
    locked_until   TIMESTAMPTZ,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- Unicité insensible à la casse : "Paul" et "paul" = même compte
CREATE UNIQUE INDEX users_username_uq ON users (lower(username));
CREATE UNIQUE INDEX users_email_uq    ON users (lower(email));

CREATE TABLE sessions (
    token_hash  TEXT PRIMARY KEY,                  -- SHA-256 du token (jamais le token brut)
    user_id     INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    expires_at  TIMESTAMPTZ NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX sessions_user_idx ON sessions (user_id);

CREATE TABLE preferences (
    user_id        INT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    topics         JSONB NOT NULL DEFAULT '[]'::jsonb,   
    send_time      TIME,                                 -- heure d'envoi souhaitée (HH:MM)
    timezone       TEXT NOT NULL DEFAULT 'UTC',          -- ex: 'Europe/Paris'
    language       TEXT NOT NULL DEFAULT 'fr',
    custom_prompt  TEXT                                  -- bonus : prompt personnalisé
);

CREATE TABLE sent_log (
    id          INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id     INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    sent_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    story_urls  JSONB NOT NULL DEFAULT '[]'::jsonb       -- évite de renvoyer les mêmes articles
);
CREATE INDEX sent_log_user_idx ON sent_log (user_id, sent_at DESC);

CREATE TABLE audit_log (
    id       INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id  INT REFERENCES users(id) ON DELETE SET NULL,  -- on garde la trace sans le lien perso
    action   TEXT NOT NULL,                                   -- ex: 'login_ok', 'login_fail', 'delete_account'
    at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
