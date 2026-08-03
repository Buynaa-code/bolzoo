/**
 * Bolzoo — захидлын муурын зураг (стикер) сан.
 *
 * Хэрэглээ:
 *   BolzooSticker.LIST            → сонгогчид харуулах жагсаалт
 *   BolzooSticker.html(id)        → тухайн стикерийн HTML (img эсвэл SVG)
 *   BolzooSticker.thumbHtml(id)   → сонгогчийн жижиг харагдац
 *
 * Шинэ зураг нэмэх бол assets/img/ дотор .webp хийгээд доор нэг мөр нэмнэ.
 */
(function(){
  'use strict';

  var STICKERS = {
    none: {
      label: 'Байхгүй', emoji: '∅', type: 'none'
    },
    roses: {
      label: 'Сарнайтай', emoji: '🌹', type: 'img',
      src: 'assets/img/cat-roses.webp',
      thumb: 'assets/img/cat-roses-thumb.webp',
      alt: 'Улаан сарнай барьсан муур'
    },
    party: {
      label: 'Баярын', emoji: '🎂', type: 'img',
      src: 'assets/img/cat-party.webp',
      thumb: 'assets/img/cat-party-thumb.webp',
      alt: 'Малгайтай, бялуу, цэцэг барьсан муур'
    },
    draw: {
      label: 'Зурсан', emoji: '🐱', type: 'svg', mood: 'love'
    }
  };

  var ORDER = ['roses','party','draw','none'];

  var LIST = ORDER.map(function(id){
    return { id: id, label: STICKERS[id].label, emoji: STICKERS[id].emoji, type: STICKERS[id].type };
  });

  function get(id){
    return STICKERS[id] || STICKERS.roses;
  }

  function svgCat(mood){
    if(window.BolzooCat && window.BolzooCat.render){
      return '<div class="sticker-svg">' + window.BolzooCat.render(mood || 'love') + '</div>';
    }
    return '<div class="sticker-svg" aria-hidden="true">🐱</div>';
  }

  function html(id){
    var s = get(id);
    if(s.type === 'none') return '';
    if(s.type === 'svg') return svgCat(s.mood);
    return '<img class="sticker-img" src="' + s.src + '" alt="' + s.alt + '" loading="lazy" />';
  }

  function thumbHtml(id){
    var s = get(id);
    if(s.type === 'none') return '<span class="sticker-none">∅</span>';
    if(s.type === 'svg') return svgCat(s.mood);
    return '<img src="' + s.thumb + '" alt="' + s.alt + '" loading="lazy" />';
  }

  window.BolzooSticker = {
    LIST: LIST,
    STICKERS: STICKERS,
    ids: ORDER,
    get: get,
    html: html,
    thumbHtml: thumbHtml
  };
})();
