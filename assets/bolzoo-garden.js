/**
 * Bolzoo — цэцэг ба захидлын цаасны сан.
 *
 * Ашиглаж буй хуудсууд: create.html (сонголт + preview), greet.html (мэндчилгээ).
 * Бүх цэцэг нь inline SVG — нэмэлт зураг, CDN шаардахгүй.
 *
 * window.BolzooGarden:
 *   FLOWERS            → [{id,name,note,accent}]  (5 төрөл)
 *   PAPERS             → [{id,name,bg,ink,line,edge}]  (5 төрөл)
 *   flowerSVG(id,size) → SVG markup string
 *   flower(id)         → цэцгийн объект (олдохгүй бол эхнийх)
 *   paper(id)          → цаасны объект (олдохгүй бол эхнийх)
 */
(function(){
  var seq = 0;

  function ellipseRing(count, rx, ry, dist, fill, offset, opacity){
    var out = '', step = 360 / count;
    for(var i = 0; i < count; i++){
      out += '<ellipse cx="100" cy="' + (84 - dist) + '" rx="' + rx + '" ry="' + ry + '" fill="' + fill + '"'
           + (opacity ? ' opacity="' + opacity + '"' : '')
           + ' transform="rotate(' + (offset + i * step) + ' 100 84)"/>';
    }
    return out;
  }

  function pathRing(count, d, fill, offset, extra){
    var out = '', step = 360 / count;
    for(var i = 0; i < count; i++){
      out += '<path d="' + d + '" fill="' + fill + '"' + (extra || '')
           + ' transform="rotate(' + (offset + i * step) + ' 100 84)"/>';
    }
    return out;
  }

  function stem(u, leaf, leafDark){
    return '<path d="M100 116 C 94 152 105 188 100 236" stroke="url(#st' + u + ')" stroke-width="7" fill="none" stroke-linecap="round"/>'
         + '<path d="M99 170 C 74 170 57 154 52 132 C 81 129 95 145 99 170 Z" fill="' + leaf + '"/>'
         + '<path d="M99 170 C 80 162 66 150 56 136" stroke="' + leafDark + '" stroke-width="2" fill="none" opacity=".55"/>'
         + '<path d="M101 200 C 126 200 143 184 148 162 C 119 159 105 175 101 200 Z" fill="' + leaf + '" opacity=".92"/>'
         + '<path d="M101 200 C 120 192 134 180 144 166" stroke="' + leafDark + '" stroke-width="2" fill="none" opacity=".45"/>';
  }

  function wrap(u, defs, body, size){
    var attr = size ? ' width="' + size + '" height="' + Math.round(size * 1.25) + '"' : '';
    return '<svg class="bz-flower-svg" viewBox="0 0 200 250"' + attr + ' xmlns="http://www.w3.org/2000/svg" role="img" aria-hidden="true">'
         + '<defs>' + defs
         + '<linearGradient id="st' + u + '" x1="0" y1="0" x2="0" y2="1">'
         + '<stop offset="0" stop-color="#6bbf8a"/><stop offset="1" stop-color="#3f8f63"/></linearGradient>'
         + '</defs>' + body + '</svg>';
  }

  /* ---------- 1. Сарнай ---------- */
  function rose(u, size){
    var defs =
      '<radialGradient id="ro' + u + '" cx="42%" cy="34%" r="72%">'
      + '<stop offset="0" stop-color="#ff9fb6"/><stop offset="1" stop-color="#e0476f"/></radialGradient>'
      + '<radialGradient id="ri' + u + '" cx="46%" cy="38%" r="70%">'
      + '<stop offset="0" stop-color="#ffd0dc"/><stop offset="1" stop-color="#f2708f"/></radialGradient>';
    var body = stem(u, '#5bb37f', '#2f7b52')
      + ellipseRing(6, 33, 37, 25, 'url(#ro' + u + ')', 0)
      + ellipseRing(6, 25, 28, 17, 'url(#ri' + u + ')', 30)
      + ellipseRing(5, 17, 19, 10, '#ffdbe5', 12)
      + ellipseRing(4, 11, 13, 5, '#ffc2d3', 24)
      + '<path d="M110 76 C 116 86 110 96 99 95 C 88 94 83 84 88 76 C 93 68 105 68 108 76"'
      + ' fill="none" stroke="#d2426a" stroke-width="3.4" stroke-linecap="round" opacity=".6"/>'
      + '<path d="M104 82 C 107 88 103 93 98 91 C 93 89 93 83 97 81"'
      + ' fill="none" stroke="#c93a63" stroke-width="3" stroke-linecap="round" opacity=".5"/>';
    return wrap(u, defs, body, size);
  }

  /* ---------- 2. Алтанзул (tulip) ---------- */
  function tulip(u, size){
    var defs =
      '<linearGradient id="tu' + u + '" x1="0" y1="0" x2="0" y2="1">'
      + '<stop offset="0" stop-color="#ff85a8"/><stop offset="1" stop-color="#dc3b6d"/></linearGradient>'
      + '<linearGradient id="tl' + u + '" x1="0" y1="0" x2="0" y2="1">'
      + '<stop offset="0" stop-color="#ffb3c8"/><stop offset="1" stop-color="#ef6f95"/></linearGradient>';
    var body = stem(u, '#57ad7b', '#2e7a51')
      + '<path d="M66 106 C 58 60 72 30 100 20 C 128 30 142 60 134 106 C 118 120 82 120 66 106 Z" fill="url(#tu' + u + ')"/>'
      + '<path d="M66 106 C 58 62 68 34 86 22 C 92 54 86 84 92 114 C 82 114 72 111 66 106 Z" fill="url(#tl' + u + ')"/>'
      + '<path d="M134 106 C 142 62 132 34 114 22 C 108 54 114 84 108 114 C 118 114 128 111 134 106 Z" fill="url(#tl' + u + ')" opacity=".85"/>'
      + '<path d="M100 24 C 106 52 106 84 100 114" stroke="#ffd6e2" stroke-width="3" fill="none" opacity=".65" stroke-linecap="round"/>';
    return wrap(u, defs, body, size);
  }

  /* ---------- 3. Наранцэцэг ---------- */
  function sunflower(u, size){
    var defs =
      '<linearGradient id="su' + u + '" x1="0" y1="1" x2="0" y2="0">'
      + '<stop offset="0" stop-color="#f0a325"/><stop offset="1" stop-color="#ffd75e"/></linearGradient>'
      + '<radialGradient id="sc' + u + '" cx="42%" cy="36%" r="70%">'
      + '<stop offset="0" stop-color="#8a5a2b"/><stop offset="1" stop-color="#4d2f14"/></radialGradient>';
    var petal = 'M100 84 C 113 58 113 28 100 8 C 87 28 87 58 100 84 Z';
    var dots = '';
    for(var r = 6; r <= 20; r += 7){
      var n = r * 2;
      for(var i = 0; i < n; i++){
        var a = (i / n) * Math.PI * 2 + r;
        dots += '<circle cx="' + (100 + Math.cos(a) * r).toFixed(1) + '" cy="' + (84 + Math.sin(a) * r).toFixed(1)
             + '" r="1.7" fill="#f3c46a" opacity=".5"/>';
      }
    }
    var body = stem(u, '#5aa96f', '#2f7245')
      + pathRing(14, petal, 'url(#su' + u + ')', 12.85, ' opacity=".9"')
      + pathRing(14, petal, 'url(#su' + u + ')', 0)
      + '<circle cx="100" cy="84" r="27" fill="url(#sc' + u + ')"/>' + dots
      + '<circle cx="100" cy="84" r="27" fill="none" stroke="#facf74" stroke-width="3"/>';
    return wrap(u, defs, body, size);
  }

  /* ---------- 4. Сараана (lily) ---------- */
  function lily(u, size){
    var defs =
      '<linearGradient id="li' + u + '" x1="0" y1="1" x2="0" y2="0">'
      + '<stop offset="0" stop-color="#ffd9ea"/><stop offset="1" stop-color="#fffdfd"/></linearGradient>';
    var petal = 'M100 84 C 120 56 122 22 100 2 C 78 22 80 56 100 84 Z';
    var stamens = '';
    for(var i = 0; i < 5; i++){
      var a = (-60 + i * 30) * Math.PI / 180;
      var x = 100 + Math.sin(a) * 26, y = 84 - Math.cos(a) * 30;
      stamens += '<line x1="100" y1="84" x2="' + x.toFixed(1) + '" y2="' + y.toFixed(1) + '" stroke="#e8b36a" stroke-width="2.4" stroke-linecap="round"/>'
              + '<ellipse cx="' + x.toFixed(1) + '" cy="' + y.toFixed(1) + '" rx="4" ry="6" fill="#d98b3f" transform="rotate(' + (-60 + i * 30) + ' ' + x.toFixed(1) + ' ' + y.toFixed(1) + ')"/>';
    }
    var body = stem(u, '#63b487', '#357c58')
      + pathRing(6, petal, 'url(#li' + u + ')', 30, ' stroke="#f6c7dd" stroke-width="1.5"')
      + pathRing(6, 'M100 84 C 112 62 114 36 100 20 C 86 36 88 62 100 84 Z', '#ffeef6', 0)
      + '<g opacity=".9">' + stamens + '</g>'
      + '<circle cx="100" cy="84" r="6" fill="#f7d9a0"/>';
    return wrap(u, defs, body, size);
  }

  /* ---------- 5. Ромашка (daisy) ---------- */
  function daisy(u, size){
    var defs =
      '<linearGradient id="da' + u + '" x1="0" y1="1" x2="0" y2="0">'
      + '<stop offset="0" stop-color="#f3f0f6"/><stop offset="1" stop-color="#ffffff"/></linearGradient>'
      + '<radialGradient id="dc' + u + '" cx="42%" cy="36%" r="70%">'
      + '<stop offset="0" stop-color="#ffdc72"/><stop offset="1" stop-color="#eda315"/></radialGradient>';
    var petal = 'M100 84 C 108 60 108 32 100 16 C 92 32 92 60 100 84 Z';
    var body = stem(u, '#66bb8b', '#38855e')
      + pathRing(13, petal, '#efe6ee', 13.8, ' opacity=".9"')
      + pathRing(13, petal, 'url(#da' + u + ')', 0, ' stroke="#d9cbd6" stroke-width="1.6"')
      + '<circle cx="100" cy="84" r="19" fill="url(#dc' + u + ')"/>'
      + '<circle cx="94" cy="79" r="4" fill="#fff0bf" opacity=".55"/>';
    return wrap(u, defs, body, size);
  }

  var BUILDERS = { rose: rose, tulip: tulip, sunflower: sunflower, lily: lily, daisy: daisy };

  var FLOWERS = [
    { id:'rose',      name:'Сарнай',     note:'Сонгодог хайрын цэцэг',      accent:'#e0476f' },
    { id:'tulip',     name:'Алтанзул',   note:'Зөөлөн, шинэлэг сэтгэгдэл',  accent:'#dc3b6d' },
    { id:'sunflower', name:'Наранцэцэг', note:'Баяр хөөр, дулаан илгээе',   accent:'#eda315' },
    { id:'lily',      name:'Сараана',    note:'Цэвэр, эмзэглэлтэй',         accent:'#c98fb4' },
    { id:'daisy',     name:'Ромашка',    note:'Энгийн, чин сэтгэлийн',      accent:'#7fb98f' }
  ];

  var PAPERS = [
    { id:'cream',   name:'Сүүн цагаан',      bg:'linear-gradient(180deg,#fffdf6,#fdf7ea)', ink:'#4a3b2f', line:'rgba(120,150,190,.22)', edge:'#efe2cd' },
    { id:'kraft',   name:'Бор крафт',        bg:'linear-gradient(180deg,#eadbbe,#dcc59f)', ink:'#4a3623', line:'rgba(105,74,40,.18)',   edge:'#c9ad83' },
    { id:'blush',   name:'Ягаан хайр',       bg:'linear-gradient(180deg,#fff4f7,#ffe9f0)', ink:'#6b2f4c', line:'rgba(224,110,150,.22)', edge:'#f7cfdd' },
    { id:'sky',     name:'Тэнгэрийн цэнхэр', bg:'linear-gradient(180deg,#f4faff,#e8f2fd)', ink:'#25445f', line:'rgba(90,140,200,.24)',  edge:'#cfe2f5' },
    { id:'vintage', name:'Хуучин захидал',   bg:'linear-gradient(180deg,#f9efd6,#f1e0bd)', ink:'#503a20', line:'rgba(140,105,55,.2)',   edge:'#dfc79a' }
  ];

  function findBy(list, id){
    for(var i = 0; i < list.length; i++){ if(list[i].id === id) return list[i]; }
    return list[0];
  }

  function flowerSVG(id, size){
    var f = findBy(FLOWERS, id);
    return BUILDERS[f.id](String(++seq), size);
  }

  window.BolzooGarden = {
    FLOWERS: FLOWERS,
    PAPERS: PAPERS,
    flowerSVG: flowerSVG,
    flower: function(id){ return findBy(FLOWERS, id); },
    paper:  function(id){ return findBy(PAPERS, id); }
  };
})();
