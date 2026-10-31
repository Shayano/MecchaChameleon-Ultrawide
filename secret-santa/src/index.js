// Secret Santa sur Cloudflare Workers (stockage KV).
//
// Clés KV :
//   g:<gid>        groupe (JSON), écrit uniquement par l'organisateur
//   w:<gid>:<pid>  liste d'idées cadeaux d'un participant
//   s:<gid>:<pid>  présent si le participant a découvert son tirage

const TTL = 60 * 60 * 24 * 400; // les groupes expirent après ~13 mois
const MAX_PEOPLE = 100;
const MAX_NAME = 40;
const MAX_WISH = 2000;

export default {
  async fetch(request, env) {
    const nonce = token(12);
    try {
      return await route(request, env, nonce);
    } catch (err) {
      if (err instanceof UserError) {
        return page(nonce, 'Oups', `<div class="card"><p class="error">${esc(err.message)}</p><p><a href="/" data-back>Revenir en arrière</a></p></div>`, 400);
      }
      console.error(err);
      return page(nonce, 'Oups', `<div class="card"><p class="error">Une erreur est survenue. Réessaie dans un instant.</p></div>`, 500);
    }
  },
};

class UserError extends Error {}

async function route(request, env, nonce) {
  const url = new URL(request.url);
  const parts = url.pathname.split('/').filter(Boolean);
  const method = request.method;

  // Pas besoin de jeton CSRF : chaque action POST passe par une URL contenant un jeton secret.
  if (parts.length === 0 && method === 'GET') return homePage(nonce);
  if (parts[0] === 'create' && parts.length === 1 && method === 'POST') return createGroup(request, env, url);

  // Organisateur : /a/<gid>/<adminToken>[/action]
  if (parts[0] === 'a' && (parts.length === 3 || parts.length === 4)) {
    const group = await loadGroup(env, parts[1]);
    if (!group || !safeEqual(group.adminToken, parts[2])) return notFound(nonce);
    const base = `/a/${group.id}/${group.adminToken}`;
    if (parts.length === 3 && method === 'GET') return adminPage(env, url, group, nonce);
    if (method === 'POST') {
      switch (parts[3]) {
        case 'info':
          applyInfo(group, await readForm(request));
          await saveGroup(env, group);
          return redirect(`${base}?ok=info`);
        case 'participants': {
          applyPeople(group, await readForm(request));
          drawGroup(group);
          await saveGroup(env, group);
          await clearKeys(env, `s:${group.id}:`);
          await removeOrphanWishes(env, group);
          return redirect(`${base}?ok=draw`);
        }
        case 'redraw':
          drawGroup(group);
          await saveGroup(env, group);
          await clearKeys(env, `s:${group.id}:`);
          return redirect(`${base}?ok=draw`);
        case 'delete':
          await env.SANTA.delete(`g:${group.id}`);
          await clearKeys(env, `w:${group.id}:`);
          await clearKeys(env, `s:${group.id}:`);
          return page(nonce, 'Groupe supprimé', `<div class="card"><h1>Groupe supprimé</h1><p>Toutes les données ont été effacées.</p><p><a class="btn" href="/">Créer un nouveau groupe</a></p></div>`);
      }
    }
  }

  // Participant : /p/<gid>/<token>[/action]
  if (parts[0] === 'p' && (parts.length === 3 || parts.length === 4)) {
    const group = await loadGroup(env, parts[1]);
    const person = group && group.people.find((p) => safeEqual(p.token, parts[2]));
    if (!person) return notFound(nonce);
    const base = `/p/${group.id}/${person.token}`;
    if (parts.length === 3 && method === 'GET') return participantPage(env, url, group, person, nonce);
    if (method === 'POST' && parts[3] === 'reveal') {
      await env.SANTA.put(`s:${group.id}:${person.id}`, String(Date.now()), { expirationTtl: TTL });
      return redirect(base);
    }
    if (method === 'POST' && parts[3] === 'wishlist') {
      const form = await readForm(request);
      const wish = String(form.get('wishlist') || '').trim().slice(0, MAX_WISH);
      if (wish) await env.SANTA.put(`w:${group.id}:${person.id}`, wish, { expirationTtl: TTL });
      else await env.SANTA.delete(`w:${group.id}:${person.id}`);
      return redirect(`${base}?ok=wish`);
    }
  }

  return notFound(nonce);
}

// ---------- Données ----------

async function loadGroup(env, gid) {
  if (!/^[A-Za-z0-9_-]{6,40}$/.test(gid || '')) return null;
  return env.SANTA.get(`g:${gid}`, 'json');
}

