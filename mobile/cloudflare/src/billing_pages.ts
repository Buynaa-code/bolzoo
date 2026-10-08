import { billingLegalReady, type BillingEnvironment } from './billing';

type PageEnvironment = BillingEnvironment & { LEGAL_OPERATOR_NAME?: string; LEGAL_SUPPORT_EMAIL?: string };
const escape = (value: string) => value.replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]!);
const css = `:root{font:16px/1.65 system-ui,-apple-system,sans-serif;color:#362b32;background:#fff8fa;color-scheme:light}*{box-sizing:border-box}body{margin:0}main{max-width:780px;margin:48px auto;padding:0 22px}h1,h2,h3{line-height:1.2;color:#30272d}h1{font-size:clamp(32px,7vw,52px);letter-spacing:-1.6px}h2{font-size:23px}p{max-width:65ch}a{color:#ae355d}header{display:flex;justify-content:space-between;gap:16px;align-items:center;border-bottom:1px solid #eddde4;padding-bottom:16px}.brand{font-weight:800;font-size:22px}nav{display:flex;gap:16px;font-size:14px}.eyebrow{text-transform:uppercase;font-size:12px;letter-spacing:2px;color:#a64166;font-weight:800}.muted{color:#786973;font-size:14px}.notice{background:#fff1ce;color:#69470c;border:1px solid #ead4a0;padding:16px;border-radius:18px}.card{background:#fff;border:1px solid #eedde5;border-radius:24px;padding:24px;margin:22px 0;box-shadow:0 6px 0 #f4e5eb}.plans{display:grid;grid-template-columns:1fr 1fr;gap:14px}.plan{position:relative;border:2px solid #ecdce3;background:#fff;border-radius:20px;padding:20px;cursor:pointer}.plan:has(input:checked){border-color:#c45c80;background:#fff0f5}.plan input{margin-right:8px;accent-color:#bb4f76}.price{display:block;font-size:32px;font-weight:850;letter-spacing:-1px;margin:12px 0}.plan small{display:block;color:#786973}.field{display:block;font-size:14px;font-weight:650;margin:14px 0 5px}input[type=email],input[type=text]{width:100%;font:inherit;padding:13px 15px;border:1px solid #c9b9c1;border-radius:14px;background:#fff}input:focus-visible,button:focus-visible,a:focus-visible{outline:3px solid #773458;outline-offset:4px}button,.button{display:inline-block;border:0;border-radius:18px;padding:13px 22px;background:#c45c80;color:white;font:inherit;font-weight:750;text-align:center;cursor:pointer;text-decoration:none;box-shadow:0 4px 0 #913c5a;margin:14px 8px 7px 0}button:active,.button:active{transform:translateY(2px);box-shadow:0 2px 0 #913c5a}button:disabled{background:#d8c9cf;color:#746971;box-shadow:none;cursor:not-allowed}.secondary{color:#8f3658;background:#f6e8ed;box-shadow:0 4px 0 #dbc4ce}#message{min-height:28px;padding:8px 0}#message.error{color:#a11c38}#payment-state{font-weight:700}footer{padding:28px 0;color:#786973;font-size:13px;border-top:1px solid #eddee5;margin-top:40px}footer a{overflow-wrap:anywhere}[hidden]{display:none!important}fieldset{border:0;padding:0;margin:0}legend{font-weight:750;margin-bottom:12px}li{margin:10px 0}@media(max-width:520px){main{margin:22px auto}.plans{grid-template-columns:1fr}.card{padding:20px}.price{font-size:29px}header{align-items:flex-start}nav{flex-direction:column;gap:3px}}`;
const script = String.raw`'use strict';
(() => {
  const $ = (id) => document.getElementById(id);
  const legalReady = document.body.dataset.legalReady === 'true';
  const terminal = new Set(['succeeded', 'canceled', 'refunded']);
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  const storageKey = 'hamtdaa.plus.pending';
  let token = null, email = '', catalog = null, pending = null, order = null, busy = false, timer = null, pollingStarted = 0;
  function message(text, error = false) { $('message').textContent = text; $('message').classList.toggle('error', error); }
  function save() {
    try { if (pending) sessionStorage.setItem(storageKey, JSON.stringify(pending)); else sessionStorage.removeItem(storageKey); } catch { /* Safe recovery remains available by checking Plus status. */ }
  }
  function restore() {
    try {
      const value = JSON.parse(sessionStorage.getItem(storageKey) || 'null');
      if (value && (value.order_id === null || uuid.test(value.order_id)) && uuid.test(value.command_id) && ['monthly', 'yearly'].includes(value.plan)) pending = value;
    } catch { /* Ignore malformed local, non-authoritative order hints. */ }
    const returned = new URL(location.href).searchParams.get('order_id');
    if (returned && uuid.test(returned)) pending = { order_id: returned, command_id: crypto.randomUUID(), plan: 'monthly' };
    if (location.search || location.hash) history.replaceState(null, '', location.pathname);
  }
  function controls() {
    const ready = legalReady && catalog && catalog.web && catalog.web.ready === true;
    const open = order && !terminal.has(order.state);
    $('buy').disabled = busy || !token || !ready || Boolean(open);
    $('send-code').disabled = busy || Boolean(token);
    $('verify-code').disabled = busy || Boolean(token);
    $('sign-out').disabled = busy || !token;
    $('check-payment').disabled = busy || !token || !pending || !pending.order_id;
    for (const radio of document.querySelectorAll('input[name=plan]')) radio.disabled = busy || Boolean(open);
    $('sign-out').hidden = !token;
  }
  const errors = { rate_limited: 'Түр хүлээгээд дахин оролдоно уу.', invalid_code: 'Код буруу эсвэл хугацаа нь дууссан байна.',
    invalid_email: 'Имэйл хаягаа шалгана уу.', order_not_found: 'Энэ нэхэмжлэл таны бүртгэлд хамаарахгүй эсвэл олдсонгүй.',
    checkout_expired: 'Нэхэмжлэлийн хугацаа дууссан. Шинээр эхлүүлнэ үү.', command_conflict: 'Өмнөх төлбөрийн хүсэлтийн сонголт өөр байна.',
    billing_unavailable: 'Төлбөр одоогоор идэвхгүй байна.', legal_not_ready: 'Үйлчилгээ үзүүлэгчийн мэдээлэл баталгаажаагүй тул төлбөр хаалттай байна.',
    unauthenticated: 'Дахин нэвтэрч эрхээ шалгана уу.' };
  async function api(path, body, auth = true) {
    const headers = { Accept: 'application/json' };
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    if (auth) { if (!token) throw { code: 'unauthenticated' }; headers.Authorization = 'Bearer ' + token; }
    const response = await fetch(path, { method: body === undefined ? 'GET' : 'POST', headers, credentials: 'omit',
      ...(body === undefined ? {} : { body: JSON.stringify(body) }), signal: AbortSignal.timeout(15000), cache: 'no-store' });
    const data = await response.json();
    if (!response.ok || data.ok !== true) {
      if (response.status === 401) { token = null; $('login').hidden = false; $('signed-in').hidden = true; stopPolling(); }
      throw { code: typeof data.code === 'string' ? data.code : 'unavailable' };
    }
    return data;
  }
  async function action(work) {
    if (busy) return;
    busy = true; controls();
    try { await work(); } catch (error) { message(errors[error && error.code] || 'Үйлчилгээтэй холбогдож чадсангүй. Дахин шалгана уу.', true); }
    finally { busy = false; controls(); }
  }
  function stopPolling() { if (timer) clearTimeout(timer); timer = null; }
  function schedule() {
    stopPolling();
    if (!token || !pending || !pending.order_id || !order || terminal.has(order.state) || Date.now() - pollingStarted > 15 * 60 * 1000) return;
    timer = setTimeout(async () => {
      if (!document.hidden && !busy) await action(checkPayment);
      schedule();
    }, 6000);
  }
  function safeCheckout(value) {
    try { const url = new URL(value); return url.origin === 'https://pay.wire.mn' && !url.username && !url.password &&
      /^\/c\/[A-Za-z0-9_-]{1,300}$/.test(url.pathname) && !url.search && !url.hash ? url.href : null; } catch { return null; }
  }
  function showEntitlement(value) {
    const entitlement = value && value.entitlement;
    const active = entitlement && entitlement.tier === 'plus' && entitlement.premium_cards === true && Date.parse(entitlement.expires_at) > Date.now();
    $('entitlement').textContent = active ? 'Plus идэвхтэй · ' + (entitlement.source === 'partner' ? 'Хосын эрхээр · ' : '') +
      new Date(entitlement.expires_at).toLocaleDateString('mn-MN') + ' хүртэл' : 'Одоогоор үнэгүй эрхтэй.';
  }
  function showOrder(value) {
    order = value;
    $('payment').hidden = false;
    const labels = { reserved: 'Нэхэмжлэл бэлтгэж байна', new: 'Төлбөр хүлээж байна', requires_payment_method: 'QPay төлбөр хүлээж байна',
      requires_action: 'QPay төлбөр хүлээж байна', processing: 'Төлбөрийг шалгаж байна', requires_capture: 'Төлбөр баталгаажаагүй',
      succeeded: value.mode === 'test' ? 'Туршилтын төлбөр амжилттай. Бодит Plus эрх үүсэхгүй.' : 'Төлбөр баталгаажлаа', canceled: 'Нэхэмжлэл цуцлагдсан', refunded: 'Төлбөр буцаагдсан. Энэ төлбөрийн эрх цуцлагдсан.' };
    $('payment-state').textContent = labels[value.state] || 'Төлбөр баталгаажаагүй';
    $('invoice').textContent = value.amount_mnt + ' ₮ · ' + value.duration_days + ' хоног' + (value.mode === 'test' ? ' · Туршилт' : '');
    const href = !terminal.has(value.state) && safeCheckout(value.checkout_url);
    $('wire-link').hidden = !href;
    if (href) $('wire-link').href = href; else $('wire-link').removeAttribute('href');
    if (terminal.has(value.state)) { pending = null; save(); stopPolling(); }
    controls();
  }
  async function checkPayment() {
    if (!pending || !pending.order_id) return;
    try {
      const data = await api('/v1/billing/web/status', { order_id: pending.order_id });
      showOrder(data.order); showEntitlement(data.billing);
    } catch (error) {
      if (error && error.code === 'order_not_found') { pending = null; order = null; save(); $('payment').hidden = true; stopPolling(); }
      throw error;
    }
  }
  $('request-code').addEventListener('submit', (event) => { event.preventDefault(); action(async () => {
    email = $('email').value.trim().toLowerCase();
    await api('/v1/auth/request-code', { email }, false);
    $('verify-form').hidden = false; $('code').focus(); message('Имэйлээр ирсэн 6 оронтой кодоо оруулна уу.');
  }); });
  $('verify-form').addEventListener('submit', (event) => { event.preventDefault(); action(async () => {
    const data = await api('/v1/auth/verify-code', { email, code: $('code').value.trim() }, false);
    if (typeof data.token !== 'string' || data.token.length < 16) throw { code: 'unavailable' };
    token = data.token; $('code').value = ''; $('login').hidden = true; $('signed-in').hidden = false;
    $('account').textContent = data.user && data.user.email || email;
    showEntitlement(await api('/v1/billing/status')); message('Нэвтэрлээ. Төлбөр төлөхөөсөө өмнө сонголтоо шалгана уу.');
    if (pending && pending.order_id) { pollingStarted = Date.now(); await checkPayment(); schedule(); }
  }); });
  $('sign-out').addEventListener('click', () => action(async () => {
    try { await api('/v1/auth/sign-out', {}); } finally {
      token = null; email = ''; order = null; stopPolling(); $('login').hidden = false; $('signed-in').hidden = true;
      $('verify-form').hidden = true; $('payment').hidden = true; $('email').value = ''; $('account').textContent = ''; $('entitlement').textContent = ''; message('Гарлаа.');
    }
  }));
  $('buy').addEventListener('click', () => action(async () => {
    if (!legalReady || !catalog || !catalog.web || catalog.web.ready !== true) throw { code: 'billing_unavailable' };
    const plan = document.querySelector('input[name=plan]:checked').value;
    if (!pending || pending.plan !== plan) pending = { order_id: null, command_id: crypto.randomUUID(), plan };
    save();
    const data = await api('/v1/billing/web/checkout', { plan, command_id: pending.command_id });
    pending.order_id = data.order.order_id; save(); pollingStarted = Date.now(); showOrder(data.order);
    showEntitlement(await api('/v1/billing/status')); message('QPay хуудсыг нээгээд төлбөрөө хийнэ үү. Дараа нь энд төлөвөө шалгана.'); schedule();
  }));
  $('check-payment').addEventListener('click', () => action(checkPayment));
  restore(); controls();
  action(async () => {
    catalog = await api('/v1/billing/catalog', undefined, false);
    if (!legalReady || !catalog.web || catalog.web.ready !== true) message('Вэб төлбөр одоогоор идэвхгүй байна. Нэвтэрч одоогийн эрхээ шалгаж болно.');
  });
})();`;

