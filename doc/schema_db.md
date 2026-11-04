# Base de données Persona

## Vue d'ensemble

PostgreSQL 16 (conteneur `postgres`), **une base `persona`**, **un compte `persona_app`**, **deux schémas** :

| Schéma   | Contenu                                   | Géré par                        |
|----------|-------------------------------------------|---------------------------------|
| `public` | Tables de Persona (utilisateurs, envois…) | `db/schema.sql` (à la main)     |
| `n8n`    | Tables internes de N8N (workflows, exécutions, credentials) | N8N (automatique) |

Le schéma est appliqué **une seule fois**, au premier démarrage (volume `pgdata` vide), via `/docker-entrypoint-initdb.d/`.
Pour le rejouer : `docker compose down -v && docker compose up -d` (⚠️ efface les données).

### Pourquoi ces choix

- **Inconvénient assumé** : pas d'isolation de droits entre N8N et Persona (même compte). Acceptable pour un projet de cette taille ; en prod on séparerait les rôles (moindre privilège).

## Tables (schéma `public`)

```
users ──< sessions
  │──── preferences   (1-1)
  │──< sent_log
  └──< audit_log      (SET NULL)
```

### `users`
Comptes. `role` ∈ {`user`, `admin`}.
- `password_hash` : **bcrypt** via `pgcrypto` (le sel est inclus dans le hash, jamais de mot de passe en clair).
- `consent_at` (NOT NULL) + `unsubscribed` : **RGPD**, preuve du consentement et désinscription.
- `failed_logins` + `locked_until` : blocage temporaire anti brute-force.
- Index unique sur `lower(username)` et `lower(email)` : `Paul` et `paul` = même compte.

### `sessions`
Connexion au chatbot. Clé primaire = `token_hash` (**SHA-256 du token**) : si la base fuite, les tokens ne sont pas utilisables. `expires_at` pour l'expiration.

### `preferences`
Une ligne par utilisateur (clé primaire = `user_id`, relation 1-1).
- `topics` en **JSONB** : liste de sujets de taille variable, pas besoin d'une table de jointure.
- `send_time` + `timezone` : heure d'envoi dans le fuseau de l'utilisateur.
- `language`, `custom_prompt` (bonus).

### `sent_log`
Historique des envois. `story_urls` (JSONB) = articles déjà envoyés, pour ne pas les répéter. Index `(user_id, sent_at DESC)` pour retrouver vite les derniers envois.

### `audit_log`
Journal d'actions (`login_ok`, `login_fail`, `delete_account`…). `user_id` en **`ON DELETE SET NULL`** : à la suppression d'un compte, on garde la trace de l'action sans le lien vers la personne.

## RGPD : suppression de compte

Toutes les tables liées à `users` ont `ON DELETE CASCADE` (sauf `audit_log`, voir plus haut) :
`DELETE FROM users WHERE id = …` efface en une requête sessions, préférences et historique d'envois.

## Points à valider au lancement

- N8N doit bien ranger ses tables dans le schéma `n8n` (`DB_POSTGRESDB_SCHEMA`). Vérif : `\dt n8n.*` dans `psql` après le premier démarrage.