async function saveGroup(env, group) {
  await env.SANTA.put(`g:${group.id}`, JSON.stringify(group), { expirationTtl: TTL });
}

async function listKeys(env, prefix) {
  const keys = [];
  let cursor;
  do {
    const res = await env.SANTA.list({ prefix, cursor });
    keys.push(...res.keys.map((k) => k.name));
    cursor = res.list_complete ? undefined : res.cursor;
  } while (cursor);
  return keys;
}

async function clearKeys(env, prefix) {
  const keys = await listKeys(env, prefix);
  await Promise.all(keys.map((k) => env.SANTA.delete(k)));
}

async function removeOrphanWishes(env, group) {
  const ids = new Set(group.people.map((p) => p.id));
  const keys = await listKeys(env, `w:${group.id}:`);
  await Promise.all(keys.filter((k) => !ids.has(k.split(':')[2])).map((k) => env.SANTA.delete(k)));
}

async function createGroup(request, env, url) {
  const form = await readForm(request);
  const group = { id: token(9), adminToken: token(18), createdAt: Date.now(), people: [], exclusions: [], assignments: {} };
  applyInfo(group, form);
  applyPeople(group, form);
  drawGroup(group);
  await saveGroup(env, group);
  return redirect(`/a/${group.id}/${group.adminToken}?ok=new`);
}

function applyInfo(group, form) {
  group.name = String(form.get('name') || '').trim().slice(0, 80) || 'Secret Santa';
  group.budget = String(form.get('budget') || '').trim().slice(0, 30);
  const date = String(form.get('date') || '').trim();
  group.date = /^\d{4}-\d{2}-\d{2}$/.test(date) ? date : '';
  group.message = String(form.get('message') || '').trim().slice(0, 500);
}

function splitNames(line) {
  return line.split(/[,;+&/]| et /i).map((s) => s.trim()).filter(Boolean);
}

function applyPeople(group, form) {
  const names = String(form.get('people') || '').split(/\r?\n/).map((s) => s.trim()).filter(Boolean);
  if (names.length < 3) throw new UserError('Il faut au moins 3 participants.');
  if (names.length > MAX_PEOPLE) throw new UserError(`Maximum ${MAX_PEOPLE} participants.`);
  const seen = new Set();
  for (const n of names) {
    if (n.length > MAX_NAME) throw new UserError(`Le prénom « ${n.slice(0, 50)}… » est trop long (${MAX_NAME} caractères max).`);
    const k = n.toLowerCase();
    if (seen.has(k)) throw new UserError(`« ${n} » apparaît deux fois. Ajoute une initiale pour les différencier (ex. « Marie D. »).`);
    seen.add(k);
  }

  // On garde l'identifiant, le lien et la liste d'idées des personnes déjà présentes.
  const previous = new Map(group.people.map((p) => [p.name.toLowerCase(), p]));
  group.people = names.map((name) => {
    const old = previous.get(name.toLowerCase());
    return old ? { ...old, name } : { id: token(6), name, token: token(16) };
  });

  const byName = new Map(group.people.map((p) => [p.name.toLowerCase(), p.id]));
  const exclusions = [];
  const unknown = [];
  for (const line of String(form.get('exclusions') || '').split(/\r?\n/)) {
    const ids = [];
    for (const n of splitNames(line)) {
      const id = byName.get(n.toLowerCase());
      if (id) ids.push(id);
      else unknown.push(n);
    }
    if (ids.length >= 2) exclusions.push(ids);
  }
  if (unknown.length) throw new UserError(`Dans les exclusions, ces prénoms ne sont pas dans la liste des participants : ${unknown.join(', ')}.`);
  group.exclusions = exclusions;
}

// ---------- Tirage au sort ----------

function drawGroup(group) {
  const ids = group.people.map((p) => p.id);
  const forbidden = new Set();
  for (const ex of group.exclusions) for (const a of ex) for (const b of ex) forbidden.add(`${a}|${b}`);
  const allowed = (g, r) => g !== r && !forbidden.has(`${g}|${r}`);
  const result = sampleUniform(ids, allowed) || sampleMatching(ids, allowed);
  if (!result) throw new UserError('Tirage impossible avec ces exclusions : trop de personnes ne peuvent pas se tirer entre elles. Retire quelques exclusions.');
  group.assignments = result;
  group.drawnAt = Date.now();
}

