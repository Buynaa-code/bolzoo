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
      title:     'Spider-Man: ХҮН-ААЛЗ',
      subtitle:  'ЦОО ШИНЭ ӨДӨР',
      tagline:   'Spider-Man кинонд хамт явах уу?',
      dateLabel: '7-р сарын 31',
      image:     'assets/posters/hun-aalz.png',
      kind:      'movie',
      availableUntil: '2026-07-31T23:59:59.999+08:00'
    }
  };

  function isAvailable(poster){
    if(!poster) return false;
    if(!poster.availableUntil) return true;
    return Date.now() <= new Date(poster.availableUntil).getTime();
  }

  function list(){
    return Object.keys(POSTERS)
      .map(function(k){ return POSTERS[k]; })
      .filter(isAvailable);
  }
  function get(id){
    if(!id) return null;
    var poster = POSTERS[id] || null;
    return isAvailable(poster) ? poster : null;
  }
  function has(id){
    return !!get(id);
  }

  window.BolzooPosters = {
    list: list,
    get: get,
    has: has
  };
})();
