(function(){
  "use strict";

  function noop(){}

  function idea(emoji, title, text, meta){
    return {
      emoji: emoji,
      title: title,
      text: text,
      meta: meta
    };
  }

  function wrappedIndex(index, total){
    return ((index % total) + total) % total;
  }

  var ROOM_QUESTIONS = [
    'Анхны болзоондоо юу хийвэл хамгийн гоё вэ?',
    'Намайг 3 үгээр тодорхойлбол?',
    'Чи coffee date уу, movie date уу?',
    'Хамт нэг өдөр аялбал хаашаа явах вэ?',
    'Чамд хамгийн cute санагддаг жижиг gesture юу вэ?',
    'Бидний playlist-д заавал байх нэг дуу юу вэ?',
    'Хоёулаа 10 минут утасгүй суувал юу яримаар байна?',
    'Чиний perfect date ямар үнэр, амт, хөгжимтэй вэ?',
    'Намайг инээлгэх хамгийн амархан арга юу вэ?',
    'Дараагийн болзоондоо заавал турших зүйл юу вэ?'
  ];

  var IDEA_BANK = {
    romantic: [
      idea(
        '☕',
        'Coffee walk',
        'Кофе аваад 20 минут алхаж, дуртай дуугаа сонсгоно.',
        '30-45 минут · тайван'
      ),
      idea(
        '🌆',
        'Sunset check',
        'Нар жаргах үед уулзаад өнөөдрийн гоё мөчөө хуваалцана.',
        '45 минут · романтик'
      ),
      idea(
        '💌',
        'Mini letter swap',
        'Уулзахаасаа өмнө 3 мөр бичээд, болзоон дээрээ уншиж өгнө.',
        '20 минут · дурсамжтай'
      )
    ],
    funny: [
      idea(
        '📸',
        'Random selfie mission',
        '3 өөр pose-оор зураг аваад хамгийн хөгжилтэйг нь story болгоно.',
        '20 минут · инээдтэй'
      ),
      idea(
        '🍟',
        'Blind snack rating',
        'Нэг нэгэндээ жижиг snack сонгож өгөөд 10 оноогоор үнэлнэ.',
        '30 минут · хөнгөн'
      ),
      idea(
        '🎤',
        'One-song karaoke',
        'Машинд эсвэл алхахдаа нэг дууг хамт дуулж дуусгана.',
        '5 минут · хөгжилтэй'
      )
    ],
    calm: [
      idea(
        '🌿',
        'Quiet walk',
        '10 минут хамт алхаж, хамгийн түрүүнд бодогдсоноо ярилцана.',
        '30 минут · тайван'
      ),
      idea(
        '🍵',
        'Tea pause',
        'Дуу намуутай газар цай уугаад талархсан 3 зүйл хэлнэ.',
        '45 минут · дулаан'
      ),
      idea(
        '🧩',
        'Tiny promise',
        'Дараа долоо хоногт хамт хийх нэг жижиг зүйлээ тохирно.',
        '15 минут · ойр'
      )
    ],
    adventure: [
      idea(
        '🗺',
        'Map roulette',
        'Maps дээр ойрхон нэг газар сонгоод хамт очиж үзнэ.',
        '45-60 минут · шинэ'
      ),
      idea(
        '🎯',
        'Two-choice date',
        'Нэг нь газар, нөгөө нь идэх зүйлээ сонгоод шууд хөдөлнө.',
        '60 минут · spontaneous'
      ),
      idea(
        '🛍',
        'Tiny gift hunt',
        '5,000₮-өөс доош жижиг зүйл нэг нэгэндээ олж өгнө.',
        '30 минут · playful'
      )
    ]
  };

  var CHALLENGES = [
    'Нэг нэгэндээ өнөөдөр хамгийн их таалагдсан зүйлээ хэлнэ.',
    '10 минут утсаа доош нь харуулаад зөвхөн ярилцана.',
    'Нэг нэгэндээ дуртай дуугаа сонсгоно.',
    'Хамт авах selfie-гээ 3 өөр mood-оор дарна.',
    'Дараагийн уулзалтынхаа нэг жижиг plan-ийг сонгоно.',
    'Нөгөөдөө нэг гэнэтийн магтаал хэлнэ.',
    'Хоёулаа нэг амттан хувааж иднэ.',
    'Өнөөдрийн болзоонд нэр өгнө.'
  ];

  function init(options){
    var opts = options || {};
    var $ = opts.$ || function(id){ return document.getElementById(id); };
    var state = opts.state;
    var setDoneMessage = opts.setDoneMessage || noop;
    var pop = opts.pop || noop;
    var twinkle = opts.twinkle || noop;
    var chime = opts.chime || noop;
    var root = $('dateRoom') || document;

    function all(selector){
      return root.querySelectorAll(selector);
    }

    function text(id, value){
      var node = $(id);
      if(node){ node.textContent = value; }
    }

    function on(id, eventName, handler){
      var node = $(id);
      if(node){ node.addEventListener(eventName, handler); }
    }

    function setRoomTab(tab){
      state.roomTab = tab;
      var tabs = all('.room-tab');
      var panels = all('.room-panel');

      for(var i = 0; i < tabs.length; i++){
        var onTab = tabs[i].getAttribute('data-room-tab') === tab;
        tabs[i].classList.toggle('on', onTab);
        tabs[i].setAttribute('aria-selected', onTab ? 'true' : 'false');
      }

      for(var j = 0; j < panels.length; j++){
        var onPanel = panels[j].getAttribute('data-room-panel') === tab;
        panels[j].classList.toggle('on', onPanel);
      }
    }

    function renderRoomTitle(){
      text('roomTitle', 'Уулзсаныхаа дараа хамт хийх жижиг тоглоом');
    }

    function renderQuestion(){
      var total = ROOM_QUESTIONS.length;
      var index = wrappedIndex(state.questionIndex, total);

      state.questionIndex = index;
      text('questionCount', (index + 1) + '/' + total);
      text('questionText', ROOM_QUESTIONS[index]);
    }

    function currentIdea(){
      var list = IDEA_BANK[state.dateMood] || IDEA_BANK.romantic;
      var index = wrappedIndex(state.ideaIndex, list.length);

      state.ideaIndex = index;
      return list[index];
    }

    function renderMoodChoices(){
      var buttons = all('#moodChoices .choice-btn');

      for(var i = 0; i < buttons.length; i++){
        var isActive = buttons[i].getAttribute('data-mood') === state.dateMood;
        buttons[i].classList.toggle('on', isActive);
      }
    }

    function renderIdea(){
      var activeIdea;

      renderMoodChoices();
      activeIdea = currentIdea();
      text('ideaEmoji', activeIdea.emoji);
      text('ideaTitle', activeIdea.title);
      text('ideaText', activeIdea.text);
      text('ideaMeta', activeIdea.meta);
    }

    function renderChallenge(){
      var total = CHALLENGES.length;
      var index = wrappedIndex(state.challengeIndex, total);

      state.challengeIndex = index;
      text('challengeCount', (index + 1) + '/' + total);
      text('challengeText', CHALLENGES[index]);
    }

    function spinChallenge(){
      var wheel = $('challengeWheel');
      var next = Math.floor(Math.random() * CHALLENGES.length);

      if(next === state.challengeIndex){
        next = (next + 1) % CHALLENGES.length;
      }

      state.challengeIndex = next;
      state.wheelRotation += 720 + Math.floor(Math.random() * 240) + next * 18;

      if(wheel){
        wheel.style.transform = 'rotate(' + state.wheelRotation + 'deg)';
      }

      renderChallenge();
      pop('G5');
    }

    function defaultMood(){
      if(state.kind === 'walk'){ return 'calm'; }
      if(state.kind === 'surprise'){ return 'adventure'; }
      if(state.kind === 'movie'){ return 'funny'; }
      return 'romantic';
    }

    function reset(){
      var wheel = $('challengeWheel');

      state.roomTab = 'question';
      state.questionIndex = 0;
      state.dateMood = defaultMood();
      state.ideaIndex = 0;
      state.challengeIndex = 0;
      state.wheelRotation = 0;

      if(wheel){
        wheel.style.transform = 'rotate(0deg)';
      }

      renderRoomTitle();
      renderQuestion();
      renderIdea();
      renderChallenge();
      setRoomTab('question');
    }

    function bindTabs(){
      var tabs = all('.room-tab');

      for(var i = 0; i < tabs.length; i++){
        tabs[i].addEventListener('click', function(){
          setRoomTab(this.getAttribute('data-room-tab'));
          pop('E5');
        });
      }
    }

    function bindQuestions(){
      on('prevQuestion', 'click', function(){
        state.questionIndex--;
        renderQuestion();
        pop('D5');
      });

      on('nextQuestion', 'click', function(){
        state.questionIndex++;
        renderQuestion();
        pop('E5');
      });
    }

    function bindIdeas(){
      var moods = all('#moodChoices .choice-btn');

      for(var i = 0; i < moods.length; i++){
        moods[i].addEventListener('click', function(){
          state.dateMood = this.getAttribute('data-mood');
          state.ideaIndex = 0;
          renderIdea();
          twinkle();
        });
      }

      on('ideaShuffle', 'click', function(){
        state.ideaIndex++;
        renderIdea();
        pop('F5');
      });

      on('ideaUse', 'click', function(){
        var activeIdea = currentIdea();

        setDoneMessage(
          activeIdea.title + ' сонгогдлоо · ' + activeIdea.meta + ' 💗'
        );
        setRoomTab('challenge');
        chime();
      });
    }

    function bindChallenges(){
      on('challengeSkip', 'click', function(){
        state.challengeIndex++;
        renderChallenge();
        pop('D5');
      });

      on('spinChallenge', 'click', spinChallenge);
    }

    if(!state){
      return { reset: noop, setTab: noop };
    }

    bindTabs();
    bindQuestions();
    bindIdeas();
    bindChallenges();
    reset();

    return {
      reset: reset,
      setTab: setRoomTab
    };
  }

  window.BolzooDateRoom = {
    init: init
  };
})();
