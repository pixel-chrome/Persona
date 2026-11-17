-- Schéma de la base "persona" (partie utilisateurs / sécurité / envoi).

-- Schéma "n8n" : N8N y range ses propres tables, séparées des nôtres (schéma "public").
CREATE SCHEMA IF NOT EXISTS n8n;

-- pgcrypto : hash SHA-256 (codes, tokens) et octets aléatoires, directement dans Postgres.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE users (
    id             INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email          TEXT NOT NULL,
    role           TEXT NOT NULL DEFAULT 'user' CHECK (role IN ('user', 'admin')),
    consent_at     TIMESTAMPTZ,                    -- RGPD : NULL tant que l'user n'a pas tapé /accepte
    unsubscribed   BOOLEAN NOT NULL DEFAULT FALSE, -- RGPD : plus d'envoi
    unsub_token    TEXT NOT NULL DEFAULT encode(gen_random_bytes(24), 'hex'), -- lien de désinscription dans la newsletter (aléatoire, non devinable)
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- Unicité insensible à la casse : "Paul@x.fr" et "paul@x.fr" = même compte
CREATE UNIQUE INDEX users_email_uq    ON users (lower(email));
CREATE UNIQUE INDEX users_unsub_token_uq ON users (unsub_token);

-- Codes de connexion à usage unique envoyés par email (un seul code actif par adresse).
CREATE TABLE login_codes (
    email       TEXT PRIMARY KEY,                  -- en minuscules
    code_hash   TEXT NOT NULL,                     -- SHA-256 du code (jamais le code brut)
    session_hash TEXT NOT NULL,                    -- SHA-256 du sessionId du chat qui a demandé le code
    expires_at  TIMESTAMPTZ NOT NULL,              -- ex: now() + 10 min
    attempts    INTEGER NOT NULL DEFAULT 0,        -- essais ratés ; bloqué à 5
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now() -- sert à limiter l'envoi de codes (anti-spam)
);

CREATE INDEX login_codes_session_idx ON login_codes (session_hash);

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
