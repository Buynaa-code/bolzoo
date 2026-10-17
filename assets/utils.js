/**
 * Bolzoo — shared DOM / string helpers.
 * Хуудсанд аль болох <script src="assets/utils.js"></script>-ыг
 * assets/config.js болон assets/api.js-с ӨМНӨ ачаалж эхлээрэй.
 *
 * window.BolzooUtils:
 *   $(id)              → document.getElementById wrapper
 *   esc(str)           → HTML escape (XSS-с хамгаална)
 *   fmtWhen(iso)       → 'mn-MN' localе-той огноо формат ('' биш бол '—')
 *   backendLabel(kind) → {text, tone}  (create/dashboard/admin badge-д)
 */
(function(){
  function $(id){ return document.getElementById(id); }

  var ESC = {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'};
  function esc(s){
    return String(s == null ? '' : s).replace(/[&<>"']/g, function(c){ return ESC[c]; });
  }

  function fmtWhen(iso){
    if(!iso) return '—';
    try { return new Date(iso).toLocaleString('mn-MN'); }
    catch(_) { return String(iso); }
  }

  var BACKEND_LABELS = {
    'supabase':     { text:'✅ Supabase backend',                                          tone:'ok' },
    'custom':       { text:'✅ Custom API backend',                                        tone:'ok' },
    'same-origin':  { text:'✅ Локал сервер холбогдсон',                                   tone:'ok' },
    'localStorage': { text:'⚠️ Backend байхгүй — line зөвхөн энэ browser дээр ажиллана (node server.js эсвэл Supabase холбоно уу)', tone:'warn' }
  };
  function backendLabel(kind){
    return BACKEND_LABELS[kind] || { text:'', tone:'warn' };
  }

  window.BolzooUtils = { $:$, esc:esc, fmtWhen:fmtWhen, backendLabel:backendLabel };
})();
