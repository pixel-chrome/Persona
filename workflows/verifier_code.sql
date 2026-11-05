-- Nœud Postgres « Vérifier code » (Execute Query)
-- Query Parameters : {{ [$json.session_hash, $json.code_hash] }}
-- Une seule requête atomique : soit le code est bon (ligne supprimée = usage unique),
-- soit on compte un essai raté. Les deux conditions s'excluent, jamais les deux à la fois.
WITH ok AS (
  DELETE FROM login_codes
  WHERE session_hash = $1 AND code_hash = $2 AND expires_at > now() AND attempts < 5
  RETURNING email
), bad AS (
  UPDATE login_codes SET attempts = attempts + 1
  WHERE session_hash = $1
    AND NOT (code_hash = $2 AND expires_at > now() AND attempts < 5)
  RETURNING 1
)
SELECT (SELECT email FROM ok) AS email;   -- toujours 1 ligne ; email NULL si refus
