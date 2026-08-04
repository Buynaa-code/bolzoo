/**
 * Bolzoo API client.
 * Ажиллах горим:
 *  - Supabase config-той бол шууд PostgREST руу fetch хийнэ
 *  - Хоосон бол localStorage-д хадгалж, ижил API-тай ажиллана (offline demo)
 *
 * localStorage key-үүд:
 *   bolzoo:invites:{id}        = { config, response, opened_at, responded_at, created_at }
 *   bolzoo:owner:{id}          = ownerToken  (тухайн төхөөрөмж дээрх зохиогч л мэднэ)
 *   bolzoo:my                  = [{id, createdAt}]  (dashboard-д харах жагсаалт)
 *   bolzoo:codes               = { code: { used, used_at, used_for_invite_id, note, created_at } }
 *   bolzoo:admin_pw            = admin password (session-only)
 */
(function(){
  var C = window.BOLZOO_CONFIG || {};
  var IS_FILE = (typeof location !== 'undefined') && location.protocol === 'file:';
  var HAS_SUPABASE = !!(C.supabaseUrl && C.supabaseAnonKey);
  var HAS_CUSTOM_API = !!C.apiUrl;
  var HAS_SAME_ORIGIN = !HAS_SUPABASE && !HAS_CUSTOM_API && !IS_FILE;
  var HAS_BACKEND = HAS_SUPABASE || HAS_CUSTOM_API || HAS_SAME_ORIGIN;
  var BACKEND_KIND = HAS_SUPABASE ? 'supabase' : HAS_CUSTOM_API ? 'custom' : HAS_SAME_ORIGIN ? 'same-origin' : 'localStorage';
  var API =
    HAS_SUPABASE   ? (C.supabaseUrl.replace(/\/$/, '') + '/rest/v1') :
    HAS_CUSTOM_API ? (C.apiUrl.replace(/\/$/, '') + '/rest/v1') :
    HAS_SAME_ORIGIN ? '/rest/v1' :
    null;
  var HDR = { 'Content-Type': 'application/json' };
  if (HAS_SUPABASE) {
    HDR['apikey'] = C.supabaseAnonKey;
    HDR['Authorization'] = 'Bearer ' + C.supabaseAnonKey;
  }

  function shortId(len){
    var abc='abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    var out=''; var arr=new Uint8Array(len||10);
    (window.crypto||window.msCrypto).getRandomValues(arr);
    for(var i=0;i<arr.length;i++){ out += abc.charAt(arr[i] % abc.length); }
    return out;
  }
  function uuid4(){
    if(window.crypto && crypto.randomUUID) return crypto.randomUUID();
    var b=new Uint8Array(16); crypto.getRandomValues(b);
    b[6]=(b[6]&0x0f)|0x40; b[8]=(b[8]&0x3f)|0x80;
    var h=[];for(var i=0;i<b.length;i++){h.push(('0'+b[i].toString(16)).slice(-2));}
    return h[0]+h[1]+h[2]+h[3]+'-'+h[4]+h[5]+'-'+h[6]+h[7]+'-'+h[8]+h[9]+'-'+h[10]+h[11]+h[12]+h[13]+h[14]+h[15];
  }
  function genLocalCode(){
    var chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    var out = 'LOV-'; var arr = new Uint8Array(6);
    (window.crypto||window.msCrypto).getRandomValues(arr);
    for(var i=0;i<arr.length;i++){ out += chars.charAt(arr[i] % chars.length); }
    return out;
  }

  /* ------------ local storage layer (fallback) ------------ */
  function lsGet(k){ try{ return JSON.parse(localStorage.getItem(k)); }catch(e){ return null; } }
  function lsSet(k,v){ try{ localStorage.setItem(k, JSON.stringify(v)); }catch(e){} }
  function lsDel(k){ try{ localStorage.removeItem(k); }catch(e){} }

  function rememberMine(id){
    var mine = lsGet('bolzoo:my') || [];
    if(!mine.some(function(x){ return x.id===id; })){
      mine.unshift({id:id, createdAt:new Date().toISOString()});
      lsSet('bolzoo:my', mine);
    }
  }
  function forgetMine(id){
    var mine = lsGet('bolzoo:my') || [];
    lsSet('bolzoo:my', mine.filter(function(x){ return x.id!==id; }));
    lsDel('bolzoo:owner:'+id);
  }
  function setOwnerToken(id, token){ lsSet('bolzoo:owner:'+id, token); }
  function getOwnerToken(id){ return lsGet('bolzoo:owner:'+id); }
  function listMine(){ return lsGet('bolzoo:my') || []; }

  function lsCodes(){ return lsGet('bolzoo:codes') || {}; }
  function lsSaveCodes(obj){ lsSet('bolzoo:codes', obj); }
  var LOCAL_ADMIN_PW = 'admin123';

  /* ------------ REST calls ------------ */
  function req(method, path, body, extraHeaders){
    var h = {}; for(var k in HDR){ h[k]=HDR[k]; }
    if(extraHeaders){ for(var k2 in extraHeaders){ h[k2]=extraHeaders[k2]; } }
    return fetch(API+path, { method:method, headers:h, body:body?JSON.stringify(body):undefined })
      .then(function(r){
        if(!r.ok){
          return r.text().then(function(t){
            var msg = t;
            try { var j = JSON.parse(t); if(j && j.message) msg = j.message; } catch(_){}
            throw new Error(msg || ('HTTP '+r.status));
          });
        }
        var ct=r.headers.get('content-type')||'';
        if(ct.indexOf('application/json')!==-1) return r.json();
        return null;
      });
  }
  function rpc(name, params){
    return req('POST', '/rpc/'+name, params || {});
  }

  /* ------------ Access codes ------------ */
  // Кодыг RPC-ээр шалгана. Хүснэгтийг шууд уншвал зарагдаагүй бүх кодыг
  // татаж авах боломжтой болох тул тэр зам хаалттай (sql/schema.sql).
  async function validateCode(code){
    if(!code) return { ok:false, reason:'empty' };
    if(HAS_BACKEND){
      try{
        var rows = await rpc('check_access_code', { p_code: code });
        var r = rows && rows[0];
        if(!r) return { ok:false, reason:'error' };
        return r.ok ? { ok:true } : { ok:false, reason:r.reason || 'not_found' };
      }catch(e){ return { ok:false, reason:'error', error:e.message }; }
    } else {
      var c = lsCodes()[code];
      if(!c) return { ok:false, reason:'not_found' };
      if(c.used) return { ok:false, reason:'used' };
      return { ok:true };
    }
  }

  async function adminCreateCodes(pw, qty, note){
    if(HAS_BACKEND){
      var rows = await rpc('admin_create_codes', { admin_pw: pw, qty: Number(qty)||1, note_: note || null });
      return rows || [];
    } else {
      if(pw !== LOCAL_ADMIN_PW) throw new Error('Invalid admin password (local default: '+LOCAL_ADMIN_PW+')');
      var all = lsCodes();
      var created = [];
      for(var i=0;i<(Number(qty)||1);i++){
        var c; do { c = genLocalCode(); } while (all[c]);
        var row = { code:c, used:false, used_at:null, used_for_invite_id:null, note:note||null, created_at:new Date().toISOString() };
        all[c] = row;
        created.push(row);
      }
      lsSaveCodes(all);
      return created;
    }
  }

  async function adminListCodes(pw){
    if(HAS_BACKEND){
      return await rpc('admin_list_codes', { admin_pw: pw }) || [];
    } else {
      if(pw !== LOCAL_ADMIN_PW) throw new Error('Invalid admin password (local default: '+LOCAL_ADMIN_PW+')');
      return Object.values(lsCodes()).sort(function(a,b){ return (b.created_at||'').localeCompare(a.created_at||''); });
    }
  }

  async function adminDeleteCode(pw, code){
    if(HAS_BACKEND){
      await rpc('admin_delete_code', { admin_pw: pw, p_code: code });
    } else {
      if(pw !== LOCAL_ADMIN_PW) throw new Error('Invalid admin password');
      var all = lsCodes();
      if(!all[code]) throw new Error('Code not found');
      if(all[code].used) throw new Error('Cannot delete used code');
      delete all[code];
      lsSaveCodes(all);
    }
  }

  /* ------------ Public API ------------ */
  async function createInvite(config, accessCode){
    if(!accessCode) throw new Error('Access code required');
    var id = shortId(10);

    if(HAS_BACKEND){
      var rows = await rpc('create_invite_with_code', {
        p_invite_id: id,
        p_config: config,
        p_access_code: accessCode
      });
      var row = rows && rows[0];
      if(!row) throw new Error('RPC returned no row');
      setOwnerToken(row.id, row.owner_token);
      rememberMine(row.id);
      return { id: row.id, ownerToken: row.owner_token, createdAt: row.created_at };
    } else {
      var all = lsCodes();
      var c = all[accessCode];
      if(!c) throw new Error('Invalid access code');
      if(c.used) throw new Error('Access code already used');
      var token = uuid4();
      var createdAt = new Date().toISOString();
      lsSet('bolzoo:invites:'+id, { config:config, response:null, opened_at:null, responded_at:null, created_at:createdAt });
      setOwnerToken(id, token);
      rememberMine(id);
      c.used = true;
      c.used_at = createdAt;
      c.used_for_invite_id = id;
      lsSaveCodes(all);
      return { id:id, ownerToken:token, createdAt:createdAt };
    }
  }

  async function getInvite(id){
    if(!id) return null;
    if(HAS_BACKEND){
      var rows = await rpc('get_invites', { p_ids: [id] });
      return rows && rows[0] ? rows[0] : null;
    } else {
      var stored = lsGet('bolzoo:invites:'+id);
      if(!stored) return null;
      return { id:id, config:stored.config, response:stored.response, opened_at:stored.opened_at, responded_at:stored.responded_at, created_at:stored.created_at };
    }
  }

  async function markOpened(id){
    if(!id) return;
    if(HAS_BACKEND){
      try{ await rpc('mark_opened', { p_invite_id: id }); }catch(e){}
    } else {
      var s = lsGet('bolzoo:invites:'+id);
      if(s && !s.opened_at){ s.opened_at = new Date().toISOString(); lsSet('bolzoo:invites:'+id, s); }
    }
  }

  async function saveResponse(id, response){
    if(!id) return;
    if(HAS_BACKEND){
      await rpc('save_response', { p_invite_id: id, p_response: response });
    } else {
      var s = lsGet('bolzoo:invites:'+id) || { config:null, response:null, opened_at:null };
      s.response = response;
      s.responded_at = new Date().toISOString();
      lsSet('bolzoo:invites:'+id, s);
    }
  }

  /**
   * Хариу хадгалсны дараа илгээгч рүү имэйл явуулах webhook-ыг зэвүүлнэ.
   * Тохируулаагүй бол юу ч хийхгүй. Хариу нь аль хэдийн DB-д хадгалагдсан
   * тул имэйл амжилтгүй болсон ч мэдээлэл алдагдахгүй — тиймээс алдааг
   * хэрэглэгчид харуулахгүй, зөвхөн console-д бичнэ.
   */
  function notifyResponse(id){
    var url = C.emailWebhookUrl;
    if(!url || !id) return Promise.resolve(false);
    return fetch(url, {
      method: 'POST',
      mode: 'no-cors',                              // Apps Script CORS header буцаадаггүй
      headers: { 'Content-Type': 'text/plain;charset=utf-8' },
      body: JSON.stringify({ inviteId: id })
    }).then(function(){ return true; })
      .catch(function(e){ console.warn('Email webhook failed:', e); return false; });
  }

  /**
   * Одоо байгаа урилгыг энэ browser-ийн жагсаалтад буцааж нэмнэ.
   * (Утсаа сольсон / түүхээ цэвэрлэсэн хүн линкээрээ сэргээхэд.)
   * Зөвхөн харах эрх — устгахад хэрэгтэй owner_token сэргэхгүй.
   */
  async function trackInvite(idOrUrl){
    var raw = String(idOrUrl || '').trim();
    if(!raw) throw new Error('Линк эсвэл ID оруулна уу');
    // Линк дотроос ?id=xxx-г салгаж авна, эсвэл шууд ID гэж үзнэ
    var m = raw.match(/[?&]id=([^&#\s]+)/);
    var id = m ? decodeURIComponent(m[1]) : raw;
    var rec = await getInvite(id);
    if(!rec) throw new Error('Ийм урилга олдсонгүй');
    rememberMine(id);
    return rec;
  }

  async function listMyInvites(){
    var mine = listMine();
    if(!mine.length) return [];
    if(HAS_BACKEND){
      var rows = await rpc('get_invites', { p_ids: mine.map(function(x){ return x.id; }) });
      return rows || [];
    } else {
      return mine.map(function(x){
        var s = lsGet('bolzoo:invites:'+x.id);
        if(!s) return null;
        return { id:x.id, config:s.config, response:s.response, opened_at:s.opened_at, responded_at:s.responded_at, created_at:s.created_at };
      }).filter(Boolean);
    }
  }

  /**
   * Үүсгэсэн урилгаа засна (хариу ирэхээс өмнө).
   * owner_token нь зөвхөн үүсгэсэн төхөөрөмжид байдаг тул линкээр сэргээсэн
   * урилгыг засах боломжгүй — зөвхөн харна.
   */
  async function updateInvite(id, config){
    var token = getOwnerToken(id);
    if(!token) throw new Error('Энэ урилгыг зөвхөн үүсгэсэн төхөөрөмжөөс засна');
    if(HAS_BACKEND){
      await rpc('update_own_invite', { p_invite_id:id, p_owner_token:token, p_config:config });
    } else {
      var s = lsGet('bolzoo:invites:'+id);
      if(!s) throw new Error('Урилга олдсонгүй');
      if(s.responded_at) throw new Error('Хариу ирсэн тул засах боломжгүй');
      s.config = config;
      lsSet('bolzoo:invites:'+id, s);
    }
  }

  async function deleteInvite(id){
    if(HAS_BACKEND){
      var token = getOwnerToken(id);
      if(!token) throw new Error('No owner token for this invite on this device');
      await rpc('delete_own_invite', { p_invite_id: id, p_owner_token: token });
    } else {
      lsDel('bolzoo:invites:'+id);
    }
    forgetMine(id);
  }

  window.BolzooAPI = {
    hasBackend: HAS_BACKEND,
    backendKind: BACKEND_KIND,
    createInvite: createInvite,
    getInvite: getInvite,
    markOpened: markOpened,
    saveResponse: saveResponse,
    notifyResponse: notifyResponse,
    hasEmailWebhook: !!C.emailWebhookUrl,
    listMyInvites: listMyInvites,
    trackInvite: trackInvite,
    updateInvite: updateInvite,
    deleteInvite: deleteInvite,
    getOwnerToken: getOwnerToken,
    validateCode: validateCode,
    adminCreateCodes: adminCreateCodes,
    adminListCodes: adminListCodes,
    adminDeleteCode: adminDeleteCode,
    _shortId: shortId
  };
})();
