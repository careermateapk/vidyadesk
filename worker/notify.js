// VidyaDesk notification server (Cloudflare Worker).
// The app sends: POST { inst, kind, title, body, topics[] } with the user's Firebase login token.
// We check who is sending, then ask Firebase Cloud Messaging to deliver to those topics.

const enc = new TextEncoder();

const json = (o, status = 200) =>
  new Response(JSON.stringify(o), { status, headers: { 'Content-Type': 'application/json' } });

function b64urlBytes(bytes) {
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
const b64urlStr = (str) => b64urlBytes(enc.encode(str));
function b64urlDecode(s) {
  s = s.replace(/-/g, '+').replace(/_/g, '/');
  while (s.length % 4) s += '=';
  return Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
}
const b64urlDecodeStr = (s) => new TextDecoder().decode(b64urlDecode(s));

// ---- Firebase login token check ----
let jwks = null;
let jwksAt = 0;
export async function verifyIdToken(idToken, projectId, now = Date.now(), fetchKeys = defaultKeys) {
  const parts = (idToken || '').split('.');
  if (parts.length !== 3) throw new Error('no_token');
  const [h, p, s] = parts;
  const header = JSON.parse(b64urlDecodeStr(h));
  const payload = JSON.parse(b64urlDecodeStr(p));
  const sec = Math.floor(now / 1000);
  if (header.alg !== 'RS256') throw new Error('bad_alg');
  if (payload.aud !== projectId || payload.iss !== `https://securetoken.google.com/${projectId}`) throw new Error('bad_project');
  if (!payload.sub || payload.exp < sec || payload.iat > sec + 300) throw new Error('expired');
  const keys = await fetchKeys(now);
  const jwk = keys.find((k) => k.kid === header.kid);
  if (!jwk) throw new Error('bad_kid');
  const key = await crypto.subtle.importKey('jwk', { kty: jwk.kty, n: jwk.n, e: jwk.e, alg: 'RS256', ext: true }, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
  const ok = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, b64urlDecode(s), enc.encode(`${h}.${p}`));
  if (!ok) throw new Error('bad_signature');
  return payload.sub;
}

// Same check, but gives back the whole login (uid + email).
export async function verifyLogin(idToken, projectId, now = Date.now(), fetchKeys = defaultKeys) {
  await verifyIdToken(idToken, projectId, now, fetchKeys);
  const payload = JSON.parse(b64urlDecodeStr(idToken.split('.')[1]));
  return { uid: payload.sub, email: String(payload.email || '').toLowerCase() };
}
async function defaultKeys(now) {
  if (!jwks || now - jwksAt > 3600e3) {
    const r = await fetch('https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com');
    jwks = (await r.json()).keys || [];
    jwksAt = now;
  }
  return jwks;
}

// ---- Google access token from the service account ----
let access = null;
let accessExp = 0;
async function accessToken(sa) {
  if (access && Date.now() < accessExp - 60e3) return access;
  const now = Math.floor(Date.now() / 1000);
  const head = b64urlStr(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claim = b64urlStr(
    JSON.stringify({
      iss: sa.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging https://www.googleapis.com/auth/datastore',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    }),
  );
  const pem = sa.private_key.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', der, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const sig = new Uint8Array(await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, enc.encode(`${head}.${claim}`)));
  const r = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${head}.${claim}.${b64urlBytes(sig)}`,
  });
  const j = await r.json();
  if (!j.access_token) throw new Error('oauth_failed');
  access = j.access_token;
  accessExp = Date.now() + (j.expires_in || 3600) * 1000;
  return access;
}

async function membership(token, projectId, uid, inst) {
  const r = await fetch(`https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/memberships/${uid}_${inst}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (r.status === 404) return null;
  if (!r.ok) throw new Error('firestore_' + r.status);
  const f = (await r.json()).fields || {};
  return { role: f.role?.stringValue || '', status: f.status?.stringValue || '' };
}

// ---- who may send what ----
// Topics: l_<inst> all students+parents, s_<inst> all staff, a_<inst> admins,
//         b_<inst>_<batch> one batch, u_<inst>_<uid> one person.
export function checkRequest(b) {
  const inst = String(b.inst || '');
  const topics = Array.isArray(b.topics) ? b.topics.map(String) : [];
  if (!/^[A-Za-z0-9_-]{4,64}$/.test(inst) || inst.includes('_')) return 'bad_inst';
  if (!topics.length || topics.length > 5) return 'bad_topics';
  const re = new RegExp(`^(?:[lsa]_${inst}|[bu]_${inst}_[A-Za-z0-9-]{1,64})$`);
  if (!topics.every((t) => re.test(t))) return 'bad_topic';
  return null;
}

export function allowed(m, kind, topics) {
  if (!m) return false;
  const toStaff = topics.every((t) => /^[sa]_/.test(t));
  if (m.status === 'approved' && (m.role === 'admin' || m.role === 'teacher')) return true;
  if (m.status === 'approved' && (m.role === 'student' || m.role === 'parent')) return toStaff && ['doubt', 'fee_claim'].includes(kind);
  if (m.status === 'pending') return toStaff && kind === 'join';
  return false;
}


// ---- daily plan reminders (runs every morning) ----
const DAY = 86400e3;
// [from, to) window relative to now, who gets it, and the message
export const PLAN_STEPS = [
  { lo: 6 * DAY, hi: 7 * DAY, to: ['a'], title: '⏳ VidyaDesk plan 7 din mein khatam', body: '{name}: renew kar lijiye taaki teachers, students aur parents ka app chalta rahe.' },
  { lo: 2 * DAY, hi: 3 * DAY, to: ['a', 's'], title: '⏳ VidyaDesk plan 3 din mein khatam', body: '{name}: plan renew karein. Admin app → Plan chuno.' },
  { lo: -1 * DAY, hi: 0, to: ['a', 's'], title: '⚠️ VidyaDesk plan khatam ho gaya', body: '{name}: 3 din tak app sirf dekh sakte hain. Admin abhi renew karein.' },
  { lo: -4 * DAY, hi: -3 * DAY, to: ['a', 's', 'l'], title: '🔒 VidyaDesk app band ho gaya', body: '{name}: plan renew hote hi sab wapas chalu. Aapka data safe hai.' },
];

async function institutesEnding(token, projectId, lo, hi) {
  const r = await fetch(`https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:runQuery`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      structuredQuery: {
        from: [{ collectionId: 'institutes' }],
        where: {
          compositeFilter: {
            op: 'AND',
            filters: [
              { fieldFilter: { field: { fieldPath: 'planUntil' }, op: 'GREATER_THAN_OR_EQUAL', value: { integerValue: String(Math.floor(lo)) } } },
              { fieldFilter: { field: { fieldPath: 'planUntil' }, op: 'LESS_THAN', value: { integerValue: String(Math.floor(hi)) } } },
            ],
          },
        },
        limit: 500,
      },
    }),
  });
  if (!r.ok) throw new Error('query_' + r.status);
  const rows = await r.json();
  return rows
    .filter((x) => x.document)
    .map((x) => ({ id: x.document.name.split('/').pop(), name: x.document.fields?.name?.stringValue || 'VidyaDesk' }));
}

async function sendFcm(token, projectId, topics, title, body, inst, kind) {
  const target = topics.length === 1 ? { topic: topics[0] } : { condition: topics.map((t) => `'${t}' in topics`).join(' || ') };
  const r = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      message: { ...target, notification: { title, body }, android: { priority: 'HIGH', notification: { sound: 'default' } }, data: { kind, inst } },
    }),
  });
  return r.ok;
}

