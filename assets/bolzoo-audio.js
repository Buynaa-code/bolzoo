/**
 * Bolzoo — audio subsystem (YouTube background song + Tone.js fallback FX).
 *
 * Хэрэглээ:
 *   var audio = BolzooAudio.init({
 *     videoId:    'qsPzEsxyzB8',
 *     buttonEl:   document.getElementById('sound'),
 *     iconEl:     document.getElementById('soundIcon'),
 *     textEl:     document.getElementById('soundText'),
 *     hostElId:   'ytHost'   // YT iframe host div id
 *   });
 *   audio.pop('A4');    // жижиг pop эффект
 *   audio.twinkle();    // twinkle bell
 *   audio.chime();      // урт chime (баяр)
 *   audio.initFX();     // хэрэглэгчийн эхний товшилтын дараа
 *
 * Тэмдэглэл: Tone.js CDN-с ачаалагдсан байх ёстой.
 * YouTube iframe API-г мөн энд өөрөө ачаална.
 */
(function(){
  function init(opts){
    var VIDEO_ID = opts.videoId || '';
    var YT_VOLUME = opts.volume != null ? opts.volume : 55;
    var soundBtn = opts.buttonEl, soundIcon = opts.iconEl, soundText = opts.textEl;
    var hostElId = opts.hostElId || 'ytHost';
    // Хэрэв true бол YT API бэлэн болоход шууд player үүсгэхгүй.
    // Оронд нь setVideoId эсвэл safety timeout-оор эхэлнэ. Race condition-с сэргийлнэ.
    var deferPlayerCreation = opts.deferPlayerCreation === true;

    var muted = false, fxReady = false;
    var masterVol = null, reverbNode = null, fxPop = null, fxBell = null;
    var toneMelodyStarted = false;
    var ytApiReady = false;
    var ytPlayer = null, ytState = 'loading', bgStarted = false;
    var wantPlay = false, firstGestureAt = 0;

    function updateSoundUI(){
      var playing = wantPlay && bgStarted && !muted;
      soundBtn.classList.toggle('playing', playing);
      soundBtn.setAttribute('aria-pressed', playing ? 'true' : 'false');
      soundBtn.setAttribute('aria-label', playing ? 'Хөгжим түр зогсоох' : 'Хөгжим тоглуулах');
      soundIcon.textContent = playing ? '🔊' : (muted ? '🔇' : '🎵');
      soundText.textContent = playing ? 'дуу явж байна' : 'дуу асаах';
    }

    function initFX(){
      if(fxReady || !window.Tone) return;
      try{
        Tone.start();
        masterVol = new Tone.Volume(-11).toDestination();
        reverbNode = new Tone.Reverb({decay:4.5, wet:0.35}).connect(masterVol);
        fxPop = new Tone.Synth({oscillator:{type:'sine'}, envelope:{attack:0.001, decay:0.13, sustain:0, release:0.08}}).connect(masterVol);
        fxPop.volume.value = -10;
        fxBell = new Tone.Synth({oscillator:{type:'triangle'}, envelope:{attack:0.001, decay:0.3, sustain:0, release:0.3}}).connect(reverbNode);
        fxBell.volume.value = -6;
        fxReady = true;
        masterVol.mute = muted;
      }catch(e){}
    }

    function startToneMelody(){
      if(toneMelodyStarted || !window.Tone || !fxReady) return;
      try{
        var delay = new Tone.FeedbackDelay('4n', 0.18); delay.wet.value = 0.22; delay.connect(reverbNode);
        var padS = new Tone.PolySynth(Tone.Synth, {oscillator:{type:'triangle'}, envelope:{attack:0.7, decay:0.4, sustain:0.6, release:2.4}}).connect(reverbNode);
        padS.volume.value = -15;
        var melS = new Tone.Synth({oscillator:{type:'triangle'}, envelope:{attack:0.02, decay:0.45, sustain:0.14, release:1.3}}).connect(delay);
        melS.volume.value = -6;
        var chords = [['C4','E4','G4'], ['B3','D4','G4'], ['A3','C4','E4'], ['A3','C4','F4']];
        var melody = ['E5','G5','C6','G5','D5','G5','B5','G5','C5','E5','A5','E5','C5','F5','A5','C6'];
        Tone.Transport.bpm.value = 74;
        var bar = 0;
        new Tone.Loop(function(time){ padS.triggerAttackRelease(chords[bar%4], '1n', time, 0.5); bar++; }, '1m').start(0);
        var seq = new Tone.Sequence(function(time, note){ if(note){ melS.triggerAttackRelease(note, '8n', time, 0.7); } }, melody, '4n');
        seq.loop = true; seq.start(0);
        Tone.Transport.start('+0.1');
        toneMelodyStarted = true;
      }catch(e){}
    }

    function setVideoId(id){
      if(!id) return;
      var changed = (id !== VIDEO_ID);
      VIDEO_ID = id;
      // 1) Player аль хэдийн 'ready' бол шууд солино (амжилттай тохиолдол).
      if(ytPlayer && ytState === 'ready' && changed){
        try{
          ytPlayer.loadVideoById(id);
          ytPlayer.setVolume(YT_VOLUME);
          if(muted){ ytPlayer.mute(); } else { ytPlayer.unMute(); }
          if(bgStarted){ ytPlayer.playVideo(); }
        }catch(e){}
        return;
      }
      // 2) Player одоо болтол үүсээгүй бөгөөд YT API бэлэн бол одоо үүсгэнэ
      //    (defer горимд getInvite ирсний дараа энд ирнэ).
      if(!ytPlayer && ytApiReady){
        try{ createYtPlayer(); }catch(e){ ytFail(); }
        return;
      }
      // 3) YT API мөн бэлэн болоогүй бол VIDEO_ID шинэчилсэн байна;
      //    onYouTubeIframeAPIReady ирэхэд шинэ утгыг ашиглана.
    }

    function pop(note){ if(!fxReady || !fxPop) return; try{ fxPop.triggerAttackRelease(note || 'C6', '32n'); }catch(e){} }
    function twinkle(){ if(!fxReady || !fxBell) return; try{ fxBell.triggerAttackRelease('E6', '16n'); }catch(e){} }
    function chime(){
      if(!fxReady || !fxBell) return;
      try{
        var t = Tone.now(), ns = ['C5','E5','G5','C6'];
        for(var i = 0; i < ns.length; i++){ fxBell.triggerAttackRelease(ns[i], '8n', t + i*0.09); }
      }catch(e){}
    }

    window.onYouTubeIframeAPIReady = function(){
      ytApiReady = true;
      // Хэрэглэгч defer оруулсан бол setVideoId дуудагдтал хүлээнэ.
      if(deferPlayerCreation) return;
      try{ createYtPlayer(); }catch(e){ ytFail(); }
    };
    (function loadYT(){
      var tag = document.createElement('script');
      tag.src = 'https://www.youtube.com/iframe_api';
      tag.onerror = ytFail;
      document.head.appendChild(tag);
      setTimeout(function(){ if(ytState === 'loading' && !window.YT){ ytFail(); } }, 4000);
    })();

    function createYtPlayer(){
      ytPlayer = new YT.Player(hostElId, {
        videoId: VIDEO_ID,
        playerVars: { autoplay:0, controls:0, disablekb:1, loop:1, playlist:VIDEO_ID, playsinline:1, modestbranding:1, rel:0, fs:0 },
        events: { onReady:onYtReady, onError:ytFail, onStateChange:onYtState }
      });
    }
    function onYtReady(){ ytState = 'ready'; try{ ytPlayer.setVolume(YT_VOLUME); }catch(e){} if(wantPlay && !bgStarted){ startBackground(); } updateSoundUI(); }
    function ytFail(){ if(ytState === 'ready') return; ytState = 'failed'; if(wantPlay && !bgStarted){ startBackground(); } updateSoundUI(); }
    function onYtState(e){ if(e && e.data === 0){ try{ ytPlayer.seekTo(0); ytPlayer.playVideo(); }catch(_){} } }
    function startBackground(){
      if(bgStarted){ updateSoundUI(); return; }
      if(ytState === 'ready' && ytPlayer){
        try{
          ytPlayer.setVolume(YT_VOLUME);
          if(muted){ ytPlayer.mute(); } else { ytPlayer.unMute(); }
          ytPlayer.playVideo();
          bgStarted = true;
        }catch(e){ ytState = 'failed'; startToneMelody(); bgStarted = true; }
      } else if(ytState === 'failed'){
        startToneMelody();
        bgStarted = true;
      }
      updateSoundUI();
    }
    function firstGesture(){
      firstGestureAt = Date.now();
      wantPlay = true;
      initFX();
      startBackground();
      updateSoundUI();
      setTimeout(function(){ if(!bgStarted){ ytState = 'failed'; startBackground(); } }, 4500);
    }
    window.addEventListener('pointerdown', firstGesture, { once:true });

    function setMuted(m){
      muted = m;
      if(masterVol){ masterVol.mute = m; }
      if(ytPlayer && ytState === 'ready'){ try{ if(m){ ytPlayer.mute(); } else { ytPlayer.unMute(); } }catch(e){} }
      updateSoundUI();
    }

    soundBtn.addEventListener('click', function(){
      if(!fxReady){ initFX(); }
      if(Date.now() - firstGestureAt < 350){ setMuted(false); }
      else if(!wantPlay || !bgStarted){ muted = false; firstGesture(); setMuted(false); }
      else { setMuted(!muted); }
    });

    updateSoundUI();

    return {
      initFX: initFX,
      pop: pop,
      twinkle: twinkle,
      chime: chime,
      setMuted: setMuted,
      setVideoId: setVideoId
    };
  }

  window.BolzooAudio = { init: init };
})();
