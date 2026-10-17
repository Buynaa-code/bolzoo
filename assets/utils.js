/**
 * Bolzoo — shared DOM / string helpers.
 * Хуудсанд аль болох <script src="assets/utils.js"></script>-ыг
 * assets/config.js болон assets/api.js-с ӨМНӨ ачаалж эхлээрэй.
 *
 * window.BolzooUtils:
 *   $(id)              → document.getElementById wrapper
 *   esc(str)           → HTML escape (XSS-с хамгаална)
 *   fmtWhen(iso)       → "2026.08.12 18:04" (locale-с хамааралгүй)
 *   forgiveLevel(0-100)→ {face, label} — уучлалын хэмжүүрийн тайлбар
 *   backendLabel(kind) → {text, tone}  (create/dashboard/admin badge-д)
 */
(function(){
  function $(id){ return document.getElementById(id); }

  var ESC = {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'};
  function esc(s){
    return String(s == null ? '' : s).replace(/[&<>"']/g, function(c){ return ESC[c]; });
  }

  /**
   * Огноо + цаг.
   * toLocaleString('mn-MN')-д найдвал mn-MN locale байхгүй төхөөрөмж дээр
   * "8/3/2026, 4:03 PM" гэж америк маягаар гардаг. Тиймээс гараар угсарна.
   */
  function pad(n){ return (n < 10 ? '0' : '') + n; }
  function fmtWhen(iso){
    if(!iso) return '—';
    var d = new Date(iso);
    if(isNaN(d.getTime())) return String(iso);
    return d.getFullYear() + '.' + pad(d.getMonth() + 1) + '.' + pad(d.getDate())
      + ' ' + pad(d.getHours()) + ':' + pad(d.getMinutes());
  }

  /**
   * Уучлалын хэмжүүрийг (0–100) нүүр + тайлбар болгоно.
   * argadah.html болон dashboard.html хоёр ижил үг хэрэглэхийн тулд энд байрлав.
   */
  var FORGIVE_LEVELS = [
    { max:15,  face:'😿', label:'Одоохондоо их гомдолтой' },
    { max:35,  face:'😾', label:'Бага зэрэг уурлаж байна' },
    { max:55,  face:'🙂', label:'Зөөлөрч байна' },
    { max:75,  face:'😊', label:'Бараг уучлах шахлаа' },
    { max:92,  face:'🥰', label:'Тэгье дээ, уучиллаа' },
    { max:100, face:'😻', label:'Бүрэн уучлаа! 💗' }
  ];
  function forgiveLevel(v){
    var n = Number(v);
    if(isNaN(n)) n = 0;
    for(var i = 0; i < FORGIVE_LEVELS.length; i++){
      if(n <= FORGIVE_LEVELS[i].max) return FORGIVE_LEVELS[i];
    }
    return FORGIVE_LEVELS[FORGIVE_LEVELS.length - 1];
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

  window.BolzooUtils = {
    $:$, esc:esc, fmtWhen:fmtWhen, backendLabel:backendLabel,
    forgiveLevel:forgiveLevel, FORGIVE_LEVELS:FORGIVE_LEVELS
  };
})();
