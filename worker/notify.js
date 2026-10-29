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
  // Only a verified email counts (owner / demo checks use it).
  return { uid: payload.sub, email: payload.email_verified === true ? String(payload.email || '').toLowerCase() : '' };
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
  const re = new RegExp(`^(?:owner|[lsa]_${inst}|[bu]_${inst}_[A-Za-z0-9-]{1,64})$`);
  if (!topics.every((t) => re.test(t))) return 'bad_topic';
  return null;
}

export function allowed(m, kind, topics) {
  if (!m) return false;
  // Help box: only an approved admin may write to the VidyaDesk owner.
  if (topics.includes('owner')) return topics.every((t) => t === 'owner') && kind === 'ticket' && m.status === 'approved' && m.role === 'admin';
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
  const val = (v) =>
    v.arrayValue ? (v.arrayValue.values || []).map(val) : v.stringValue ?? (v.integerValue !== undefined ? Number(v.integerValue) : v.doubleValue ?? v.booleanValue ?? null);
  for (const [k, v] of Object.entries(f)) o[k] = val(v);
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

// Plan prices: the owner can change them from the app (config/app → prices).
export function pickPrices(cfg) {
  const out = { ...PRICES };
  const p = cfg && cfg.prices;
  if (p && typeof p === 'object') {
    for (const k of Object.keys(PRICES)) {
      const v = p[k];
      if (Array.isArray(v) && Number(v[0]) > 0 && Number(v[1]) > 0) out[k] = [Number(v[0]), Number(v[1])];
    }
  }
  return out;
}

async function appPrices(token, pid) {
  try {
    const r = await fetch(`${fsBase(pid)}/config/app`, { headers: { Authorization: `Bearer ${token}` } });
    if (!r.ok) return PRICES;
    return pickPrices(decodeFields((await r.json()).fields || {}));
  } catch (_) {
    return PRICES;
  }
}

// Discount from a coupon document (0 when it can't be used).
export function couponDiscount(c, plan, yearly, amount, now = Date.now()) {
  if (!c || c.active === false) return 0;
  if (Number(c.until || 0) > 0 && now > Number(c.until)) return 0;
  if (Number(c.maxUses || 0) > 0 && Number(c.used || 0) >= Number(c.maxUses)) return 0;
  const plans = Array.isArray(c.plans) ? c.plans : [];
  if (plans.length && !plans.includes(plan)) return 0;
  if (c.yearlyOnly === true && !yearly) return 0;
  const v = Number(c.value || 0);
  const off = c.pct === false ? v : Math.round((amount * v) / 100);
  return Math.max(0, Math.min(amount, off));
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
  const prices = await appPrices(token, pid);
  let amount = prices[b.plan][yearly ? 1 : 0];
  const code = String(b.coupon || '').trim().toUpperCase().replace(/\s/g, '');
  let couponUsed = '';
  if (code) {
    const c = await fsGet(token, pid, `coupons/${encodeURIComponent(code)}`).catch(() => null);
    const off = couponDiscount(c, b.plan, yearly, amount, Date.now());
    if (off > 0) {
      amount -= off;
      couponUsed = code;
      await fsPatch(token, pid, `coupons/${encodeURIComponent(code)}`, { used: Number(c.used || 0) + 1 }, ['used']).catch(() => {});
    }
  }
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
    coupon: couponUsed,
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

// ---- daily: fee due reminders (morning) and missed teacher check-in (evening) ----
const IST = 5.5 * 3600e3;
const pad2 = (n) => String(n).padStart(2, '0');

function decodeFields(f = {}) {
  const val = (v) =>
    v.arrayValue
      ? (v.arrayValue.values || []).map(val)
      : v.mapValue
        ? decodeFields(v.mapValue.fields || {})
        : v.stringValue ?? (v.integerValue !== undefined ? Number(v.integerValue) : v.doubleValue ?? v.booleanValue ?? null);
  const o = {};
  for (const [k, v] of Object.entries(f)) o[k] = val(v);
  return o;
}

async function listDocs(token, pid, path) {
  const out = [];
  let page = '';
  for (let i = 0; i < 20; i++) {
    const r = await fetch(`${fsBase(pid)}/${path}?pageSize=300${page ? `&pageToken=${page}` : ''}`, { headers: { Authorization: `Bearer ${token}` } });
    if (!r.ok) break;
    const j = await r.json();
    for (const d of j.documents || []) out.push({ id: d.name.split('/').pop(), ...decodeFields(d.fields) });
    if (!j.nextPageToken) break;
    page = j.nextPageToken;
  }
  return out;
}

async function queryEq(token, pid, parent, collection, field, value) {
  const r = await fetch(`${fsBase(pid)}${parent ? '/' + parent : ''}:runQuery`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      structuredQuery: { from: [{ collectionId: collection }], where: { fieldFilter: { field: { fieldPath: field }, op: 'EQUAL', value: { stringValue: value } } }, limit: 2000 },
    }),
  });
  if (!r.ok) return [];
  return (await r.json()).filter((x) => x.document).map((x) => ({ id: x.document.name.split('/').pop(), ...decodeFields(x.document.fields) }));
}

const planLive = (inst, now) => !inst.planUntil || Number(inst.planUntil) > now;
const notifOn = (inst, k) => !(inst.notif && inst.notif[k] === false);

// Which fee message (if any) goes out today. dueDay: 1..28.
export function feeStep(day, dueDay) {
  if (day === dueDay - 2) return 'soon';
  if (day === dueDay) return 'today';
  if (day === dueDay + 3) return 'late';
  return '';
}