// Tirage uniforme parmi toutes les combinaisons valides (permutations aléatoires + rejet).
function sampleUniform(ids, allowed) {
  for (let attempt = 0; attempt < 3000; attempt++) {
    const perm = shuffle(ids);
    if (ids.every((g, i) => allowed(g, perm[i]))) {
      return Object.fromEntries(ids.map((g, i) => [g, perm[i]]));
    }
  }
  return null;
}

// Repli pour les cas très contraints : couplage biparti (algorithme de Kuhn) dans un ordre aléatoire.
function sampleMatching(ids, allowed) {
  const adj = new Map(ids.map((g) => [g, shuffle(ids.filter((r) => allowed(g, r)))]));
  const giverOf = new Map();
  const augment = (g, visited) => {
    for (const r of adj.get(g)) {
      if (visited.has(r)) continue;
      visited.add(r);
      if (!giverOf.has(r) || augment(giverOf.get(r), visited)) {
        giverOf.set(r, g);
        return true;
      }
    }
    return false;
  };
  for (const g of shuffle(ids)) if (!augment(g, new Set())) return null;
  const out = {};
  for (const [r, g] of giverOf) out[g] = r;
  return out;
}

function randomInt(n) {
  const limit = Math.floor(0x100000000 / n) * n;
  const buf = new Uint32Array(1);
  do crypto.getRandomValues(buf);
  while (buf[0] >= limit);
  return buf[0] % n;
}

