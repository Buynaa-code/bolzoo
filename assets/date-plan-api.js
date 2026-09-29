(function (root) {
  'use strict';
  var prefix = 'bolzoo:date-plan:';
  var requests = Object.create(null);
  function read(key) {
    try { var value = root.localStorage.getItem(prefix + key); return value ? JSON.parse(value) : null; }
    catch (_) { throw new Error('Энэ browser хадгалах боломжгүй байна. Ердийн browser дээр нээгээд дахин оролдоорой.'); }
  }
  function write(key, value) {
    try { root.localStorage.setItem(prefix + key, JSON.stringify(value)); }
    catch (_) { throw new Error('Нэвтрэх эрхийг энэ browser дээр хадгалж чадсангүй. Ердийн browser дээр дахин нээгээрэй.'); }
  }
  function remove(key) { try { root.localStorage.removeItem(prefix + key); } catch (_) {} }
  function secret() {
    var bytes = new Uint8Array(32);
    if (!root.crypto || !root.crypto.getRandomValues) throw new Error('Аюулгүй холболтоор хуудсыг дахин нээгээрэй.');
    root.crypto.getRandomValues(bytes);
    return Array.from(bytes, function (n) { return n.toString(16).padStart(2, '0'); }).join('');
  }
  function uuid() {
    if (root.crypto && root.crypto.randomUUID) return root.crypto.randomUUID();
    var s = secret();
    return s.slice(0,8)+'-'+s.slice(8,12)+'-4'+s.slice(13,16)+'-'+((parseInt(s[16],16)&3)|8).toString(16)+s.slice(17,20)+'-'+s.slice(20,32);
  }
  function ownerToken(invite) { return root.BolzooAPI && root.BolzooAPI.getOwnerToken(invite); }
  function auth(invite) { return ownerToken(invite) || read('participant:' + invite); }
  function hasOwner(invite) { return !!ownerToken(invite); }
  function captureJoin(invite) {
    var fragment = root.location.hash;
    // Remove all fragments before storage or a network request can fail.
    if (fragment) root.history.replaceState(null, '', root.location.pathname + root.location.search);
    var incoming = new URLSearchParams(fragment.replace(/^#/, '')).get('join');
    if (incoming && invite) {
      if (!/^[A-Za-z0-9_-]{43,128}$/.test(incoming)) throw new Error('Оролцох холбоос дутуу байна. Илгээгчээс шинэ холбоос аваарай.');
      var completed = read('completed-join:' + invite);
      if (completed && completed.claim_token === incoming && read('participant:' + invite)) return false;
      var existing = read('join:' + invite);
      if (!existing || existing.claim_token !== incoming) write('join:' + invite, {claim_token:incoming, participant_token:secret(),request_id:uuid()});
    }
    return invite ? !!read('join:' + invite) : false;
  }
  async function request(invite, body, token) {
    var options = {method:body ? 'POST' : 'GET',cache:'no-store',credentials:'same-origin',referrerPolicy:'no-referrer',headers:{'Accept':'application/json'}};
    var controller = typeof root.AbortController === 'function' ? new root.AbortController() : null;
    var timeout = controller ? root.setTimeout(function () { controller.abort(); }, 20000) : null;
    if (controller) options.signal = controller.signal;
    if (token) options.headers.Authorization = 'Bearer ' + token;
    if (body) { options.headers['Content-Type'] = 'application/json'; options.body = JSON.stringify(body); }
    var response;
    try { response = await root.fetch('/api/date-plan' + (body ? '' : '?invite_id=' + encodeURIComponent(invite)), options); }
    catch (_) { if (timeout) root.clearTimeout(timeout); var network = new Error('Холболт тасарлаа. Бичсэн зүйл тань хэвээрээ. Дахин оролдоорой.'); network.code = 'network'; throw network; }
    var data;
    try { data = await response.json(); }
    catch (_) { if (timeout) root.clearTimeout(timeout); var invalid = new Error('Серверийн хариуг уншиж чадсангүй. Дахин оролдоорой.'); invalid.status = response.status; throw invalid; }
    if (timeout) root.clearTimeout(timeout);
    if (!response.ok) {
      var error = new Error(data.user_error || 'Хадгалж чадсангүй. Дахин оролдоорой.');
      error.code = data.code || data.error; error.status = response.status; throw error;
    }
    return data;
  }
  function claimToken(invite) {
    var saved = read('claim:' + invite);
    if (!saved) { saved = secret(); write('claim:' + invite, saved); }
    return saved;
  }
  async function mutate(invite, action, fields) {
    var payload = Object.assign({}, fields || {}, {action:action,invite_id:invite});
    if (action === 'create') payload.claim_token = claimToken(invite);
    var rotation;
    if (action === 'rotate_claim') {
      rotation = read('rotation:' + invite);
      if (!rotation || rotation.expected_version !== payload.expected_version) {
        rotation = {claim_token:secret(),request_id:uuid(),expected_version:payload.expected_version};
        write('rotation:' + invite, rotation);
      }
      payload.claim_token = rotation.claim_token;
    }
    var signature = JSON.stringify(payload);
    var key = invite + ':' + action;
    var previous = requests[key];
    if (!previous || previous.signature !== signature) requests[key] = {signature:signature,request_id:uuid()};
    payload.request_id = rotation ? rotation.request_id : requests[key].request_id;
    try {
      var result = await request(invite, payload, auth(invite));
      if (rotation) { write('claim:' + invite, rotation.claim_token); remove('rotation:' + invite); }
      delete requests[key]; return result;
    } catch (error) {
      if (error.status >= 400 && error.status < 500) delete requests[key];
      throw error;
    }
  }
  async function claim(invite) {
    var pending = read('join:' + invite);
    if (!pending) throw new Error('Илгээгчээс энэ болзоонд оролцох холбоос аваарай.');
    var result = await request(invite, Object.assign({action:'claim',invite_id:invite}, pending));
    // Persist the credential before clearing the retryable claim.
    write('participant:' + invite, pending.participant_token);
    var index = read('joined') || [];
    if (!index.some(function (p) { return p.invite_id === invite; })) index.unshift({id:result.id,invite_id:invite});
    write('joined', index);
    write('completed-join:' + invite, {claim_token:pending.claim_token});
    remove('join:' + invite);
    return result;
  }
  function joinLink(invite) {
    if (read('rotation:' + invite)) return null;
    var token = read('claim:' + invite);
    if (!token) return null;
    return root.location.origin + '/date-plan.html?invite=' + encodeURIComponent(invite) + '#join=' + encodeURIComponent(token);
  }
  root.BolzooDatePlanAPI = Object.freeze({
    get:function (invite) { return request(invite, null, auth(invite)); },
    mutate:mutate,claim:claim,captureJoin:captureJoin,hasOwner:hasOwner,
    hasAuth:function(invite){return !!auth(invite);},hasPendingJoin:function(invite){return !!read('join:'+invite);},
    joinLink:joinLink,listJoined:function(){return read('joined') || [];}
  });
}(window));
