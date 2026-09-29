/* Bolzoo · Small date ideas and messages to make the first invitation easier. */
(function(root, factory){
  var api = factory(root);
  if(typeof module === 'object' && module.exports) module.exports = api;
  if(root) root.BolzooDateIdeas = api;
})(typeof window !== 'undefined' ? window : globalThis, function(root){
  'use strict';

  var presets = Object.freeze([
    Object.freeze({
      id: 'coffee', title: 'Кофе, бас жаахан яриа', label: 'Кофенд урих', emoji: '☕',
      description: 'Дуртай кофегоо аваад, зөвхөн бие биедээ цаг гаргая.',
      note: 'Нэг аяга кофе, дуусахгүй яриа. Чамтай хамт суух тэр мөчийг хүлээж байна. ☕',
      theme: 'coral', template: 'letter'
    }),
    Object.freeze({
      id: 'picnic', title: 'Хоёулхнаа жижигхэн пикник', label: 'Гадаа уулзах', emoji: '🌿',
      description: 'Амттай зүйл, цэвэр агаар, хамтдаа өнгөрүүлэх тайван өдөр.',
      note: 'Амттай зүйлсээ аваад, цэвэр агаарт хамт сууя. Энэ өдрийн хамгийн гоё хэсэг нь чи байх болно. 🌿',
      theme: 'mint', template: 'dreamy'
    }),
    Object.freeze({
      id: 'cinema', title: 'Нэг кино, хоёр сэтгэгдэл', label: 'Кинонд урих', emoji: '🎬',
      description: 'Киногоо хамт сонгоод, дараа нь сэтгэгдлээ хуваалцъя.',
      note: 'Киногоо хамт сонгоод, дараа нь дуртай мөчөө ярилцъя. Хоёулаа кино үзэх үү? 🎬',
      theme: 'lavender', template: 'ticket'
    })
  ]);
  var activeCleanup = null;

  function findIdea(id){
    return presets.find(function(idea){ return idea.id === id; }) || null;
  }

  function init(options){
    if(activeCleanup) activeCleanup();
    options = options || {};
    var doc = root.document;
    if(!doc) return {destroy: function(){}};
    var pending = null;
    var pendingTrigger = null;
    var destroyed = false;
    var spotlight = doc.getElementById('ideaSpotlight');
    var noteField = doc.getElementById('customNote');
    var notePanel = doc.getElementById('noteIdeaConfirm');
    var noteStatus = doc.getElementById('noteIdeaStatus');
    var noteIdeas = doc.getElementById('noteIdeas');

    function status(message){
      if(noteStatus) noteStatus.textContent = message;
    }
    function isDateMode(){
      return !doc.body || !doc.body.hasAttribute('data-experience') ||
        doc.body.getAttribute('data-experience') === 'date';
    }
    function clearPending(){
      pending = null;
      pendingTrigger = null;
      if(notePanel) notePanel.hidden = true;
      var pendingText = doc.getElementById('pendingIdeaNote');
      if(pendingText) pendingText.textContent = '';
    }
    function renderSpotlight(idea){
      if(spotlight) spotlight.setAttribute('data-selected-idea', idea.id);
      [
        ['ideaSpotlightTitle', idea.title], ['ideaSpotlightNote', idea.note],
        ['ideaSpotlightEmoji', idea.emoji], ['ideaSpotlightDescription', idea.description]
      ].forEach(function(entry){
        var element = doc.getElementById(entry[0]);
        if(element) element.textContent = entry[1];
      });
    }
    function applyIdea(idea){
      if(!idea || typeof options.applyIdea !== 'function') return;
      clearPending();
      status('');
      options.applyIdea(idea);
    }
    function applyNote(idea){
      if(!isDateMode() || !idea || typeof options.applyNote !== 'function') return;
      clearPending();
      options.applyNote(idea.note);
      status('Зурвас нэмэгдлээ. Өөрийнхөөрөө засаж болно.');
      if(noteField) noteField.focus({preventScroll: true});
    }
    function selectNote(idea, trigger){
      if(!isDateMode() || !noteField || !idea) return;
      clearPending();
      if(noteField.value.trim() === idea.note){
        status('Энэ зурвас аль хэдийн сонгогдсон байна.');
        return;
      }
      if(!noteField.value.trim()){
        applyNote(idea);
        return;
      }
      // Existing writing is replaced only after a separate, explicit choice.
      if(!notePanel){
        status('Эхлээд бичсэн зурвасаа арилгаад, дахин сонгоорой.');
        return;
      }
      pending = idea;
      pendingTrigger = trigger;
      var pendingText = doc.getElementById('pendingIdeaNote');
      if(pendingText) pendingText.textContent = idea.note;
      notePanel.hidden = false;
      status('Бичсэн зурвасаа энэ санаагаар солих эсэхээ сонгоорой.');
      var confirm = doc.getElementById('confirmIdeaNote');
      if(confirm) confirm.focus({preventScroll: true});
    }
    function onClick(event){
      var target = event.target;
      if(!target || typeof target.closest !== 'function') return;
      var button = target.closest('button');
      if(!button || button.disabled) return;
      if(button.hasAttribute('data-date-idea')){
        applyIdea(findIdea(button.getAttribute('data-date-idea')));
      }else if(button.id === 'shuffleDateIdea'){
        var current = spotlight && spotlight.getAttribute('data-selected-idea');
        var alternatives = presets.filter(function(idea){ return idea.id !== current; });
        renderSpotlight(alternatives[Math.floor(Math.random() * alternatives.length)]);
      }else if(button.id === 'useSpotlightIdea'){
        applyIdea(findIdea(spotlight && spotlight.getAttribute('data-selected-idea')));
      }else if(button.hasAttribute('data-note-idea') && noteIdeas && noteIdeas.contains(button)){
        selectNote(findIdea(button.getAttribute('data-note-idea')), button);
      }else if(button.id === 'confirmIdeaNote'){
        if(!isDateMode()){
          clearPending();
          status('');
          return;
        }
        applyNote(pending);
      }else if(button.id === 'cancelIdeaNote'){
        var trigger = pendingTrigger;
        clearPending();
        status('Бичсэн зурвасыг хэвээр үлдээлээ.');
        if(trigger) trigger.focus({preventScroll: true});
      }else if(button.hasAttribute('data-experience-choice')){
        clearPending();
        status('');
      }
    }
    function onNoteInput(){
      if(!pending) return;
      clearPending();
      status('Зурвасаа заслаа. Санаа нэмэх бол дахин сонгоорой.');
    }

    if(noteStatus){
      noteStatus.setAttribute('role', 'status');
      noteStatus.setAttribute('aria-live', 'polite');
    }
    if(noteIdeas && !noteIdeas.querySelector('[data-note-idea]')){
      presets.forEach(function(idea){
        var button = doc.createElement('button');
        button.type = 'button';
        button.className = 'note-idea';
        button.setAttribute('data-note-idea', idea.id);
        button.textContent = idea.emoji + ' ' + idea.label;
        noteIdeas.appendChild(button);
      });
    }
    clearPending();
    renderSpotlight(findIdea(spotlight && spotlight.getAttribute('data-selected-idea')) || presets[0]);
    doc.addEventListener('click', onClick);
    if(noteField) noteField.addEventListener('input', onNoteInput);
    var observer = doc.body && typeof root.MutationObserver === 'function'
      ? new root.MutationObserver(function(){ clearPending(); status(''); }) : null;
    if(observer) observer.observe(doc.body, {attributes: true, attributeFilter: ['data-experience']});

    function destroy(){
      if(destroyed) return;
      destroyed = true;
      doc.removeEventListener('click', onClick);
      if(noteField) noteField.removeEventListener('input', onNoteInput);
      if(observer) observer.disconnect();
      clearPending();
      if(activeCleanup === destroy) activeCleanup = null;
    }
    activeCleanup = destroy;
    return {destroy: destroy};
  }

  return Object.freeze({presets: presets, init: init});
});