function shuffle(arr) {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = randomInt(i + 1);
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

// ---------- Pages ----------

function homePage(nonce) {
  return page(nonce, 'Secret Santa', `
<header class="hero">
  <div class="big">🎅</div>
  <h1>Secret Santa</h1>
  <p>Organise le tirage au sort en famille ou entre amis. Chacun reçoit un lien secret pour découvrir à qui il offre un cadeau.</p>
</header>
<form class="card" method="post" action="/create">
  <h2>Nouveau groupe</h2>
  ${infoFields({ name: '', budget: '', date: '', message: '' })}
  ${peopleFields({ people: '', exclusions: '' })}
  <button class="btn big-btn" type="submit">🎲 Créer le groupe et faire le tirage</button>
</form>
<div class="card muted">
  <h2>Comment ça marche ?</h2>
  <ol>
    <li>Tu saisis les participants, le tirage est fait automatiquement.</li>
    <li>Tu reçois un lien d'organisateur (à garder !) avec un lien perso pour chaque participant.</li>
    <li>Tu envoies à chacun son lien par WhatsApp, SMS ou email.</li>
    <li>Chacun découvre à qui il offre un cadeau et peut écrire sa liste d'idées.</li>
  </ol>
  <p>Même l'organisateur ne voit pas qui a tiré qui. 🤫</p>
</div>`);
}

function infoFields(g) {
  return `
  <label>Nom du groupe
    <input name="name" maxlength="80" required placeholder="Noël 2026 chez Mamie" value="${esc(g.name)}">
  </label>
  <div class="row">
    <label>Budget
      <input name="budget" maxlength="30" placeholder="30 €" value="${esc(g.budget)}">
    </label>
    <label>Date de l'échange
      <input name="date" type="date" value="${esc(g.date)}">
    </label>
  </div>
  <label>Message pour les participants <span class="hint">(facultatif)</span>
    <textarea name="message" maxlength="500" rows="2" placeholder="On se retrouve le 24 au soir !">${esc(g.message)}</textarea>
  </label>`;
}

function peopleFields(v) {
  return `
  <label>Participants <span class="hint">(un prénom par ligne, 3 minimum)</span>
    <textarea name="people" rows="7" required placeholder="Alice&#10;Bob&#10;Chloé&#10;David">${esc(v.people)}</textarea>
  </label>
  <label>Exclusions <span class="hint">(facultatif) : une ligne par couple ou foyer, prénoms séparés par des virgules. Les personnes d'une même ligne ne se tireront pas entre elles.</span>
    <textarea name="exclusions" rows="3" placeholder="Alice, Bob&#10;Chloé, David">${esc(v.exclusions)}</textarea>
  </label>`;
}

async function adminPage(env, url, group, nonce) {
  const seenKeys = new Set((await listKeys(env, `s:${group.id}:`)).map((k) => k.split(':')[2]));
  const adminUrl = `${url.origin}/a/${group.id}/${group.adminToken}`;
  const ok = url.searchParams.get('ok');
  const nameOf = new Map(group.people.map((p) => [p.id, p.name]));
  const seenCount = group.people.filter((p) => seenKeys.has(p.id)).length;

  const banner = {
    new: `<div class="card success"><h2>🎉 Groupe créé, tirage effectué !</h2>
      <p><strong>Garde précieusement ce lien d'organisateur</strong> (ajoute le à tes favoris). C'est le seul moyen de revenir sur cette page :</p>
      <div class="copyrow"><input readonly value="${esc(adminUrl)}"><button class="btn small" type="button" data-copy="${esc(adminUrl)}">Copier</button></div></div>`,
    draw: `<div class="card success"><p>✅ Nouveau tirage effectué. Préviens tout le monde de rouvrir son lien (les liens ne changent pas).</p></div>`,
    info: `<div class="card success"><p>✅ Informations mises à jour.</p></div>`,
  }[ok] || '';

  const rows = group.people.map((p) => {
    const link = `${url.origin}/p/${group.id}/${p.token}`;
    const msg = `🎅 Secret Santa « ${group.name} » : voici ton lien personnel pour découvrir à qui tu offres un cadeau (ne le partage pas !) ${link}`;
    return `<li class="person">
      <div class="who"><strong>${esc(p.name)}</strong>
        <span class="status ${seenKeys.has(p.id) ? 'yes' : 'no'}">${seenKeys.has(p.id) ? '✅ a découvert' : '⏳ pas encore ouvert'}</span></div>
      <div class="actions">
        <button class="btn small" type="button" data-copy="${esc(msg)}">Copier le message</button>
        <a class="btn small wa" target="_blank" rel="noopener noreferrer" href="https://wa.me/?text=${encodeURIComponent(msg)}">WhatsApp</a>
        <a class="btn small ghost" href="sms:?&body=${encodeURIComponent(msg)}">SMS</a>
      </div>
    </li>`;
  }).join('');

  const exclusionsText = group.exclusions.map((ex) => ex.map((id) => nameOf.get(id)).join(', ')).join('\n');
  const base = `/a/${group.id}/${group.adminToken}`;

  return page(nonce, `${group.name} (organisateur)`, `
${banner}
<div class="card">
  <p class="tag">Espace organisateur</p>
  <h1>🎄 ${esc(group.name)}</h1>
  ${infoSummary(group)}
  <p><strong>${seenCount} / ${group.people.length}</strong> participants ont découvert leur tirage.</p>
</div>
<div class="card">
  <h2>Liens des participants</h2>
  <p class="hint">Envoie à chacun <strong>son propre</strong> lien. Évite d'ouvrir les liens des autres, sinon tu verras leur tirage. 😉</p>
  <ul class="people">${rows}</ul>
</div>
<details class="card">
  <summary>✏️ Modifier les informations</summary>
  <form method="post" action="${base}/info">
    ${infoFields(group)}
    <button class="btn" type="submit">Enregistrer</button>
  </form>
</details>
<details class="card">
  <summary>👥 Modifier les participants ou exclusions</summary>
  <form method="post" action="${base}/participants" data-confirm="Cela refait entièrement le tirage. Ceux qui ont déjà découvert leur tirage devront rouvrir leur lien. Continuer ?">
    <p class="hint">Les liens et listes d'idées des personnes déjà inscrites sont conservés. Un nouveau tirage sera effectué.</p>
    ${peopleFields({ people: group.people.map((p) => p.name).join('\n'), exclusions: exclusionsText })}
    <button class="btn" type="submit">Enregistrer et refaire le tirage</button>
  </form>
</details>
<details class="card">
  <summary>⚙️ Autres actions</summary>
  <form method="post" action="${base}/redraw" data-confirm="Refaire le tirage ? Ceux qui ont déjà découvert leur tirage devront rouvrir leur lien.">
    <button class="btn ghost" type="submit">🎲 Refaire le tirage</button>
  </form>
  <form method="post" action="${base}/delete" data-confirm="Supprimer définitivement ce groupe et toutes ses données ?">
    <button class="btn danger" type="submit">🗑️ Supprimer le groupe</button>
  </form>
</details>`);
}

async function participantPage(env, url, group, person, nonce) {
  const [seen, myWish] = await Promise.all([
    env.SANTA.get(`s:${group.id}:${person.id}`),
    env.SANTA.get(`w:${group.id}:${person.id}`),
  ]);
  const base = `/p/${group.id}/${person.token}`;
  const receiver = group.people.find((p) => p.id === group.assignments[person.id]);

  let draw;
  if (!receiver) {
    draw = `<p class="error">Le tirage n'est pas disponible. Contacte l'organisateur.</p>`;
  } else if (!seen) {
    draw = `<form method="post" action="${base}/reveal">
      <button class="btn big-btn" type="submit">🎁 Découvrir à qui j'offre un cadeau</button>
    </form>
    <p class="hint center">Assure toi que personne ne regarde ton écran ! Même l'organisateur ne connaît pas le résultat.</p>`;
  } else {
    const theirWish = await env.SANTA.get(`w:${group.id}:${receiver.id}`);
    draw = `<p class="center">Tu offres un cadeau à</p>
    <p class="receiver">${esc(receiver.name)}</p>
    <h3>💡 Ses idées cadeaux</h3>
    ${theirWish ? `<div class="wish">${linkify(theirWish)}</div>` : `<p class="hint">${esc(receiver.name)} n'a pas encore écrit sa liste. Repasse plus tard sur ce lien !</p>`}`;
  }

  return page(nonce, group.name, `
<div class="card">
  <p class="tag">🎄 ${esc(group.name)}</p>
  <h1>Salut ${esc(person.name)} 👋</h1>
  ${infoSummary(group)}
</div>
<div class="card reveal">${draw}</div>
${url.searchParams.get('ok') === 'wish' ? `<div class="card success"><p>✅ Ta liste est enregistrée.</p></div>` : ''}
<form class="card" method="post" action="${base}/wishlist">
  <h2>📝 Ma liste d'idées</h2>
  <p class="hint">Elle sera visible uniquement par la personne qui doit t'offrir un cadeau. Tu peux mettre des liens.</p>
  <textarea name="wishlist" rows="6" maxlength="${MAX_WISH}" placeholder="Un bon livre de cuisine&#10;Des chaussettes rigolotes (taille 42)&#10;https://...">${esc(myWish || '')}</textarea>
  <button class="btn" type="submit">Enregistrer ma liste</button>
</form>
<p class="hint center">Garde ce lien : il te permet de revenir voir ton tirage et les idées de ta personne.</p>`);
}

function infoSummary(g) {
  const items = [];
  if (g.budget) items.push(`<li>💶 Budget : <strong>${esc(g.budget)}</strong></li>`);
  if (g.date) items.push(`<li>📅 Échange : <strong>${esc(formatDate(g.date))}</strong></li>`);
  const msg = g.message ? `<p class="message">${esc(g.message)}</p>` : '';
  return (items.length ? `<ul class="info">${items.join('')}</ul>` : '') + msg;
}

function formatDate(d) {
  try {
    return new Date(`${d}T12:00:00Z`).toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC' });
  } catch {
    return d;
  }
}

function notFound(nonce) {
  return page(nonce, 'Introuvable', `<div class="card"><h1>Lien introuvable 🎅</h1><p>Ce lien n'existe pas ou le groupe a été supprimé. Vérifie que tu as copié le lien en entier.</p><p><a class="btn" href="/">Créer un groupe</a></p></div>`, 404);
}

function redirect(location) {
  return new Response(null, { status: 303, headers: { Location: location, 'Cache-Control': 'no-store' } });
}

function page(nonce, title, body, status = 200) {
  const html = `<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>${esc(title)}</title>
<link rel="icon" href="data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 100 100%22><text y=%22.9em%22 font-size=%2290%22>🎅</text></svg>">
<style>${CSS}</style>
</head>
<body>
<main>${body}</main>
<footer>🎁 Secret Santa</footer>
<script nonce="${nonce}">${JS}</script>
</body>
</html>`;
  return new Response(html, {
    status,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'no-store',
      'Referrer-Policy': 'no-referrer',
      'X-Robots-Tag': 'noindex, nofollow',
      'X-Content-Type-Options': 'nosniff',
      'Content-Security-Policy': `default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${nonce}'; img-src data:; form-action 'self'; base-uri 'none'; frame-ancestors 'none'`,
    },
  });
}