export async function planReminders(env, now = Date.now()) {
  const token = await accessToken(JSON.parse(env.SA_JSON));
  let sent = 0;
  for (const st of PLAN_STEPS) {
    for (const inst of await institutesEnding(token, env.PROJECT_ID, now + st.lo, now + st.hi)) {
      const topics = st.to.map((t) => `${t}_${inst.id}`);
      if (await sendFcm(token, env.PROJECT_ID, topics, st.title, st.body.replace('{name}', inst.name), inst.id, 'plan')) sent++;
    }
  }
  return sent;
}

// ---- VidyaDesk plans: the admin pays by UPI, the plan starts at once ----
export const OWNER_EMAILS = ['support.sangam360@gmail.com'];
export const DEMO_EMAILS = ['ksuraj.th@gmail.com'];
export const PRICES = { basic: [299, 2990], standard: [599, 5990], pro: [999, 9990] };

export function extendUntil(current, yearly, now = Date.now()) {
  const d = new Date(Math.max(current || 0, now));
  const day = d.getUTCDate();
  if (yearly) d.setUTCFullYear(d.getUTCFullYear() + 1);
  else d.setUTCMonth(d.getUTCMonth() + 1);
  if (d.getUTCDate() !== day) d.setUTCDate(0); // 31 Jan + 1 month = 28/29 Feb
  return d.getTime();
}

const fsBase = (pid) => `https://firestore.googleapis.com/v1/projects/${pid}/databases/(default)/documents`;
const fv = (v) =>
  typeof v === 'boolean' ? { booleanValue: v } : typeof v === 'number' ? { integerValue: String(Math.round(v)) } : { stringValue: String(v ?? '') };

async function fsGet(token, pid, path) {
  const r = await fetch(`${fsBase(pid)}/${path}`, { headers: { Authorization: `Bearer ${token}` } });
  if (r.status === 404) return null;
  if (!r.ok) throw new Error('firestore_' + r.status);
  const f = (await r.json()).fields || {};
  const o = {};
  for (const [k, v] of Object.entries(f)) o[k] = v.stringValue ?? (v.integerValue !== undefined ? Number(v.integerValue) : v.doubleValue ?? v.booleanValue ?? null);
  return o;
}