function footer(env: PageEnvironment) {
  const ready = billingLegalReady(env);
  const identity = ready ? `<p>Үйлчилгээ үзүүлэгч: ${escape(env.LEGAL_OPERATOR_NAME!.trim())}<br>Холбоо барих: <a href="mailto:${escape(env.LEGAL_SUPPORT_EMAIL!.trim())}">${escape(env.LEGAL_SUPPORT_EMAIL!.trim())}</a></p>`
    : '<p>Үйлчилгээ үзүүлэгчийн нэр, холбоо барих хаяг баталгаажаагүй. Энэ баримт бичиг нь төсөл бөгөөд төлбөр хүлээн авахгүй.</p>';
  return `<footer>${identity}<p><a href="/terms">Үйлчилгээний нөхцөл</a> · <a href="/privacy">Нууцлал</a></p></footer>`;
}
function documentPage(env: PageEnvironment, title: string, content: string, plans = false) {
  const ready = billingLegalReady(env);
  return `<!doctype html><html lang="mn"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="referrer" content="no-referrer"><title>${escape(title)} · Хамтдаа</title><link rel="stylesheet" href="/billing-assets/pages.css">${plans ? '<script src="/billing-assets/plans.js" defer></script>' : ''}</head><body data-legal-ready="${ready}"><main><header><span class="brand">Хамтдаа</span><nav aria-label="Баримт бичиг"><a href="/privacy">Нууцлал</a><a href="/terms">Нөхцөл</a></nav></header>${!ready ? '<p class="notice"><strong>Төсөл · Төлбөр идэвхгүй.</strong> Үйлчилгээ үзүүлэгчийн мэдээлэл бүрэн баталгаажаагүй байна.</p>' : ''}${content}${footer(env)}</main></body></html>`;
}
const plans = `<p class="eyebrow">Хамтдаа Plus</p><h1>Нэг эрх.<br>Хоёуланд нь.</h1><p>Нэг хүн Plus авснаар одоо холбогдсон хос нь хамт ашиглана. Холбоосоо салгавал хосын хуваалцсан эрх дуусна; худалдан авагчийн өөрийн эрх хэвээр үлдэнэ.</p><p class="muted">Нэвтрэлт, хосын холбоос, үндсэн хуанли, дурсамж, бэлэг үнэгүй. Plus нь тусгай хосын картын боломж нээнэ.</p><section class="card"><fieldset><legend>Хугацаагаа сонгох</legend><div class="plans"><label class="plan"><input type="radio" name="plan" value="monthly" checked>30 хоног<strong class="price">9,900 ₮</strong><small>Нэг удаагийн төлбөр</small></label><label class="plan"><input type="radio" name="plan" value="yearly">365 хоног<strong class="price">79,900 ₮</strong><small>Нэг удаагийн төлбөр</small></label></div></fieldset><p><strong>Автоматаар сунгахгүй.</strong> Энэ вэбийн QPay эрх нь 30 эсвэл 365 хоногийн урьдчилсан төлбөр. Данснаас дахин автоматаар мөнгө суутгахгүй.</p><p class="muted">Хүчинтэй QPay эрхтэй үед шинээр төлбөл үлдсэн хугацааны дараа нэмэгдэнэ. Apple, Google-ийн захиалга тусдаа бөгөөд тухайн дэлгүүрээс удирдана.</p></section><section id="login" class="card"><h2>Аппдаа ашигладаг бүртгэлээр нэвтрэх</h2><p class="muted">Эрхийг таны нэвтэрсэн бүртгэлд холбоно. Энэ хуудас нэвтрэх түлхүүрийг зөвхөн нээлттэй байх хугацаанд санана.</p><form id="request-code"><label class="field" for="email">Имэйл</label><input id="email" type="email" maxlength="254" autocomplete="email" required><button id="send-code" type="submit">Код авах</button></form><form id="verify-form" hidden><label class="field" for="code">6 оронтой код</label><input id="code" type="text" inputmode="numeric" autocomplete="one-time-code" pattern="[0-9]{6}" maxlength="6" required><button id="verify-code" type="submit">Нэвтрэх</button></form></section><section id="signed-in" class="card" hidden><h2>Таны бүртгэл</h2><p id="account"></p><p id="entitlement" aria-live="polite"></p><button id="sign-out" type="button" class="secondary" hidden>Гарах</button></section><p id="message" role="status" aria-live="polite"></p><button id="buy" type="button" disabled>QPay нэхэмжлэл үүсгэх</button><p class="muted">Төлөхөөс өмнө <a href="/terms">үйлчилгээний нөхцөл</a>, <a href="/privacy">нууцлалын мэдээлэл</a>тэй танилцана уу. Банкны мэдээллээ зөвхөн Wire болон өөрийн банкны хуудсанд оруулна.</p><section id="payment" class="card" hidden><h2>Төлбөрийн төлөв</h2><p id="invoice"></p><p id="payment-state" aria-live="polite"></p><a id="wire-link" class="button" target="_blank" rel="noopener noreferrer" hidden>Wire дээр QPay нээх</a><button id="check-payment" class="secondary" type="button" disabled>Төлөв шалгах</button><p class="muted">Буцаж ирсэн холбоосоор эрх олгохгүй. Төлбөрийг серверээр баталгаажуулсны дараа Plus идэвхжинэ. Хуудсыг дахин нээвэл бүртгэлээрээ дахин нэвтэрнэ.</p></section>`;
const terms = `<h1>Үйлчилгээний нөхцөл</h1><p>Хамтдаа нь хоёр хүний сайн дурын холбоос болон хамтын хэрэглээнд зориулсан үйлчилгээ. Бүртгэлдээ зөв имэйл ашиглаж, нэвтрэх кодоо бусдад дамжуулахгүй байна.</p><h2>Үнэгүй боломж ба Plus</h2><p>Нэвтрэлт, хосын холбоос, үндсэн хуанли, дурсамж, үндсэн бэлэг үнэгүй. Plus нь тусгай хосын картын боломжийг нээнэ. Нэг худалдан авагчийн хүчинтэй эрхийг зөвхөн тухайн мөчид идэвхтэй холбогдсон хос нь хуваалцана. Холбоос салвал хосын хуваалцсан боломж шууд дуусна.</p><h2>Төлбөр ба хугацаа</h2><p>Вэбийн QPay төлбөр: 30 хоног 9,900 ₮; 365 хоног 79,900 ₮. Энэ нь тогтмол хугацаатай урьдчилсан төлбөр бөгөөд автоматаар сунгахгүй, дахин суутгал хийхгүй. Сервер төлбөрийг анх баталгаажуулснаар хугацаа эхэлнэ. Идэвхтэй QPay хугацаа байгаа бол шинэ төлбөрийн хугацаа түүний араас нэмэгдэнэ. Apple, Google-ийн захиалга болон QPay төлбөр тусдаа; давхар идэвхжүүлсэн эрхийн хугацааг хооронд нь нийлүүлэхгүй.</p><p>Апп доторх Apple болон Google худалдан авалт нь тухайн дэлгүүрийн автоматаар сунгагддаг захиалга. Эцсийн үнэ, валют, хугацаа, сунгалтын мэдээллийг дэлгүүрийн баталгаажуулах дэлгэцээс шалгана. Захиалгаа тухайн дэлгүүрийн тохиргоонд удирдаж, цуцална. Сунгалтыг цуцлах нь төлсөн хугацааны эрхийг шууд устгахгүй.</p><h2>Төлбөрийн асуудал, буцаалт</h2><p>QPay төлбөртэй холбоотой хүсэлтийг доорх баталгаажсан холбоо барих хаягт нэхэмжлэлийн дугаартай илгээнэ. Apple, Google худалдан авалтын буцаалтыг тухайн дэлгүүрээр хүснэ. Баталгаажсан буцаалт, хүчингүй болсон төлбөрийн Plus эрх цуцлагдана. Нууц үг, нэвтрэх код, банкны баталгаажуулах кодоо тусламжийн хүсэлтэд оруулахгүй.</p><h2>Эрхийн баталгаажуулалт</h2><p>Төлбөрийг зөвхөн сервер болон төлбөрийн үйлчилгээний баталгаажсан мэдээллээр шалгана. Аппын захиалгын төлөв шинэчлэгдэхгүй удах эсвэл төлбөрийн үйлчилгээ түр тасалдах үед Plus боломж түр хаагдаж болно. Үнэгүй боломжууд энэ төлбөрийн шалгалтаар хязгаарлагдахгүй.</p><h2>Бүртгэл ба хосын аюулгүй байдал</h2><p>Хосын холбоос үүсгэхэд хоёр талын зөвшөөрөл шаардлагатай. Та холбоосоо салгаж болно. Бусдын бүртгэл, төлбөрийн баримт ашиглан эрх авах, үйлчилгээний аюулгүй байдлыг зөрчихийг зөвшөөрөхгүй.</p>`;
const privacy = `<h1>Нууцлалын мэдээлэл</h1><p>Энэ мэдээлэл нь Хамтдаагийн бүртгэл, хосын холбоос болон Plus эрхийн үйлчилгээнд хамаарна.</p><h2>Ямар мэдээлэл ашиглах вэ</h2><ul><li>Нэвтрэх, код илгээх, бүртгэлийг танихад имэйл хаяг, баталгаажсан эсэх, сессийн аюулгүй байдлын мэдээлэл ашиглана.</li><li>Хосын холбоосод профайлын нэр, урилгын төлөв, идэвхтэй холбоос, салгасан эсэх болон блоклох мэдээлэл ашиглана.</li><li>Plus эрхэд худалдан авагчийн бүртгэлийн дугаар, төлбөрийн үйлчилгээ, бүтээгдэхүүн, нэхэмжлэл эсвэл гүйлгээний дугаар, дүн, хугацаа, төлөв хадгална.</li><li>Apple, Google захиалгыг сэргээж шалгахад шаардлагатай лавлагааг серверт шифрлэж хадгална. Энэ мэдээллийг хосод нь харуулахгүй.</li></ul><h2>Мэдээллийг хэрхэн ашиглах вэ</h2><p>Мэдээллийг нэвтрүүлэх, хоёр талын зөвшөөрлийг шалгах, төлбөрийг баталгаажуулах, Plus эрхийг одоогийн хостой хуваалцах, давхардсан болон бусдын төлбөрийн баримтаар эрх авахыг зогсооход ашиглана. Бүртгэлийн таних дугаарыг дэлгүүрийн худалдан авалттай холбохдоо тусдаа тогтвортой танигч хэрэглэнэ.</p><h2>Үйлчилгээний оролцогчид</h2><p>Cloudflare нь нэвтрэлт, серверийн ажиллагаа, өгөгдлийн сан болон нэвтрэх имэйл хүргэлтэд оролцоно. Вэбийн төлбөрийг Wire.mn, QPay болон таны сонгосон банк боловсруулна. Аппын худалдан авалтыг Apple эсвэл Google боловсруулна. Тэдгээр үйлчилгээ өөрийн нөхцөл, нууцлалын мэдээлэлтэй.</p><p>Энэ вэб хуудас банкны картын дугаар, банкны нууц үг эсвэл банкны баталгаажуулах код цуглуулахгүй. Ийм мэдээллийг зөвхөн төлбөрийн үйлчилгээ, банкны албан ёсны дэлгэцэд оруулна.</p><h2>Хосод харагдах мэдээлэл</h2><p>Холбогдсон хос Plus эрхийг хуваалцаж байгаа эсэх, үйлчилгээний төрөл болон дуусах хугацааг харж болно. Банкны мэдээлэл, дэлгүүрийн төлбөрийн нууц лавлагаа түүнд харагдахгүй. Холбоос салмагц хуваалцсан Plus эрх дуусна.</p><h2>Энэ вэбийн хадгалалт</h2><p>Нэвтрэх түлхүүрийг зөвхөн хуудасны санах ойд ашиглаж, хаяг, холбоос эсвэл хөтчийн байнгын хадгалалтад бичихгүй. Тасалдсан төлбөрийг сэргээхэд нэхэмжлэл болон хүсэлтийн дугаар, сонгосон хугацааг тухайн хөтчийн табын session storage-д түр хадгалж болно. Дахин нээхэд нэвтэрч, нэхэмжлэлийн эзэмшлийг серверээр шалгуулна.</p><h2>Хадгалах хугацаа ба хүсэлт</h2><p>Бүртгэл, төлбөрийн ажиллагаа, аюулгүй байдал, маргаан шийдвэрлэхэд шаардлагатай мэдээллийг хадгална. Мэдээлэл авах, засах, устгах тухай хүсэлтээ доорх баталгаажсан холбоо барих хаягаар гаргана. Төлбөрийн бүртгэлийг устгах боломж нь тухайн төлбөр болон үйлчилгээ үзүүлэгчийн хамаарах шаардлагаас шалтгаална.</p>`;

