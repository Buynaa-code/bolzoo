/**
 * Bolzoo — захидлын цаасны текстур сан.
 *
 * Бүх текстур нь цэвэр CSS (gradient + inline SVG data URI) — гадны зураг,
 * CDN шаардахгүй тул static hosting дээр шууд ажиллана.
 *
 * Хэрэглээ:
 *   BolzooPaper.LIST              → [{id, label, emoji}, ...] сонгогч жагсаалт
 *   BolzooPaper.get(id)           → тухайн цаасны тодорхойлолт
 *   BolzooPaper.apply(el, id)     → элемент дээр дэвсгэр + бэхний өнгө тавина
 *   BolzooPaper.swatchStyle(id)   → сонгогчийн жижиг дөрвөлжинд тохирсон style
 *
 * Шинэ цаас нэмэх бол доорх PAPERS обьектод нэг мөр нэмэхэд хангалттай.
 */
(function(){
  'use strict';

  /* Нарийн ширхэгт мөхлөг — цаасны утас/ширхэгийг дуурайна */
  function grain(opacity, freq){
    return "url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='140' height='140'%3E"
      + "%3Cfilter id='g'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='" + (freq || 0.8)
      + "' numOctaves='3' stitchTiles='stitch'/%3E%3CfeColorMatrix type='saturate' values='0'/%3E%3C/filter%3E"
      + "%3Crect width='140' height='140' filter='url(%23g)' opacity='" + opacity + "'/%3E%3C/svg%3E\")";
  }

  /* Давтагдах зүрх — ягаан хээтэй цаас */
  function heartTile(color, size){
    return "url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='" + size + "' height='" + size + "'%3E"
      + "%3Cpath d='M14 21 C6 14 6 7 10.5 7 C12.6 7 14 9 14 9 C14 9 15.4 7 17.5 7 C22 7 22 14 14 21 Z' "
      + "fill='" + encodeURIComponent(color) + "'/%3E%3C/svg%3E\")";
  }

  var PAPERS = {
    cream: {
      label: 'Цөцгий', emoji: '🤍',
      ink: '#4b2a44', line: 'rgba(255,190,208,.34)',
      background:
        grain(0.05) + ','
        + 'radial-gradient(120% 90% at 15% 0%, #fffdfa 0%, transparent 55%),'
        + 'radial-gradient(110% 90% at 100% 100%, #fff2f4 0%, transparent 60%),'
        + 'linear-gradient(160deg,#fffaf6 0%,#fff5f1 48%,#fff3f6 100%)'
    },
    linen: {
      label: 'Маалинган', emoji: '🧵',
      ink: '#46304a', line: 'rgba(190,160,180,.3)',
      background:
        grain(0.045, 0.9) + ','
        + 'repeating-linear-gradient(90deg, rgba(150,120,140,.055) 0 1px, transparent 1px 4px),'
        + 'repeating-linear-gradient(0deg, rgba(150,120,140,.055) 0 1px, transparent 1px 4px),'
        + 'linear-gradient(155deg,#fbf7f4 0%,#f6efec 100%)'
    },
    kraft: {
      label: 'Крафт', emoji: '📦',
      ink: '#4a3120', line: 'rgba(140,100,60,.28)',
      background:
        grain(0.085, 0.7) + ','
        + 'radial-gradient(100% 80% at 20% 10%, rgba(255,235,205,.55) 0%, transparent 60%),'
        + 'linear-gradient(150deg,#e8cfa8 0%,#dfc094 55%,#e6cba3 100%)'
    },
    ruled: {
      label: 'Дэвтэр', emoji: '📓',
      ink: '#25406b', line: 'rgba(90,140,200,.5)',
      lined: true,
      background:
        'repeating-linear-gradient(180deg, transparent 0 30px, rgba(96,150,205,.32) 30px 31px),'
        + 'linear-gradient(90deg, transparent 0 30px, rgba(240,120,140,.5) 30px 31.5px, transparent 31.5px),'
        + grain(0.035) + ','
        + 'linear-gradient(160deg,#fdfdfa 0%,#f8fbfd 100%)'
    },
    grid: {
      label: 'Тор', emoji: '📐',
      ink: '#2f4a52', line: 'rgba(120,170,180,.4)',
      background:
        'repeating-linear-gradient(0deg, transparent 0 15px, rgba(120,175,185,.22) 15px 16px),'
        + 'repeating-linear-gradient(90deg, transparent 0 15px, rgba(120,175,185,.22) 15px 16px),'
        + grain(0.03) + ','
        + 'linear-gradient(160deg,#fbfefe 0%,#f3fbfa 100%)'
    },
    hearts: {
      label: 'Зүрхэн', emoji: '💗',
      ink: '#5c2246', line: 'rgba(255,150,180,.42)',
      // Хээ нь текстийг бүлээхгүйн тулд цайвар өнгө, өргөн алхамтай
      background:
        heartTile('#ffe2ea', 46) + ','
        + grain(0.04) + ','
        + 'linear-gradient(160deg,#fff9fc 0%,#fff0f6 100%)'
    },
    vintage: {
      label: 'Хуучирсан', emoji: '🕰',
      ink: '#4a3524', line: 'rgba(150,110,70,.32)',
      background:
        grain(0.075, 0.75) + ','
        + 'radial-gradient(120% 100% at 50% 50%, transparent 45%, rgba(120,80,40,.16) 100%),'
        + 'radial-gradient(60% 45% at 12% 8%, rgba(190,140,80,.2) 0%, transparent 70%),'
        + 'radial-gradient(55% 40% at 88% 92%, rgba(180,130,75,.18) 0%, transparent 70%),'
        + 'linear-gradient(155deg,#f8ecd6 0%,#f2e1c4 100%)'
    },
    blush: {
      label: 'Ягаан манан', emoji: '🌸',
      ink: '#5b1f42', line: 'rgba(255,140,180,.4)',
      background:
        grain(0.04) + ','
        + 'radial-gradient(90% 70% at 80% 5%, rgba(255,205,225,.8) 0%, transparent 62%),'
        + 'radial-gradient(85% 65% at 5% 95%, rgba(255,225,205,.75) 0%, transparent 60%),'
        + 'linear-gradient(150deg,#fff4f8 0%,#ffe9f1 100%)'
    }
  };

  var ORDER = ['cream','blush','hearts','linen','ruled','grid','kraft','vintage'];

  var LIST = ORDER.map(function(id){
    return { id: id, label: PAPERS[id].label, emoji: PAPERS[id].emoji };
  });

  function get(id){
    return PAPERS[id] || PAPERS.cream;
  }

  /**
   * Цаасны дэвсгэр + бэхний өнгийг элемент дээр тавина.
   *
   * ВАЖНО: background утга нь давхар хашилттай data-URI агуулдаг тул үүнийг
   * HTML-ийн style="..." атрибутад ШУУД БИЧИЖ БОЛОХГҮЙ — атрибут тасарна.
   * Үргэлж энэ функцээр (JS-ээр) тавь.
   */
  function apply(el, id){
    if(!el) return;
    var p = get(id);
    el.style.background = p.background;
    el.style.color = p.ink;
    el.setAttribute('data-paper', PAPERS[id] ? id : 'cream');
  }

  window.BolzooPaper = {
    LIST: LIST,
    PAPERS: PAPERS,
    get: get,
    apply: apply,
    ids: ORDER
  };
})();
