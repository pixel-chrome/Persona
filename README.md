# Persona

Agrégateur de news personnalisé, sans interface : tout passe par un chatbot (Chat Trigger N8N).
L'utilisateur donne son email, ses sujets et son créneau horaire, puis reçoit une newsletter par email à l'heure choisie.

Stack : N8N + PostgreSQL (Docker), un LLM (Google Gemini), un SMTP (Gmail), les flux RSS BBC et Le Monde et l'API AskNews.

Fonctionnement : le chatbot (`01chat`) enregistre l'utilisateur et ses préférences en base. Toutes les 4 minutes, `02newsletter` cherche les utilisateurs dont l'heure d'envoi vient d'arriver, appelle `03fetch` (récupération des news), demande au LLM de choisir et résumer les articles de chacun, puis envoie l'email. Un lien dans chaque email permet de se désinscrire (`04unsubscribe`).

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
| `02newsletter.json` | Envoi planifié de la newsletter (Schedule Trigger toutes les 4 min) |
| `03fetch.json` | Sous-workflow appelé par `02newsletter` : récupération des news (2 flux RSS + AskNews) |
| `04unsubscribe.json` | Webhook de désinscription (lien présent dans chaque email) |

Aucun community node n'est requis : tous les nœuds sont natifs de N8N.

Ordre à respecter :