export async function feeReminders(env, now = Date.now()) {
  const token = await accessToken(JSON.parse(env.SA_JSON));
  const pid = env.PROJECT_ID;
  const ist = new Date(now + IST);
  const day = ist.getUTCDate();
  const month = `${ist.getUTCFullYear()}-${pad2(ist.getUTCMonth() + 1)}`;
  let sent = 0;
  for (const inst of await listDocs(token, pid, 'institutes')) {
    if (!planLive(inst, now) || !notifOn(inst, 'feeDue')) continue;
    const due = Math.min(28, Math.max(1, Number(inst.dueDay || 10)));
    const step = feeStep(day, due);
    if (!step) continue;
    const mems = (await queryEq(token, pid, '', 'memberships', 'instituteId', inst.id)).filter((m) => m.status === 'approved');
    const fees = await queryEq(token, pid, `institutes/${inst.id}`, 'fees', 'month', month);
    const paid = new Set(fees.filter((f) => f.paid === true || f.claimed === true).map((f) => f.studentUid));
    const dueDate = `${due} ${['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][ist.getUTCMonth()]}`;
    const title = step === 'soon' ? `💰 Fees ${dueDate} tak bharni hai` : step === 'today' ? '💰 Aaj fees ki last date hai' : '⚠️ Fees late ho gayi';
    for (const st of mems.filter((m) => m.role === 'student' && !paid.has(m.uid))) {
      const parents = mems.filter((m) => m.role === 'parent' && Array.isArray(m.childUids) && m.childUids.includes(st.uid)).map((m) => `u_${inst.id}_${m.uid}`);
      const topics = [`u_${inst.id}_${st.uid}`, ...parents].slice(0, 5);
      const body = `${st.name} · ${inst.name}${step === 'late' && Number(inst.lateFee || 0) > 0 ? ` · late fee ₹${inst.lateFee}` : ''} — app mein UPI se bharein`;
      if (await sendFcm(token, pid, topics, title, body, inst.id, 'fee_due')) sent++;
    }
  }
  return sent;
}

export async function checkinReminders(env, now = Date.now()) {
  const token = await accessToken(JSON.parse(env.SA_JSON));
  const pid = env.PROJECT_ID;
  const ist = new Date(now + IST);
  const weekday = ist.getUTCDay() === 0 ? 7 : ist.getUTCDay(); // 1 = Monday … 7 = Sunday
  const key = `${ist.getUTCFullYear()}${pad2(ist.getUTCMonth() + 1)}${pad2(ist.getUTCDate())}`;
  let sent = 0;
  for (const inst of await listDocs(token, pid, 'institutes')) {
    if (!planLive(inst, now) || !notifOn(inst, 'checkin')) continue;
    if (inst.geoCheckin !== true && inst.onlineCheckin !== true) continue; // check-in not used here
    const batches = (await listDocs(token, pid, `institutes/${inst.id}/batches`)).filter((b) => Array.isArray(b.days) && b.days.includes(weekday) && b.teacherUid);
    const teachers = new Map();
    for (const b of batches) if (b.teacherUid !== inst.ownerUid) teachers.set(b.teacherUid, b.teacherName || 'Teacher');
    const missed = [];
    for (const [uid, name] of teachers) {
      const c = await fsGet(token, pid, `institutes/${inst.id}/checkins/${uid}_${key}`).catch(() => null);
      if (!c) missed.push(name);
    }
    if (!missed.length) continue;
    if (await sendFcm(token, pid, [`a_${inst.id}`], `🕘 Aaj check-in nahi kiya: ${missed.slice(0, 3).join(', ')}${missed.length > 3 ? ` +${missed.length - 3}` : ''}`, inst.name, inst.id, 'checkin')) sent++;
  }
  return sent;
}

// ---- morning: tell the owner how many coachings have not opened the app for 7+ days ----
export function sleepingCount(insts, now = Date.now()) {
  return insts.filter((i) => {
    const until = Number(i.planUntil || 0);
    if (until > 0 && until + 3 * DAY < now) return false; // plan over → already "left"
    const last = Number(i.lastActive || 0);
    return last <= 0 || now - last > 7 * DAY;
  }).length;
}

async function sleepingNotice(env, now = Date.now()) {
  const token = await accessToken(JSON.parse(env.SA_JSON));
  const insts = await listDocs(token, env.PROJECT_ID, 'institutes');
  const n = sleepingCount(insts, now);
  if (n <= 0) return 0;
  await sendFcm(token, env.PROJECT_ID, ['owner'], `😴 ${n} coaching app use nahi kar rahi`, '7 din se app nahi khola. Owner panel → So rahi → call / WhatsApp karein.', '', 'owner');
  return n;
}

export default {
  async scheduled(event, env, ctx) {
    if (event.cron === '30 15 * * *') {
      ctx.waitUntil(checkinReminders(env).catch((e) => console.log('check-in reminders failed', e)));
      return;
    }
    ctx.waitUntil(planReminders(env).catch((e) => console.log('plan reminders failed', e)));
    ctx.waitUntil(feeReminders(env).catch((e) => console.log('fee reminders failed', e)));
    ctx.waitUntil(sleepingNotice(env).catch((e) => console.log('sleeping notice failed', e)));
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
      if (b.action === 'broadcast') {
        if (!OWNER_EMAILS.includes(login.email)) return json({ error: 'forbidden' }, 403);
        const token = await accessToken(JSON.parse(env.SA_JSON));
        const ok = await sendFcm(token, env.PROJECT_ID, ['all'], String(b.title || 'VidyaDesk').slice(0, 120), String(b.body || '').slice(0, 400), '', 'broadcast');
        return json({ ok });
      }
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
