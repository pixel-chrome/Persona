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
login_codes   (indépendante : codes email en attente)
users ──< sessions
  │──── preferences   (1-1)
  │──< sent_log
  └──< audit_log      (SET NULL)
```

### `users`
Comptes, identifiés par **email** (pas de mot de passe). `role` ∈ {`user`, `admin`}.
- Création à la **première validation d'un code email** : l'adresse est prouvée, `consent_at` est posé à ce moment (RGPD) et `unsubscribed` permet de se désinscrire.
- Index unique sur `lower(email)` : `Paul@x.fr` et `paul@x.fr` = même compte.
- `unsub_token` : secret aléatoire de 48 caractères hexadécimaux (`gen_random_bytes(24)`), unique, généré à la création du compte. Il sert uniquement au lien de désinscription présent dans les emails (workflow `04unsubscribe`) : il identifie l'utilisateur sans révéler son id ni son email. Ne jamais le copier dans un log, un ticket ou un chat.

### `login_codes`
Code à 6 chiffres envoyé par email. On stocke son **SHA-256** (`code_hash`), jamais le code brut. `session_hash` lie le code à la conversation du chat qui l'a demandé (sinon `/code 123456` ne dirait pas à quel email il se rapporte). Une seule ligne par adresse (clé primaire = `email`) : redemander un code remplace l'ancien. `expires_at` (10 min), `attempts` (blocage à 5 essais ratés) et `created_at` (pas plus d'un envoi par minute) protègent contre le brute-force et le spam d'emails. Ligne supprimée après validation.

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