1. Créer les credentials (section 3), avant l'import.
2. Importer `03fetch.json` **avant** `02newsletter.json`.
3. Dans `02newsletter`, ouvrir le nœud `Execute_03fetch` et **re-sélectionner le sous-workflow `03fetch`** dans la liste : l'identifiant d'origine n'existe pas sur une autre instance.
4. Dans chaque workflow, vérifier que les nœuds Postgres, SMTP, Gemini et HTTP ont bien leur credential rattaché (les exports de `01chat` n'en contiennent aucun).
5. **Publier** chaque workflow (bouton **Publish**, ou interrupteur « Active » selon la version) : sans cela, ni le Schedule Trigger, ni le webhook de désinscription ne fonctionnent. Un workflow importé est inactif par défaut.

## 3. Credentials

À créer dans N8N (**Credentials → Create**), avec **exactement** ces noms pour que les workflows les retrouvent. Aucun credential n'est dans le dépôt.

| Nom | Type | À renseigner |
|---|---|---|
| `POSTGRES_PERSONA` | Postgres | Host `postgres`, port `5432`, database `persona`, user/password = valeurs du `.env` |
| `SMTP_PERSONA` | SMTP | Gmail : host `smtp.gmail.com`, port `465`, SSL activé, user = adresse Gmail, password = mot de passe d'application. Gmail remplace l'expéditeur affiché par l'adresse du compte SMTP |
| `LLM_PERSONA` | Google Gemini(PaLM) Api | Clé API Google AI Studio, host `https://generativelanguage.googleapis.com`. Modèle : `gemini-3.5-flash-lite` (offre gratuite : 15 requêtes/min, 500/jour). Le modèle `gemini-3.5-flash` est souvent saturé (erreur 503) : ne pas l'utiliser |
| `AskNews_API_Persona` | Header Auth | Name : `Authorization`. Value : `Bearer <clé API AskNews>`. Le mot `Bearer` suivi d'une espace est **obligatoire** (sans lui, AskNews répond 401) |

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
2. Vérifier que `02newsletter` et `03fetch` sont **publiés**. Le Schedule Trigger s'exécute toutes les 4 minutes et sert les utilisateurs dont l'heure d'envoi date de **moins de 5 minutes** (dans leur fuseau).
3. Attendre le passage suivant : l'email arrive, et une ligne apparaît dans `sent_log` :

   ```bash
   docker compose exec postgres psql -U <POSTGRES_USER> -d persona -c 'SELECT * FROM sent_log ORDER BY sent_at DESC LIMIT 5;'
   ```

Règles utiles pour les tests :

- Un utilisateur n'est servi **qu'une fois par jour** : dès qu'une ligne existe dans `sent_log` pour aujourd'hui, il est ignoré. Pour rejouer, supprimer cette ligne (`DELETE FROM sent_log WHERE user_id = <id> AND sent_at::date = current_date;`).
- Le bouton **Execute workflow** (Manual Trigger de `02newsletter`) lance le workflow tout de suite, mais la requête garde le filtre horaire : il faut quand même que l'heure d'envoi de l'utilisateur soit dans la fenêtre de 5 minutes. Pour la placer 1 minute dans le passé :

  ```bash
  docker compose exec postgres psql -U <POSTGRES_USER> -d persona -c "UPDATE preferences SET send_time = (now() AT TIME ZONE timezone)::time - interval '1 minute' WHERE user_id = <id>;"
  ```

- Si le workflow s'arrête sur le nœud `Users_a_servir` sans sortie, aucun utilisateur n'est dû à cet instant (heure hors fenêtre, déjà servi, désinscrit ou sans consentement). Ce n'est pas une erreur.
- Si aucun article ne correspond aux sujets de l'utilisateur, il reçoit quand même un email indiquant qu'il n'y a pas de nouvel article aujourd'hui.
- Désinscription : cliquer sur le lien en bas de l'email, puis vérifier `SELECT id, unsubscribed FROM users;`. Un utilisateur désinscrit n'est plus servi. `/reprendre` dans le chat réactive l'envoi.

## 6. Sécurité

- Le chat est le seul point d'entrée. Hors `/connexion` et `/code`, chaque message passe par une session vérifiée.
- Codes et tokens de session sont stockés hachés (SHA-256).
- Requêtes SQL paramétrées.
- L'identité vient de la session, jamais du texte du chat.
- Le LLM ne fait qu'extraire un JSON (sujets, heure, fuseau). Il n'a accès ni à la base ni aux données des utilisateurs, et sa sortie est revérifiée par un nœud Code avant d'être enregistrée. Les commandes ne lui sont jamais envoyées.
- Limites : 500 caractères par message, 5 messages par minute vers le LLM, un code par minute, 5 essais par code.
- Les erreurs techniques (quota du LLM, etc.) ne sont pas montrées à l'utilisateur.
- Newsletter : le LLM ne reçoit que des titres et extraits d'articles, présentés comme des données (il lui est interdit d'obéir à une instruction qu'ils contiendraient). Il ne renvoie que des numéros d'articles et des résumés : les liens de l'email viennent de nos données, jamais du LLM, et seuls les liens `http(s)` sont acceptés. Le contenu inséré dans l'email HTML est échappé.
- Désinscription : chaque utilisateur a un `unsub_token` aléatoire de 48 caractères (non devinable). Le lien ne contient pas l'identifiant ni l'email, donc personne ne peut désinscrire un autre utilisateur. Un token inconnu reçoit exactement la même réponse qu'un token valide.
- Aucun secret n'est dans les exports JSON ni dans le dépôt : clés et mots de passe sont dans les credentials N8N.

Tests d'attaque et limites connues : [doc/tests_securite.md](doc/tests_securite.md).

## 7. RGPD

- Données stockées : email, sujets, heure et fuseau d'envoi, historique des envois, journal d'audit.
- Finalité : envoyer la newsletter demandée. Rien n'est partagé.
- Consentement : explicite avec `/accepte`, horodaté dans `consent_at`. Aucune préférence n'est enregistrée avant.
- Accès : `/mesdonnees`.
- Désinscription : lien « cliquez ici » en bas de chaque email (workflow `04unsubscribe`), ou `/stop` dans le chat (`/reprendre` pour revenir). Dans les deux cas, plus aucun email n'est envoyé.
- Effacement : `/supprimer confirmer` supprime le compte, les sessions, les préférences, l'historique et les codes en attente. Le journal d'audit garde l'action, sans lien vers la personne.

Durées de conservation :

| Donnée | Durée |
|---|---|
| Code de connexion (et l'email associé, avant consentement) | 10 min |
| Session | 24 h |
| Compteur de messages | 2 min |
| Logs d'exécution N8N (erreurs, tests lancés depuis l'éditeur, exécutions de `02newsletter` et `03fetch`) | 24 h |
| Historique des envois (`sent_log`) | Jusqu'à `/supprimer confirmer` (sert à ne pas renvoyer les mêmes articles pendant 2 jours) |
| Compte et préférences | Jusqu'à `/supprimer confirmer` |
## 8. Limites connues

- **Sources de news** : 2 flux RSS (BBC, Le Monde, identiques pour tous) et AskNews avec 3 thèmes généraux fixes (`health`, `technology`, `movies`), sur les dernières 24 h. Les sujets libres tapés dans le chat ne sont pas envoyés aux sources : le LLM sélectionne dans ce lot les articles qui correspondent aux sujets de l'utilisateur. Un sujet absent de ces sources donne un email « aucun nouvel article ».
- **LLM indisponible** : si Gemini échoue (quota, erreur 503), l'envoi continue avec une sélection vide : l'utilisateur reçoit l'email « aucun nouvel article » et n'est pas resservi ce jour-là.
- **Lien de désinscription** : il pointe vers `http://localhost:5678/webhook/unsubscribe`, donc il ne fonctionne que depuis la machine qui héberge N8N. Sur un serveur, définir `WEBHOOK_URL` dans `docker-compose.yml` et adapter l'adresse dans le nœud `Construire_email` de `02newsletter`.
- **Quotas** : AskNews (3 appels par exécution qui a au moins un utilisateur à servir) et Gemini (15 requêtes/min, 500/jour en offre gratuite, soit 1 appel par utilisateur servi).
- **Historique** : un utilisateur sans article reçoit quand même une ligne dans `sent_log`, ce qui le sert au plus une fois par jour.
