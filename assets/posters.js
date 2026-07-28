/**
 * Bolzoo poster registry.
 * Онцгой урилга — постерийн жагсаалт.
 *
 * Шинэ постер нэмэхдээ:
 *   1) assets/posters/ дотор зурагаа тавь
 *   2) энд шинэ entry нэм (id, title, tagline, dateLabel, image)
 *
 * Хэрэглэгдэх газар:
 *   - create.html    → picker дээр харуулна, config.poster-т id-г нь хадгална
 *   - bolzoo.html    → config.poster байгаа бол dialog нээгээд Тийм/Үгүй асууна
 */
(function(){
  var POSTERS = {
    'hun-aalz': {
      id:        'hun-aalz',
      title:     'ХҮН-ААЛЗ',
      subtitle:  'ЦОО ШИНЭ ӨДӨР',
      tagline:   'Хамтдаа кино үзэх үү?',
      dateLabel: '7-р сарын 31',
      image:     'assets/posters/hun-aalz.png',
      kind:      'movie'
    }
  };

  function list(){
    return Object.keys(POSTERS).map(function(k){ return POSTERS[k]; });
  }
  function get(id){
    if(!id) return null;
    return POSTERS[id] || null;
  }
  function has(id){
    return !!POSTERS[id];
  }

  window.BolzooPosters = {
    list: list,
    get: get,
    has: has
  };
})();
