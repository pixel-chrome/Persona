// Nœud Code « Hasher saisie » 
const crypto = require('crypto');
const sha256 = (s) => crypto.createHash('sha256').update(s).digest('hex');
return { json: { code_hash: sha256($json.code), session_hash: sha256($json.sessionId) } };
