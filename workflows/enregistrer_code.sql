-- Nœud Postgres « Enregistrer code » (Execute Query)
-- Query Parameters : {{ [$json.email, $json.code_hash, $json.session_hash] }}
-- Anti-spam : le WHERE refuse de remplacer un code créé il y a moins d'1 minute (0 ligne renvoyée).
INSERT INTO login_codes (email, code_hash, session_hash, expires_at, attempts, created_at)
VALUES ($1, $2, $3, now() + interval '10 minutes', 0, now())
ON CONFLICT (email) DO UPDATE
  SET code_hash    = EXCLUDED.code_hash,
      session_hash = EXCLUDED.session_hash,
      expires_at   = EXCLUDED.expires_at,
      attempts     = 0,
      created_at   = now()
  WHERE login_codes.created_at < now() - interval '1 minute'
RETURNING email;
