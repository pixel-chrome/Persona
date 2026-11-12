# Persona

Agrégateur de news personnalisé, sans interface : tout passe par un chatbot (Chat Trigger N8N).
L'utilisateur donne son email, ses sujets et son créneau horaire, puis reçoit une newsletter par email à l'heure choisie.

Stack : N8N + PostgreSQL (Docker), un LLM, un SMTP.

> Les éléments marqués **[À COMPLÉTER]** dépendent de choix pas encore figés dans le projet.

## 1. Installation

Prérequis : Docker et Docker Compose.

```bash
git clone <url-du-repo>
cd B-AIA-300-MPL-3-1-persona-4
cp .env.example .env
```

Dans `.env`, remplacer **toutes** les valeurs `change_me` (générer un secret : `openssl rand -hex 24`) :

| Variable | Rôle |
|---|---|
| `POSTGRES_USER` | Compte PostgreSQL (utilisé par N8N et les workflows) |
| `POSTGRES_PASSWORD` | Mot de passe de ce compte |
| `N8N_ENCRYPTION_KEY` | Chiffre les credentials dans N8N. À conserver : la perdre rend les credentials illisibles |

Démarrer :

```bash
docker compose up -d
```

- N8N : http://localhost:5678 (créer le compte propriétaire au premier accès).
- PostgreSQL : `127.0.0.1:5432`, base `persona`. Le fichier `db/schema.sql` est appliqué automatiquement au premier démarrage.
- Pour réinitialiser la base (**efface les données**) : `docker compose down -v && docker compose up -d`.

Vérifier : `docker compose exec postgres psql -U <POSTGRES_USER> -d persona -c '\dt public.*'`
(tables attendues : `users`, `login_codes`, `sessions`, `preferences`, `sent_log`, `audit_log`).

Détail du schéma : [doc/schema_db.md](doc/schema_db.md).

## 2. Import des workflows

Dans N8N : **Workflows → Import from file**, puis importer chaque fichier du dossier `workflows/` :

| Fichier | Rôle |
|---|---|
| `01chat.json` | Chat Trigger, authentification par code email, préférences, RGPD |
| `02newsletter.json` | Envoi planifié de la newsletter **[À COMPLÉTER]** |
| `03fetch.json` | Récupération des news (sous-workflow) **[À COMPLÉTER]** |

Aucun community node n'est requis **[À COMPLÉTER : à confirmer]**.
Après l'import, ouvrir chaque workflow, rattacher les credentials (section 3), puis **activer** les workflows (interrupteur « Active »).

## 3. Credentials

À créer dans N8N (**Credentials → Create**), avec **exactement** ces noms pour que les workflows les retrouvent. Aucun credential n'est dans le dépôt.

| Nom | Type | À renseigner |
|---|---|---|
| `POSTGRES_PERSONA` | Postgres | Host `postgres`, port `5432`, database `persona`, user/password = valeurs du `.env` |
| `SMTP_PERSONA` | SMTP | Serveur, port, utilisateur et mot de passe de votre fournisseur d'envoi (ex. Gmail avec mot de passe d'application) |
| `LLM_PERSONA` | Selon le modèle choisi | Clé API de GEMINI|
| Clé API news | **[À COMPLÉTER]** | Si une API de news est utilisée (les flux RSS n'en demandent pas) |

## 4. Utiliser Persona via le chatbot

Ouvrir le chat : dans N8N, ouvrir `01chat.json` puis **Open chat**.

Connexion (sans mot de passe, par code email) :

1. `/connexion ton@email.com` : un code à 6 chiffres est envoyé par email (valable 10 min, 1 envoi par minute max).
2. `/code 123456` : valide le code. Le compte est créé à la première validation, ce qui vaut consentement (RGPD).
   Après 5 essais ratés, le code est invalidé.

Ensuite, en langage libre **[À COMPLÉTER : à confirmer avec le workflow final]** :

- Donner ses sujets : « je veux des news sur le volley et l'IA »
- Choisir le créneau : « envoie-la chaque matin vers 8h »
- Demander une newsletter
- Se désinscrire : « stop »
- Voir ses données / supprimer ses données

## 5. Tester rapidement un envoi planifié

1. Se connecter et définir ses préférences via le chat, avec un créneau à **2-3 minutes** de l'heure actuelle (ex. il est 14:10 → « envoie-moi la newsletter à 14:13 »).
2. Vérifier que `02newsletter.json` est **actif** (le Schedule Trigger s'exécute toutes les 5 minutes **[À COMPLÉTER]**).
3. Attendre le passage suivant du Schedule Trigger : l'email arrive, et une ligne apparaît dans `sent_log` :

   ```bash
   docker compose exec postgres psql -U <POSTGRES_USER> -d persona -c 'SELECT * FROM sent_log ORDER BY sent_at DESC LIMIT 5;'
   ```

Pour forcer un envoi immédiat sans attendre : **[À COMPLÉTER : mode test du workflow]**.

## 6. Sécurité

- Le chat est le seul point d'entrée.
- Codes et tokens de session sont stockés **hachés** (SHA-256), jamais en clair.
- Requêtes SQL paramétrées (pas de concaténation de texte utilisateur).
- Chaque action utilise l'identité issue de la session, jamais un identifiant donné dans le texte du chat.
- Limites : message de 500 caractères max, codes expirants, anti-spam et anti-brute-force sur la connexion.
- Les commandes `/connexion` et `/code` ne sont jamais transmises au LLM.
- Tests d'attaque et résultats : **[À COMPLÉTER]**.

## 7. RGPD

- **Données stockées** : email, sujets, créneau, fuseau, historique des envois, journal d'audit. Rien d'autre.
- **Finalité** : envoyer la newsletter demandée.
- **Consentement** : horodaté (`consent_at`) à la validation du code email.
- **Désinscription** : « stop » dans le chat et lien dans chaque email **[À COMPLÉTER]**.
- **Effacement** : « supprime mes données » supprime le compte et ses données liées (sessions, préférences, historique). Le journal d'audit est conservé sans lien vers la personne.
- **Accès** : « montre-moi ce que tu stockes sur moi ».
- **Durée de conservation** : **[À COMPLÉTER]**.