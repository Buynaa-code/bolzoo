/**
 * Bolzoo — kawaii cat avatar SVG generator.
 * Хэрэглээ: BolzooCat.render(mood) → SVG string
 *          BolzooCat.orbit(mood) → orbit emoji
 *          BolzooCat.mount(el)   → тухайн <div class="avatar">-т catSVG + orbit тавина
 *
 * Шинэ mood нэмэх бол доор MOODS obj-т нэмээд түр rendering хэсэгт салбар нэм.
 */
(function(){
  var ORBIT = { ask:'✨', thanks:'💗', star:'⭐', love:'💕' };

  function star(cx, cy){
    return '<path transform="translate('+cx+','+cy+')" '
      + 'd="M0 -6.5 L1.8 -1.8 L6.7 -1.8 L2.7 1.2 L4.2 6 L0 3 L-4.2 6 L-2.7 1.2 L-6.7 -1.8 L-1.8 -1.8 Z" '
      + 'fill="#f76a8e"/>';
  }
  function heartEye(cx, cy){
    return '<path transform="translate('+cx+','+cy+')" '
      + 'd="M0 5 C-6 -1 -6 -7 -2.5 -7 C-0.8 -7 0 -5.5 0 -5.5 C0 -5.5 0.8 -7 2.5 -7 C6 -7 6 -1 0 5 Z" '
      + 'fill="#f4477a"/>';
  }

  function render(mood){
    var eyes, mouth, extra = '';
    if(mood === 'thanks'){
      eyes = '<g fill="none" stroke="#5a3a34" stroke-width="3.4" stroke-linecap="round">'
        + '<path d="M32 51 q5.5 -6 11 0"/><path d="M57 51 q5.5 -6 11 0"/></g>';
      mouth = '<path d="M43 62 q7 7 14 0" fill="none" stroke="#b76a45" stroke-width="2.4" stroke-linecap="round"/>';
    } else if(mood === 'star'){
      eyes = star(38,51) + star(62,51);
      mouth = '<path d="M42 61 q8 8 16 0 q-8 4 -16 0 Z" fill="#ff6f91"/>';
      extra = '<g fill="#ffd37e">'
        + '<path d="M20 24 l1.2 3 3 1.2 -3 1.2 -1.2 3 -1.2 -3 -3 -1.2 3 -1.2 Z"/>'
        + '<path d="M82 30 l1 2.4 2.4 1 -2.4 1 -1 2.4 -1 -2.4 -2.4 -1 2.4 -1 Z"/></g>';
    } else if(mood === 'love'){
      eyes = heartEye(38,51) + heartEye(62,51);
      mouth = '<path d="M41 60 q9 9 18 0 q-9 5 -18 0 Z" fill="#f4477a"/>'
        + '<ellipse cx="50" cy="66" rx="4" ry="2.6" fill="#ff8fab"/>';
      extra = '<g fill="#ff8fb3">'
        + '<path transform="translate(18,26)" d="M0 4 C-4 0 -4 -4 -1.6 -4 C-0.5 -4 0 -3.2 0 -3.2 C0 -3.2 0.5 -4 1.6 -4 C4 -4 4 0 0 4 Z"/>'
        + '<path transform="translate(83,30)" d="M0 4 C-4 0 -4 -4 -1.6 -4 C-0.5 -4 0 -3.2 0 -3.2 C0 -3.2 0.5 -4 1.6 -4 C4 -4 4 0 0 4 Z"/></g>';
    } else {
      eyes = '<g fill="#5a3a34"><ellipse cx="38" cy="52" rx="5.2" ry="6.6"/><ellipse cx="62" cy="52" rx="5.2" ry="6.6"/></g>'
        + '<g fill="#fff"><circle cx="40" cy="49" r="1.9"/><circle cx="64" cy="49" r="1.9"/></g>';
      mouth = '<path d="M46 60 q4 4 8 1" fill="none" stroke="#b76a45" stroke-width="2" stroke-linecap="round"/>'
        + '<path d="M54 60 q-4 4 -8 1" fill="none" stroke="#b76a45" stroke-width="2" stroke-linecap="round"/>';
    }
    return '<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">'
      + '<path d="M22 42 L27 12 L47 35 Z" fill="#ffcf9a"/><path d="M78 42 L73 12 L53 35 Z" fill="#ffcf9a"/>'
      + '<path d="M28 34 L30 19 L41 32 Z" fill="#ff9db0"/><path d="M72 34 L70 19 L59 32 Z" fill="#ff9db0"/>'
      + '<ellipse cx="50" cy="57" rx="33" ry="29" fill="#ffce9a"/>'
      + '<ellipse cx="31" cy="63" rx="7" ry="4.6" fill="#ff8fab" opacity=".72"/>'
      + '<ellipse cx="69" cy="63" rx="7" ry="4.6" fill="#ff8fab" opacity=".72"/>'
      + eyes
      + '<path d="M50 60 l-3.2 -3.4 h6.4 Z" fill="#ff6f91"/>' + mouth
      + '<g stroke="#eaa25e" stroke-width="1.5" stroke-linecap="round">'
      + '<line x1="12" y1="55" x2="25" y2="54"/><line x1="12" y1="62" x2="25" y2="61"/>'
      + '<line x1="88" y1="55" x2="75" y2="54"/><line x1="88" y1="62" x2="75" y2="61"/></g>'
      + extra + '</svg>';
  }

  function orbit(mood){ return ORBIT[mood] || '✨'; }

  function mountAll(){
    var avs = document.querySelectorAll('.avatar');
    for(var i = 0; i < avs.length; i++){
      var mood = avs[i].getAttribute('data-mood');
      avs[i].innerHTML =
        '<div class="avatar-inner">' + render(mood) + '</div>'
        + '<div class="orbit"><span>' + orbit(mood) + '</span></div>';
    }
  }

  window.BolzooCat = { render: render, orbit: orbit, mountAll: mountAll };
})();