async function fsPatch(token, pid, path, obj, mask) {
  const q = mask ? '?' + mask.map((m) => `updateMask.fieldPaths=${m}`).join('&') : '';
  const fields = {};
  for (const [k, v] of Object.entries(obj)) fields[k] = fv(v);
  const r = await fetch(`${fsBase(pid)}/${path}${q}`, {
    method: 'PATCH',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ fields }),
  });
  if (!r.ok) throw new Error('firestore_write_' + r.status);
}

export function checkPlanRequest(b) {
  const inst = String(b.inst || '');
  if (!/^[A-Za-z0-9_-]{4,64}$/.test(inst) || inst.includes('_')) return 'bad_inst';
  if (!PRICES[b.plan]) return 'bad_plan';
  if (!['success', 'unsure'].includes(b.result)) return 'bad_result';
  return null;
}

async function buyPlan(env, login, b) {
  const bad = checkPlanRequest(b);
  if (bad) return json({ error: bad }, 400);
  const token = await accessToken(JSON.parse(env.SA_JSON));
  const pid = env.PROJECT_ID;
  const m = await membership(token, pid, login.uid, b.inst);
  if (!m || m.role !== 'admin' || m.status !== 'approved') return json({ error: 'forbidden' }, 403);
  const inst = await fsGet(token, pid, `institutes/${b.inst}`);
  if (!inst) return json({ error: 'no_institute' }, 404);
  const demo = DEMO_EMAILS.includes(login.email);
  const yearly = b.yearly === true;
  const amount = PRICES[b.plan][yearly ? 1 : 0];
  const now = Date.now();
  const start = demo || b.result === 'success';
  const prevPlan = inst.plan || 'trial';
  const prevUntil = Number(inst.planUntil || 0);
  const newUntil = extendUntil(prevUntil, yearly, now);
  const id = `${b.inst}_${now}`;
  const pay = {
    id,
    instituteId: b.inst,
    instituteName: String(inst.name || ''),
    adminUid: login.uid,
    adminName: String(b.adminName || '').slice(0, 80),
    phone: String(b.phone || '').slice(0, 20),
    plan: b.plan,
    yearly,
    amount,
    utr: String(b.ref || '').slice(0, 40),
    via: String(b.via || '').slice(0, 40),
    status: start ? 'auto' : 'pending',
    demo,
    prevPlan,
    prevUntil,
    newUntil: start ? newUntil : 0,
    createdAt: now,
    decidedAt: 0,
  };
  await fsPatch(token, pid, `subPayments/${id}`, pay);
  if (start) await fsPatch(token, pid, `institutes/${b.inst}`, { plan: b.plan, planUntil: newUntil }, ['plan', 'planUntil']);
  return json({ ok: true, id, started: start, planUntil: start ? newUntil : prevUntil, amount, demo });
}

export default {
  async scheduled(event, env, ctx) {
    ctx.waitUntil(planReminders(env).catch((e) => console.log('plan reminders failed', e)));
  },
  async fetch(req, env) {
    if (req.method !== 'POST') return json({ ok: true, service: 'vidyadesk-notify' });
    let uid, login;
    try {
      login = await verifyLogin((req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, ''), env.PROJECT_ID);
      uid = login.uid;
    } catch (e) {
      return json({ error: String(e.message || e) }, 401);
    }
    try {
      const b = await req.json();
      if (b.action === 'plan') return await buyPlan(env, login, b);
      const bad = checkRequest(b);
      if (bad) return json({ error: bad }, 400);
      const inst = String(b.inst);
      const kind = String(b.kind || 'general').slice(0, 30);
      const topics = b.topics.map(String);
      const title = String(b.title || 'VidyaDesk').slice(0, 120);
      const body = String(b.body || '').slice(0, 400);
      const sa = JSON.parse(env.SA_JSON);
      const token = await accessToken(sa);
      const m = await membership(token, env.PROJECT_ID, uid, inst);
      if (!OWNER_EMAILS.includes(login.email) && !allowed(m, kind, topics)) return json({ error: 'forbidden' }, 403);
      const target = topics.length === 1 ? { topic: topics[0] } : { condition: topics.map((t) => `'${t}' in topics`).join(' || ') };
      const r = await fetch(`https://fcm.googleapis.com/v1/projects/${env.PROJECT_ID}/messages:send`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: {
            ...target,
            notification: { title, body },
            android: { priority: 'HIGH', notification: { sound: 'default' } },
            data: { kind, inst, from: uid },
          },
        }),
      });
      if (!r.ok) return json({ error: 'fcm', detail: (await r.text()).slice(0, 300) }, 502);
      return json({ ok: true });
    } catch (e) {
      return json({ error: String(e.message || e) }, 500);
    }
  },
};