// ---------- Utilitaires ----------

async function readForm(request) {
  try {
    return await request.formData();
  } catch {
    throw new UserError('Formulaire invalide.');
  }
}

function token(bytes) {
  const buf = crypto.getRandomValues(new Uint8Array(bytes));
  return btoa(String.fromCharCode(...buf)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function safeEqual(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function esc(s) {
  return String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

function linkify(text) {
  return esc(text).replace(/https?:\/\/[^\s<>"]+/g, (u) => `<a href="${u}" target="_blank" rel="noopener noreferrer nofollow">${u}</a>`);
}

const JS = `
document.querySelectorAll('[data-copy]').forEach(function (b) {
  b.addEventListener('click', function () {
    var text = b.getAttribute('data-copy');
    var done = function () { var t = b.textContent; b.textContent = 'Copié ✓'; setTimeout(function () { b.textContent = t; }, 1500); };
    if (navigator.clipboard) navigator.clipboard.writeText(text).then(done, function () { prompt('Copie ce texte :', text); });
    else prompt('Copie ce texte :', text);
  });
});
document.querySelectorAll('form[data-confirm]').forEach(function (f) {
  f.addEventListener('submit', function (e) { if (!confirm(f.getAttribute('data-confirm'))) e.preventDefault(); });
});
document.querySelectorAll('[data-back]').forEach(function (a) {
  a.addEventListener('click', function (e) { e.preventDefault(); history.back(); });
});
`;

const CSS = `
*{box-sizing:border-box}
html{background:#7d121a}
body{margin:0;font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;color:#1f2933;line-height:1.5;
  background:#b3202a radial-gradient(circle at 20% 10%,#d33a43 0,#b3202a 40%,#7d121a 100%) fixed;min-height:100vh}
main{max-width:640px;margin:0 auto;padding:20px 14px}
h1{margin:.2em 0 .4em;font-size:1.7rem}
h2{margin:0 0 .6em;font-size:1.25rem}
h3{margin:1.2em 0 .4em;font-size:1.05rem}
.hero{text-align:center;color:#fff;padding:20px 0 10px}
.hero .big{font-size:4rem;line-height:1}
.hero p{opacity:.92}
.card{background:#fff;border-radius:16px;padding:18px 18px;margin:0 0 16px;box-shadow:0 8px 24px rgba(0,0,0,.18)}
.card.success{background:#e8f7ee;border:2px solid #2f9e5b}
.card.muted{background:#fff8f0}
label{display:block;font-weight:600;margin:0 0 14px}
input,textarea{display:block;width:100%;margin-top:6px;padding:10px 12px;border:1.5px solid #cbd2d9;border-radius:10px;font:inherit;font-weight:400;background:#fff}
input:focus,textarea:focus{outline:none;border-color:#1e7a46;box-shadow:0 0 0 3px rgba(30,122,70,.15)}
.row{display:flex;gap:12px}.row label{flex:1}
.hint{font-weight:400;color:#616e7c;font-size:.9rem}
.center{text-align:center}
.btn{display:inline-block;border:0;border-radius:10px;padding:11px 18px;font:inherit;font-weight:700;cursor:pointer;
  background:#1e7a46;color:#fff;text-decoration:none;margin:4px 0}
.btn:hover{filter:brightness(1.08)}
.btn.small{padding:7px 12px;font-size:.88rem;margin:3px 4px 3px 0}
.btn.ghost{background:#eef2f5;color:#1f2933}
.btn.wa{background:#25d366;color:#fff}
.btn.danger{background:#c62828}
.big-btn{width:100%;font-size:1.1rem;padding:15px}
.error{color:#b3202a;font-weight:600}
.tag{margin:0;color:#b3202a;font-weight:700;font-size:.9rem;text-transform:uppercase;letter-spacing:.04em}
.info{list-style:none;padding:0;margin:0 0 8px}
.message{background:#fff8f0;border-left:4px solid #e0a100;padding:8px 12px;border-radius:6px;white-space:pre-wrap}
.people{list-style:none;padding:0;margin:0}
.person{border-top:1px solid #e4e7eb;padding:12px 0}
.person:first-child{border-top:0}
.who{display:flex;justify-content:space-between;align-items:center;gap:8px;flex-wrap:wrap}
.status{font-size:.85rem}.status.yes{color:#1e7a46}.status.no{color:#8a6d00}
.actions{margin-top:6px}
.copyrow{display:flex;gap:8px;align-items:center}.copyrow input{margin:0}
.reveal{text-align:left}
.receiver{text-align:center;font-size:2.2rem;font-weight:800;color:#b3202a;margin:0 0 6px}
.wish{white-space:pre-wrap;background:#f5f7fa;border-radius:10px;padding:12px;overflow-wrap:anywhere}
details summary{cursor:pointer;font-weight:700;font-size:1.05rem}
details[open] summary{margin-bottom:12px}
details form{margin:0 0 8px}
footer{text-align:center;color:rgba(255,255,255,.75);padding:10px 0 30px;font-size:.9rem}
@media (max-width:480px){.row{flex-direction:column;gap:0}h1{font-size:1.45rem}}
`;
