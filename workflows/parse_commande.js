// Nœud Code « Parse commande » — mode « Run Once for Each Item », langage JavaScript
const text = String($json.chatInput ?? '').trim();
const sessionId = $json.sessionId;
const FORMAT = 'Commandes : /connexion ton@email.com puis /code 123456';

if (text.length > 500) {
  return { json: { kind: 'error', reply: 'Message trop long (500 caractères max).', sessionId } };
}

let m = text.match(/^\/connexion\s+([^\s@]+@[^\s@]+\.[^\s@]+)$/i);
if (m && m[1].length <= 254) {
  return { json: { kind: 'login', email: m[1].toLowerCase(), sessionId } };
}

m = text.match(/^\/code\s+(\d{6})$/);
if (m) {
  return { json: { kind: 'code', code: m[1], sessionId } };
}

// Garde-fou : une commande mal formée ou cachée dans une phrase ne part JAMAIS au LLM
if (/\/connexion|\/code/i.test(text)) {
  return { json: { kind: 'error', reply: 'Format invalide. ' + FORMAT, sessionId } };
}

return { json: { kind: 'chat', chatInput: text, sessionId } };
