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
| `SMTP_FROM` | Adresse expéditrice des emails (celle du compte SMTP) |

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
| `SMTP_PERSONA` | SMTP | Gmail : host `smtp.gmail.com`, port `465`, SSL activé, user = adresse Gmail, password = mot de passe d'application |
| `LLM_PERSONA` | Google Gemini(PaLM) Api | Clé API Google AI Studio, host par défaut. Modèle : `gemini-3.5-flash-lite` (offre gratuite : 15 requêtes/min, 500/jour) |
| Clé API news | **[À COMPLÉTER]** | Si une API de news est utilisée (les flux RSS n'en demandent pas) |

## 4. Utiliser Persona via le chatbot

Ouvrir `01chat.json` dans N8N puis **Open chat**.

Première utilisation : `/connexion`, puis `/code`, puis `/accepte`. Ensuite, les préférences se donnent en langage libre.

| Commande | À mettre après | Session | Consentement | Effet |
|---|---|---|---|---|
| `/connexion` | une adresse email | non | non | Envoie un code à 6 chiffres, valable 10 min (un envoi par minute) |
| `/code` | les 6 chiffres reçus | non | non | Ouvre une session de 24 h. Code invalidé après 5 essais ratés |
| `/accepte` | rien | oui | non | Donne son consentement (le bot affiche avant quelles données sont stockées) |
| `/mesdonnees` | rien | oui | non | Affiche toutes les données stockées sur soi |
| `/stop` | rien | oui | oui | Arrête l'envoi de la newsletter (`stop` seul marche aussi) |
| `/reprendre` | rien | oui | oui | Relance l'envoi |
| `/supprimer` | rien | oui | non | Affiche un avertissement, ne supprime rien |
| `/supprimer confirmer` | rien | oui | non | Supprime le compte et toutes ses données |
| `/logout` | rien | oui | non | Ferme la session |
| texte libre | des sujets, une heure, une ville | oui | oui | Enregistre les préférences, max 5 messages par minute |

Exemples : `/connexion moi@exemple.fr`, `/code 482913`.

Exemples de texte libre :

- « je veux des news cyber et volley »
- « à 8h, heure de Paris »
- « qu'est-ce que tu as sur moi ? »

Le bot redemande ce qui manque. Sans ville, le fuseau est UTC. Une nouvelle liste de sujets remplace l'ancienne. Une commande mal écrite ou inconnue est refusée avec un message d'aide, elle n'est jamais envoyée au LLM.

## 5. Tester rapidement un envoi planifié

1. Se connecter et définir ses préférences via le chat, avec un créneau à **2-3 minutes** de l'heure actuelle (ex. il est 14:10 → « envoie-moi la newsletter à 14:13 »).
2. Vérifier que `02newsletter.json` est **actif** (le Schedule Trigger s'exécute toutes les 5 minutes **[À COMPLÉTER]**).
3. Attendre le passage suivant du Schedule Trigger : l'email arrive, et une ligne apparaît dans `sent_log` :

   ```bash
   docker compose exec postgres psql -U <POSTGRES_USER> -d persona -c 'SELECT * FROM sent_log ORDER BY sent_at DESC LIMIT 5;'
   ```

Pour forcer un envoi immédiat sans attendre : **[À COMPLÉTER : mode test du workflow]**.

## 6. Sécurité

- Le chat est le seul point d'entrée. Hors `/connexion` et `/code`, chaque message passe par une session vérifiée.
- Codes et tokens de session sont stockés hachés (SHA-256).
- Requêtes SQL paramétrées.
- L'identité vient de la session, jamais du texte du chat.
- Le LLM ne fait qu'extraire un JSON (sujets, heure, fuseau). Il n'a accès ni à la base ni aux données des utilisateurs, et sa sortie est revérifiée par un nœud Code avant d'être enregistrée. Les commandes ne lui sont jamais envoyées.
- Limites : 500 caractères par message, 5 messages par minute vers le LLM, un code par minute, 5 essais par code.
- Les erreurs techniques (quota du LLM, etc.) ne sont pas montrées à l'utilisateur.

Tests d'attaque et limites connues : [doc/tests_securite.md](doc/tests_securite.md).

## 7. RGPD

- Données stockées : email, sujets, heure et fuseau d'envoi, historique des envois, journal d'audit.
- Finalité : envoyer la newsletter demandée. Rien n'est partagé.
- Consentement : explicite avec `/accepte`, horodaté dans `consent_at`. Aucune préférence n'est enregistrée avant.
- Accès : `/mesdonnees`.
- Désinscription : `/stop` dans le chat (`/reprendre` pour revenir). Lien dans chaque email **[À COMPLÉTER]**.
- Effacement : `/supprimer confirmer` supprime le compte, les sessions, les préférences, l'historique et les codes en attente. Le journal d'audit garde l'action, sans lien vers la personne.

Durées de conservation :

| Donnée | Durée |
|---|---|
| Code de connexion (et l'email associé, avant consentement) | 10 min |
| Session | 24 h |
| Compteur de messages | 2 min |
| Logs d'exécution N8N (erreurs et tests lancés depuis l'éditeur) | 24 h |
| Compte et préférences | Jusqu'à `/supprimer confirmer` |