/** Read-only pages and local assets; no auth/session is created by rendering. */
export function handleBillingPage(request: Request, env: PageEnvironment): Response | null {
  const path = new URL(request.url).pathname;
  if (!['/plans', '/terms', '/privacy', '/billing-assets/plans.js', '/billing-assets/pages.css'].includes(path)) return null;
  const headers = new Headers({
    'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer', 'X-Content-Type-Options': 'nosniff',
    'X-Frame-Options': 'DENY', 'Permissions-Policy': 'camera=(), microphone=(), geolocation=(), payment=()',
    'Content-Security-Policy': "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'none'; font-src 'none'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'; object-src 'none'",
  });
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    headers.set('Allow', 'GET, HEAD');
    return new Response(null, { status: 405, headers });
  }
  let content: string;
  if (path.endsWith('.js')) { headers.set('Content-Type', 'text/javascript; charset=utf-8'); content = script; }
  else if (path.endsWith('.css')) { headers.set('Content-Type', 'text/css; charset=utf-8'); content = css; }
  else {
    headers.set('Content-Type', 'text/html; charset=utf-8');
    content = documentPage(env, path === '/plans' ? 'Plus' : path === '/terms' ? 'Үйлчилгээний нөхцөл' : 'Нууцлал', path === '/plans' ? plans : path === '/terms' ? terms : privacy, path === '/plans');
  }
  return new Response(request.method === 'HEAD' ? null : content, { headers });
}
