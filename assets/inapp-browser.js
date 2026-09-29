/**
 * Bolzoo — Instagram/Messenger/Facebook in-app browser detector.
 *
 * WebView (FB/IG/Messenger) дотор нээгдсэн бол:
 *   • Android → Chrome руу intent:// -оор автоматаар үсэрнэ
 *   • iOS     → modal харуулж, "⋯ → Open in Browser" зааврыг өгнө
 *   • Линкийг хуулах товч болон домайн руу шууд орох fallback link
 *
 * Хэрэглэх: <script src="assets/inapp-browser.js"></script>
 * (assets/utils.js, config.js-c өмнө/хойно нь байсан хамаагүй — өөрөө standalone)
 *
 * Skip хийх бол URL-д ?inapp=ok эсвэл localStorage.bolzooInappOk=1 нэмнэ.
 */
(function(){
  if (typeof window === 'undefined' || typeof document === 'undefined') return;

  var ua = navigator.userAgent || navigator.vendor || '';
  var isInApp = /FBAN|FBAV|FB_IAB|FBIOS|Instagram|Messenger|MessengerLite|Line\/|MicroMessenger|Twitter|TikTok|KAKAOTALK/i.test(ua);
  if (!isInApp) return;

  // Хэрэглэгч modal-г нэг удаа хаасан бол дахин бүү заа
  try {
    var url = new URL(window.location.href);
    if (url.searchParams.get('inapp') === 'ok') return;
    if (localStorage.getItem('bolzooInappOk') === '1') return;
  } catch(_) {}

  var isAndroid = /Android/i.test(ua);
  var isIOS = /iPhone|iPad|iPod/i.test(ua);

  // ---- Android: Chrome руу intent://-оор шууд үсэргэнэ ----
  if (isAndroid) {
    try {
      var loc = window.location;
      var hostAndPath = loc.host + loc.pathname + loc.search + loc.hash;
      // Fallback URL-д inapp=ok нэмнэ — Chrome байхгүй үед infinite loop болохоос сэргийлнэ
      var fallbackUrl = new URL(loc.href);
      fallbackUrl.searchParams.set('inapp','ok');
      var intentUrl =
        'intent://' + hostAndPath +
        '#Intent;scheme=' + loc.protocol.replace(':','') +
        ';package=com.android.chrome' +
        ';S.browser_fallback_url=' + encodeURIComponent(fallbackUrl.toString()) +
        ';end';
      window.location.href = intentUrl;
      return;
    } catch(_) { /* fall through to modal */ }
  }

  // ---- iOS (болон бусад) : modal + copy link ----
  function showModal(){
    var currentUrl = window.location.href;

    var overlay = document.createElement('div');
    overlay.id = 'bolzoo-inapp-modal';
    overlay.setAttribute('role','dialog');
    overlay.setAttribute('aria-modal','true');
    overlay.style.cssText = [
      'position:fixed','inset:0','z-index:2147483647',
      'background:linear-gradient(160deg,rgba(76,20,55,.86) 0%,rgba(90,42,70,.9) 55%,rgba(50,15,42,.92) 100%)',
      'backdrop-filter:blur(10px)','-webkit-backdrop-filter:blur(10px)',
      'display:flex','align-items:center','justify-content:center',
      'padding:20px','font-family:"Nunito",system-ui,-apple-system,sans-serif',
      'animation:bolzooInappFade .28s ease-out'
    ].join(';');

    var card = document.createElement('div');
    card.style.cssText = [
      'width:100%','max-width:380px',
      'background:linear-gradient(160deg,#fff8fb 0%,#fff2f6 60%,#fdeaf3 100%)',
      'border-radius:22px','padding:26px 22px 22px',
      'box-shadow:0 30px 70px -20px rgba(76,20,55,.55)',
      'border:1px solid rgba(255,205,220,.7)',
      'text-align:center','color:#4b173f'
    ].join(';');

    var emoji = document.createElement('div');
    emoji.textContent = '💌';
    emoji.style.cssText = 'font-size:44px;line-height:1;margin-bottom:10px;';

    var title = document.createElement('div');
    title.textContent = 'Урилгыг браузероор нээнэ үү';
    title.style.cssText = 'font-family:"Comfortaa",sans-serif;font-weight:700;font-size:20px;margin-bottom:8px;color:#4b173f;';

    var subtitle = document.createElement('div');
    subtitle.innerHTML = 'Instagram/Messenger дотор зарим функц ажиллахгүй.<br>Safari эсвэл Chrome дээр нээвэл бүх зүйл гоё харагдана 💕';
    subtitle.style.cssText = 'font-size:14px;font-weight:600;line-height:1.55;color:#7a4a68;margin-bottom:20px;';

    // iOS-т зориулсан заавар (illustrated steps)
    var steps = document.createElement('div');
    steps.style.cssText = 'text-align:left;background:#fff;border:1px dashed #ffc4d6;border-radius:14px;padding:14px 16px;margin-bottom:18px;font-size:13px;color:#5a2a46;line-height:1.6;font-weight:700;';
    if (isIOS) {
      steps.innerHTML =
        '<div style="font-weight:800;color:#c74773;margin-bottom:6px;">iPhone дээр:</div>' +
        '<div>1. Баруун дээд буланд <b>••• </b>дар</div>' +
        '<div>2. "<b>Open in External Browser</b>" сонгоно</div>' +
        '<div style="color:#8a5a78;font-weight:600;margin-top:6px;">Эсвэл линкийг хуулаад Safari-даа буулгаарай 👇</div>';
    } else {
      steps.innerHTML =
        '<div style="font-weight:800;color:#c74773;margin-bottom:6px;">Заавар:</div>' +
        '<div>Меню товчоо дараад "Open in browser" сонгоно уу.</div>' +
        '<div style="color:#8a5a78;font-weight:600;margin-top:6px;">Эсвэл линкийг хуулаад браузероо нээгээрэй 👇</div>';
    }

    var linkBox = document.createElement('div');
    linkBox.style.cssText = 'display:flex;gap:8px;align-items:center;background:#fff;border:1px solid #ffd5e0;border-radius:12px;padding:10px 12px;margin-bottom:14px;';

    var linkText = document.createElement('div');
    linkText.textContent = currentUrl;
    linkText.style.cssText = 'flex:1;font-size:12px;color:#6a3a55;font-weight:600;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;text-align:left;';

    var copyBtn = document.createElement('button');
    copyBtn.type = 'button';
    copyBtn.textContent = 'Хуулах';
    copyBtn.style.cssText = 'flex:0 0 auto;background:#ff4d82;color:#fff;border:none;border-radius:10px;padding:8px 14px;font-family:"Nunito",sans-serif;font-weight:800;font-size:12px;cursor:pointer;';
    copyBtn.addEventListener('click', function(){
      var done = function(){
        copyBtn.textContent = '✓ Хууллаа';
        copyBtn.style.background = '#22a06b';
        setTimeout(function(){
          copyBtn.textContent = 'Хуулах';
          copyBtn.style.background = '#ff4d82';
        }, 1800);
      };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(currentUrl).then(done, function(){ fallbackCopy(); });
      } else {
        fallbackCopy();
      }
      function fallbackCopy(){
        try {
          var ta = document.createElement('textarea');
          ta.value = currentUrl;
          ta.style.position = 'fixed';
          ta.style.opacity = '0';
          document.body.appendChild(ta);
          ta.select();
          document.execCommand('copy');
          document.body.removeChild(ta);
          done();
        } catch(e){}
      }
    });

    linkBox.appendChild(linkText);
    linkBox.appendChild(copyBtn);

    // Safari-д шууд нээхийг оролдох (iOS-д ихэвчлэн ажилладаггүй ч оролдоно)
    var openBtn = document.createElement('a');
    openBtn.href = currentUrl;
    openBtn.target = '_blank';
    openBtn.rel = 'noopener noreferrer';
    openBtn.textContent = '🌐 Браузероор нээх';
    openBtn.style.cssText = 'display:block;text-decoration:none;background:linear-gradient(135deg,#ff4d82,#c136a0);color:#fff;padding:14px 18px;border-radius:14px;font-weight:900;font-size:15px;box-shadow:0 12px 30px -14px rgba(193,54,160,.7);margin-bottom:10px;';

    var closeBtn = document.createElement('button');
    closeBtn.type = 'button';
    closeBtn.textContent = 'Ойлголоо, үргэлжлүүлэх';
    closeBtn.style.cssText = 'background:transparent;border:none;color:#9a6b84;font-family:"Nunito",sans-serif;font-weight:700;font-size:13px;cursor:pointer;padding:6px 10px;';
    closeBtn.addEventListener('click', function(){
      try { localStorage.setItem('bolzooInappOk','1'); } catch(_){}
      if (overlay.parentNode) overlay.parentNode.removeChild(overlay);
    });

    card.appendChild(emoji);
    card.appendChild(title);
    card.appendChild(subtitle);
    card.appendChild(steps);
    card.appendChild(linkBox);
    card.appendChild(openBtn);
    card.appendChild(closeBtn);
    overlay.appendChild(card);

    var style = document.createElement('style');
    style.textContent = '@keyframes bolzooInappFade{from{opacity:0;transform:scale(.96)}to{opacity:1;transform:scale(1)}}';
    document.head.appendChild(style);

    document.body.appendChild(overlay);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', showModal);
  } else {
    showModal();
  }
})();
