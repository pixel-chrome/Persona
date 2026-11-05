// Nœud Code « Générer code » — JavaScript, mode « Run Once for Each Item »
// Nécessite NODE_FUNCTION_ALLOW_BUILTIN=crypto (déjà dans docker-compose.yml)
const crypto = require('crypto');
const sha256 = (s) => crypto.createHash('sha256').update(s).digest('hex');
const code = String(crypto.randomInt(0, 1000000)).padStart(6, '0');   // 000000 à 999999
return { json: {
  email: $json.email,
  code,                                   // en clair : uniquement pour le mail
  code_hash: sha256(code),
  session_hash: sha256($json.sessionId),  // lie le code à cette conversation
} };
