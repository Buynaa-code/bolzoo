/**
 * Bolzoo API client.
 * Ажиллах горим:
 *  - Supabase config-той бол шууд PostgREST руу fetch хийнэ
 *  - Хоосон бол localStorage-д хадгалж, ижил API-тай ажиллана (offline demo)
 *
 * localStorage key-үүд:
 *   bolzoo:invites:{id} = { config, response, opened_at, responded_at, created_at }
 *   bolzoo:owner:{id}   = ownerToken  (тухайн төхөөрөмж дээрх зохиогч л мэднэ)
 *   bolzoo:my           = [{id, createdAt}]  (dashboard-д харах жагсаалт)
 */
(function(){
  var C = window.BOLZOO_CONFIG || {};
  var IS_FILE = (typeof location !== 'undefined') && location.protocol === 'file:';
  var HAS_SUPABASE = !!(C.supabaseUrl && C.supabaseAnonKey);
  var HAS_CUSTOM_API = !!C.apiUrl;
  // If served over HTTP(S) with no explicit config, assume same-origin dev server (server.js)
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

  /* ------------ REST calls ------------ */
  function req(method, path, body, extraHeaders){
    var h = {}; for(var k in HDR){ h[k]=HDR[k]; }
    if(extraHeaders){ for(var k2 in extraHeaders){ h[k2]=extraHeaders[k2]; } }
    return fetch(API+path, { method:method, headers:h, body:body?JSON.stringify(body):undefined })
      .then(function(r){
        if(!r.ok){ return r.text().then(function(t){ throw new Error('HTTP '+r.status+': '+t); }); }
        var ct=r.headers.get('content-type')||'';
        if(ct.indexOf('application/json')!==-1) return r.json();
        return null;
      });
  }

  /* ------------ Public API ------------ */
  async function createInvite(config){
    var id = shortId(10);
    var record = { id:id, config:config };
    var createdAt = new Date().toISOString();

    if(HAS_BACKEND){
      var rows = await req('POST', '/invites?select=id,owner_token,created_at', record, {'Prefer':'return=representation'});
      var row = rows && rows[0];
      if(!row) throw new Error('Insert returned no row');
      setOwnerToken(row.id, row.owner_token);
      rememberMine(row.id);
      return { id: row.id, ownerToken: row.owner_token, createdAt: row.created_at };
    } else {
      var token = uuid4();
      lsSet('bolzoo:invites:'+id, { config:config, response:null, opened_at:null, responded_at:null, created_at:createdAt });
      setOwnerToken(id, token);
      rememberMine(id);
      return { id:id, ownerToken:token, createdAt:createdAt };
    }
  }

  async function getInvite(id){
    if(!id) return null;
    if(HAS_BACKEND){
      var rows = await req('GET', '/invites?id=eq.'+encodeURIComponent(id)+'&select=id,config,response,opened_at,responded_at,created_at');
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
      // Only stamp if empty (best-effort — race is OK)
      try{
        await req('PATCH', '/invites?id=eq.'+encodeURIComponent(id)+'&opened_at=is.null',
                  { opened_at: new Date().toISOString() });
      }catch(e){}
    } else {
      var s = lsGet('bolzoo:invites:'+id);
      if(s && !s.opened_at){ s.opened_at = new Date().toISOString(); lsSet('bolzoo:invites:'+id, s); }
    }
  }

  async function saveResponse(id, response){
    if(!id) return;
    var patch = { response: response, responded_at: new Date().toISOString() };
    if(HAS_BACKEND){
      await req('PATCH', '/invites?id=eq.'+encodeURIComponent(id), patch);
    } else {
      var s = lsGet('bolzoo:invites:'+id) || { config:null, response:null, opened_at:null };
      s.response = response;
      s.responded_at = patch.responded_at;
      lsSet('bolzoo:invites:'+id, s);
    }
  }

  async function listMyInvites(){
    var mine = listMine();
    if(!mine.length) return [];
    if(HAS_BACKEND){
      var ids = mine.map(function(x){ return x.id; });
      var q = 'id=in.('+ids.map(encodeURIComponent).join(',')+')&order=created_at.desc';
      var rows = await req('GET', '/invites?'+q+'&select=id,config,response,opened_at,responded_at,created_at');
      return rows || [];
    } else {
      return mine.map(function(x){
        var s = lsGet('bolzoo:invites:'+x.id);
        if(!s) return null;
        return { id:x.id, config:s.config, response:s.response, opened_at:s.opened_at, responded_at:s.responded_at, created_at:s.created_at };
      }).filter(Boolean);
    }
  }

  async function deleteInvite(id){
    if(HAS_BACKEND){
      // Only allow delete if owner_token matches
      var token = getOwnerToken(id);
      if(!token) throw new Error('No owner token for this invite on this device');
      await req('DELETE', '/invites?id=eq.'+encodeURIComponent(id)+'&owner_token=eq.'+encodeURIComponent(token));
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
    listMyInvites: listMyInvites,
    deleteInvite: deleteInvite,
    getOwnerToken: getOwnerToken,
    _shortId: shortId
  };
})();
