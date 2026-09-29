(function (root) {
  'use strict';
  var d = root.document;
  var catalog = root.BolzooMissionCatalog;
  var $ = function (id) { return d.getElementById(id); };
  function element(tag, className, text) { var node = d.createElement(tag); if (className) node.className = className; if (text !== undefined) node.textContent = text; return node; }
  function hide(id, hidden) { if ($(id)) $(id).hidden = hidden; }
  function text(id, value) { if ($(id)) $(id).textContent = value == null ? '' : value; }
  function ulaanbaatarTime(iso) {
    if(!iso)return null;
    var value=new Date(iso);if(!Number.isFinite(value.getTime()))return null;
    var local=new Date(value.getTime()+8*60*60*1000);
    var pad=function(number){return String(number).padStart(2,'0');};
    return {date:local.getUTCFullYear()+'.'+pad(local.getUTCMonth()+1)+'.'+pad(local.getUTCDate()),
      text:local.getUTCFullYear()+' оны '+(local.getUTCMonth()+1)+' сарын '+local.getUTCDate(),
      time:pad(local.getUTCHours())+':'+pad(local.getUTCMinutes())};
  }
  var environmentNames = {indoor:'Дотор',outdoor:'Гадаа',home:'Гэртээ',online:'Хамт / онлайн'};

  function initIdeas() {
    var params = new URLSearchParams(root.location.search);
    var invite = params.get('invite');
    var selected = null;
    var preset = '';
    var visibleCount = 3;
    if(invite){
      var journey=d.querySelector('.journey-strip');journey.setAttribute('aria-label','Болзооны дараалал');
      ['Санаа сонгох','Хоёулаа тохирох','Хамт хийж дурсах'].forEach(function(label,i){var item=journey.children[i];item.replaceChildren(element('span','','0'+(i+1)),d.createTextNode(' '+label));});
    }
    function ideaLink(id) {
      return invite ? '/date-plan.html?invite='+encodeURIComponent(invite)+'&idea='+encodeURIComponent(id) : '/create.html?idea='+encodeURIComponent(id)+'&quick=1';
    }
    function showDetail(id) {
      var idea = catalog.get(id); if (!idea) return;
      selected = id;
      d.querySelectorAll('[data-idea-id]').forEach(function (card) { card.dataset.selected = String(card.dataset.ideaId === id); });
      var panel = $('idea-detail'); panel.replaceChildren();
      var heading = element('div','detail-heading');
      var emoji = element('span','idea-emoji',idea.emoji); emoji.setAttribute('aria-hidden','true'); heading.appendChild(emoji);
      var titleWrap = element('div'); var title = element('h2','',idea.title); title.id = 'detail-title'; titleWrap.appendChild(title); titleWrap.appendChild(element('p','muted',idea.description)); heading.appendChild(titleWrap); panel.appendChild(heading);
      var list = element('ol','detail-steps');
      idea.steps.forEach(function(step,i){var li=element('li');li.appendChild(element('span','step-number','0'+(i+1)));li.appendChild(element('h3','',step.title));li.appendChild(element('p','',step.description));list.appendChild(li);});panel.appendChild(list);
      panel.appendChild(element('p','detail-note','Бэлтгэл · '+idea.preparation));
      panel.appendChild(element('p','detail-note','Өөр хувилбар · '+idea.fallback));
      var cta = element('div','detail-cta'); cta.appendChild(element('p','',idea.notice+' Зардлын тайлбар нь хоёр хүний төлөвлөлтөд зориулсан.'));
      var link = element('a','button','Энэ загварыг ашиглах');
      link.href = ideaLink(id);
      cta.appendChild(link);panel.appendChild(cta);panel.hidden=false;panel.focus({preventScroll:true});if (panel.scrollIntoView) panel.scrollIntoView({behavior:'smooth',block:'start'});
    }
    function render() {
      var form = $('idea-filters');
      var results = catalog.getSuggestions(preset,{duration:form.elements.duration.value,budget:form.elements.budget.value,environment:form.elements.environment.value});
      var visible = results.slice(0,visibleCount);
      d.querySelectorAll('[data-idea-preset]').forEach(function(button){button.setAttribute('aria-pressed',String(button.dataset.ideaPreset===preset));});
      var grid = $('idea-grid'); grid.replaceChildren();
      visible.forEach(function(idea){
        var card=element('article','idea-card');card.dataset.ideaId=idea.id;card.dataset.selected=String(selected===idea.id);
        var top=element('div','idea-card-top');var emoji=element('span','idea-emoji',idea.emoji);emoji.setAttribute('aria-hidden','true');top.appendChild(emoji);top.appendChild(element('span','idea-category',environmentNames[idea.environment]));card.appendChild(top);
        card.appendChild(element('h3','',idea.title));card.appendChild(element('p','idea-description',idea.description));
        var meta=element('div','idea-meta');meta.appendChild(element('span','',idea.duration.label));meta.appendChild(element('span','',idea.budget.category==='free'?'Нэмэлт худалдан авалтгүй':idea.budget.category==='low'?'Бага зардлаар':'Төсвөө тохирно'));card.appendChild(meta);
        var link=element('a','button idea-use','Энэ загварыг ашиглах');link.href=ideaLink(idea.id);link.setAttribute('aria-label',idea.title+' — энэ загварыг ашиглах');card.appendChild(link);
        var button=element('button','idea-details-button','Дэлгэрэнгүй');button.type='button';button.setAttribute('aria-label',idea.title+' — гурван алхмыг харах');button.setAttribute('aria-controls','idea-detail');button.addEventListener('click',function(){showDetail(idea.id);});card.appendChild(button);grid.appendChild(card);
      });
      text('idea-count',visible.length+' санаа');hide('ideas-empty',results.length>0);hide('show-more',visible.length>=results.length);
    }
    function resetResults(){visibleCount=3;hide('idea-detail',true);selected=null;render();}
    catalog.quickPresets.forEach(function(item){
      var button=element('button','quick-preset',item.label);button.type='button';button.dataset.ideaPreset=item.id;button.setAttribute('aria-pressed','false');
      button.addEventListener('click',function(){preset=preset===item.id?'':item.id;$('idea-filters').reset();resetResults();});$('idea-presets').appendChild(button);
    });
    $('idea-filters').addEventListener('change',resetResults);
    $('idea-filters').addEventListener('submit',function(event){event.preventDefault();});
    $('clear-idea-filters').addEventListener('click',function(){preset='';$('idea-filters').reset();resetResults();});
    $('show-more').addEventListener('click',function(){visibleCount+=3;render();});
    render(); if (catalog.get(params.get('idea'))) showDetail(params.get('idea'));
    if(root.BolzooDatePlanAPI){
      try{
        var joined=root.BolzooDatePlanAPI.listJoined().filter(function(item){return item&&/^[A-Za-z0-9_-]{8,64}$/.test(item.invite_id);});
        joined.forEach(function(item,i){var link=element('a','button button-outline','Миний оролцсон болзоо '+(i+1)+' ↗');link.href='/date-plan.html?invite='+encodeURIComponent(item.invite_id);$('joined-plan-links').appendChild(link);});hide('joined-plans',!joined.length);
      }catch(_){}
    }
  }

  function initPlan() {
    var api = root.BolzooDatePlanAPI;
    var params = new URLSearchParams(root.location.search);
    var invite = params.get('invite');
    var plan = null;
    var busy = false;
    var conflict = false;
    var editorOpen = false;
    var editorDirty = false;
    var memoryDirty = false;
    var confirmedAction = null;
    var pendingJoin = false;
    var selectedIdea = catalog.get(params.get('idea')) || catalog.ideas[0];
    var states = {proposed:'Шинэ санал · хариу хүлээж байна',agreed:'Хоёулаа тохирлоо',in_progress:'Болзоо үргэлжилж байна',ended:'Болзооны дурсамж',declined:'Энэ удаа боломжгүй',cancelled:'Төлөвлөгөөг цуцалсан'};
    var outcomeNames = {todo:'Тэмдэглээгүй',done:'Хийлээ',skipped:'Алгассан',adapted:'Өөрөөр хийсэн'};
    function status(message) { text('plan-message',message);hide('plan-message',!message); }
    function clearError() { hide('plan-error',true);hide('retry-load',true);hide('reload-conflict',true); }
    function showError(error,retryLoad) {
      var isConflict = error.status === 409 && !/^claim_/.test(error.code || '');
      if (isConflict) conflict=true;
      text('plan-error-text',isConflict ? 'Төлөвлөгөөнд өөр өөрчлөлт оржээ. Бичсэн зүйл тань хэвээрээ. Шинэ хувилбарыг үзээд дахин шийдээрэй.' : error.message || 'Алдаа гарлаа. Дахин оролдоорой.');
      hide('plan-error',false);hide('reload-conflict',!isConflict);hide('retry-load',!retryLoad||isConflict);
    }
    function setBusy(value) {
      busy=value;
      $('main').setAttribute('aria-busy',String(value));
      d.querySelectorAll('#main button,#main input,#main textarea,#main select').forEach(function(control){
        if (value) {control.dataset.wasDisabled=String(control.disabled);control.disabled=true;}
        else if ('wasDisabled' in control.dataset) {control.disabled=control.dataset.wasDisabled==='true';delete control.dataset.wasDisabled;}
      });
      if(!value&&plan&&editorOpen&&['ended','cancelled','declined','in_progress'].includes(plan.state))$('save-plan').disabled=true;
    }
    function localInput(iso) {
      if (!iso) return '';
      var value = new Date(iso); if (!Number.isFinite(value.getTime())) return '';
      return new Date(value.getTime()+8*60*60*1000).toISOString().slice(0,16);
    }
    function formattedTime(iso) {
      var parts=ulaanbaatarTime(iso);
      return parts?parts.date+' · '+parts.time+' · УБ':'Хамт тохирно';
    }
    function editorValues(source) {
      var idea=catalog.get(source.template_id)||selectedIdea;
      if(source.template_id&&!catalog.get(source.template_id)){
        if(!Array.from($('plan-template').options).some(function(option){return option.value===source.template_id;})){var retired=element('option','',source.title+' · өмнөх санаа');retired.value=source.template_id;$('plan-template').appendChild(retired);}
        $('plan-template').value=source.template_id;
      }else $('plan-template').value=idea.id;
      $('plan-title').value=source.title||idea.title;
      $('plan-time').value=localInput(source.scheduled_at);
      $('plan-location').value=source.location||'';
      $('plan-budget').value=source.budget||'';
      (source.steps||idea.steps.map(function(step){return {id:step.id,text:step.title+' — '+step.description};})).forEach(function(step,i){$('plan-step-'+i).value=step.text;});
    }
    function openEditor(source,keepDraft) {
      editorOpen=true;
      if (!keepDraft) {editorValues(source||{template_id:selectedIdea.id});editorDirty=false;}
      hide('plan-editor',false);hide('close-editor',!plan);
      text('save-plan',plan?'Шинэ санал хадгалах →':'Төлөвлөгөө үүсгэх →');
      text('editor-copy',plan?'Цаг, газар, төсөв эсвэл алхмууд өөрчлөгдвөл хоёулаа шинэ хувилбарыг дахин зөвшөөрнө.':'Өдөр, газар, төсвөө хоёулаа тохирно. Үүсгэсний дараа оролцох холбоосоо нөгөө хүндээ өгнө.');
    }
    function showAccess(canClaim,copy) {
      hide('plan-loading',true);hide('plan-access',false);hide('claim-plan',!canClaim);hide('access-home',canClaim);
      text('access-title',canClaim?'Энэ болзоонд хамт оролцоё':'Энэ болзооны оролцох эрх хэрэгтэй');
      text('access-copy',copy||(canClaim?'Оролцох эрхээ энэ browser дээр хадгалсны дараа төлөвлөгөөг хамт засаж, зөвшөөрч болно. Холбоос нэг хүнд зориулагдсан.':'Илгээгчээс оролцох холбоосоо аваарай. Илгээгч бол урилгаа үүсгэсэн browser-оор нээх эсвэл Миний урилгууд дээр эрхээ сэргээнэ.'));
    }
    function renderSteps() {
      var list=$('plan-steps');list.replaceChildren();
      var role=plan.role;var other=role==='creator'?'partner':'creator';
      var own=0;
      plan.steps.forEach(function(step,i){
        var outcomes=step.outcomes||{};var value=outcomes[role]||'todo';if(value!=='todo')own++;
        var card=element('article','mission-step');card.appendChild(element('span','step-number','0'+(i+1)));
        var body=element('div','mission-step-body');body.appendChild(element('h3','',step.text));
        if(plan.state==='in_progress'){
          var controls=element('div','outcome-buttons');controls.setAttribute('role','group');controls.setAttribute('aria-label',(i+1)+'-р алхмын миний тэмдэглэгээ');
          [['done','Хийлээ'],['skipped','Алгасъя'],['adapted','Өөрөөр хийсэн']].forEach(function(item){var button=element('button','',item[1]);button.type='button';button.dataset.stepId=step.id;button.dataset.outcome=item[0];button.setAttribute('aria-pressed',String(value===item[0]));button.addEventListener('click',function(){if(value!==item[0])run('outcome',{step_id:step.id,outcome:item[0]});});controls.appendChild(button);});
          if(value!=='todo'){var undo=element('button','','Буцаах');undo.type='button';undo.dataset.stepId=step.id;undo.dataset.outcome='todo';undo.addEventListener('click',function(){run('outcome',{step_id:step.id,outcome:'todo'});});controls.appendChild(undo);}body.appendChild(controls);
        }
        var stepStatus='Миний тэмдэглэгээ: '+(outcomeNames[value]||outcomeNames.todo);
        if(plan.partner_claimed)stepStatus+=' · Нөгөө хүнийх: '+(outcomeNames[outcomes[other]]||outcomeNames.todo);
        body.appendChild(element('p','step-status',stepStatus));card.appendChild(body);list.appendChild(card);
      });
      text('steps-progress',own+' / 3 тэмдэглэсэн');
      text('steps-guidance',plan.state==='proposed'?'Эхлээд хоёулаа төлөвлөгөөгөө зөвшөөрнө.':plan.state==='agreed'?'Бэлэн болсон үедээ болзоогоо эхлүүлээд тэмдэглэж болно.':'Хүн бүр өөрийн тэмдэглэгээг хадгална. Алгасаж, өөрчилж болно.');
    }
    function render() {
      if(!plan)return;
      hide('plan-loading',true);hide('plan-access',true);hide('plan-content',false);
      var agreed=plan.state==='agreed';var active=plan.state==='in_progress';var ended=plan.state==='ended';var proposed=plan.state==='proposed';var terminal=ended||plan.state==='cancelled'||plan.state==='declined';
      var idea=catalog.get(plan.template_id);var accepted=plan.accepted||{};var mine=accepted[plan.role]===plan.revision;var other=accepted[plan.role==='creator'?'partner':'creator']===plan.revision;
      text('plan-state',states[plan.state]||plan.state);text('ticket-title',plan.title);text('ticket-emoji',idea?idea.emoji:'♡');
      text('ticket-people',[plan.senderName,plan.recipientName].filter(Boolean).join(' + ')||'Хоёр хүний жижиг төлөвлөгөө');
      text('ticket-time',formattedTime(plan.scheduled_at));text('ticket-location',plan.location||'Газар тохироогүй');text('ticket-budget',plan.budget||'Төсвөө хамт тохирно');
      text('ticket-consent',ended?'Өнөөдрийн болзоог өндөрлөсөн':agreed||active?'Хоёулаа тохирлоо':proposed?'Хоёр талын зөвшөөрөл хүлээж байна':states[plan.state]);
      text('ticket-revision','Хувилбар '+plan.revision);text('ticket-notice',idea&&idea.id==='movie-and-talk'?idea.notice:'');
      hide('agreement-panel',terminal||active);
      text('agreement-title',agreed?'Хоёулаа тохирлоо':'Хоёулаа тохиръё');
      text('agreement-copy',mine?(other?'Энэ хувилбар дээр хоёр тал зөвшөөрсөн. Өөрчилбөл дахин тохиролцоно.':'Та энэ хувилбарыг зөвшөөрсөн. Нөгөө хүний хариу хүлээж байна.'):'Нэр, өдөр, газар, төсөв, хамт хийх зүйлсээ хараад энэ хувилбарыг зөвшөөрөөрэй.');
      hide('accept-plan',!proposed||mine);hide('edit-plan',!proposed&&!agreed);hide('decline-plan',!proposed&&!agreed);
      var link=plan.role==='creator'&&!plan.partner_claimed?api.joinLink(invite):null;
      var expired=plan.claim_expires_at&&new Date(plan.claim_expires_at).getTime()<=Date.now();
      hide('share-plan',!link||expired);hide('manual-copy-wrap',true);$('manual-copy').value='';
      hide('rotate-claim',plan.role!=='creator'||(!proposed&&!agreed));
      text('claim-expiry',plan.claim_expires_at?'Холбоосын хугацаа: '+formattedTime(plan.claim_expires_at):'');
      if(plan.role==='creator'&&!plan.partner_claimed&&!link)text('agreement-copy','Оролцох холбоос энэ browser дээр хадгалагдаагүй байна. Төлөвлөгөөг үүсгэсэн browser-оор холбоосоо хуулаарай.');
      if(plan.role==='creator'&&!plan.partner_claimed&&expired)text('agreement-copy','Оролцох холбоосын хугацаа дуусжээ. Доорх товчоор шинэ холбоос гаргаж болно.');
      hide('start-panel',!agreed);hide('end-panel',!active);hide('memory-panel',!ended);hide('next-date',!terminal);hide('cancel-plan',terminal);
      hide('download-ticket',!agreed&&!active&&!ended);hide('download-story',!agreed&&!active&&!ended);
      if(!memoryDirty)$('memory-text').value=plan.my_memory||'';
      $('original-invite').href='/bolzoo.html?id='+encodeURIComponent(invite);
      renderSteps();
      if((terminal||active)&&editorOpen)text('editor-copy','Төлөвлөгөөний төлөв өөрчлөгдсөн тул одоо засвар хадгалах боломжгүй. Таны бичсэн зүйл энд хэвээрээ; хүсвэл хуулж авч болно.');
    }
    async function load(options) {
      if(busy)return;options=options||{};clearError();setBusy(true);
      try{
        plan=await api.get(invite);conflict=false;render();
        if(options.review){status(editorOpen||memoryDirty?'Шинэ хувилбарыг ачааллаа. Таны бичсэн зүйл хадгалагдаагүй хэвээр байна. Төлөвлөгөөг нягтлаад дахин хадгалаарай.':'Шинэ хувилбарыг ачааллаа. Өөрчлөлтийг хараад дахин шийдээрэй.');}
      }catch(error){
        if(error.status===404&&error.code==='plan_not_found'&&api.hasOwner(invite)){
          plan=null;hide('plan-loading',true);hide('plan-access',true);hide('plan-content',true);openEditor(null,editorDirty);
        }else if(error.status===403||error.status===401){plan=null;hide('plan-content',true);hide('plan-editor',true);editorOpen=false;showAccess(pendingJoin);showError(error,false);}
        else {hide('plan-loading',true);showError(error,true);}
      }finally{setBusy(false);}
    }
    async function run(action,fields) {
      if(busy)return false;
      if(conflict){showError({status:409},false);return false;}
      clearError();status('');setBusy(true);
      try{
        var data=Object.assign({},fields||{});
        if(plan){data.expected_version=plan.version;if(action==='accept')data.expected_revision=plan.revision;}
        plan=await api.mutate(invite,action,data);
        if(action==='create'||action==='propose'){editorDirty=false;editorOpen=false;hide('plan-editor',true);}
        if(action==='memory')memoryDirty=false;
        hide('confirm-panel',true);confirmedAction=null;render();
        status(action==='create'?'Төлөвлөгөө хадгалагдлаа. Оролцох холбоосоо хуулаад нөгөө хүндээ өгнө үү.':action==='propose'?'Шинэ санал хадгалагдлаа. Хоёулаа энэ хувилбарыг дахин зөвшөөрнө.':action==='memory'?'Таны хувийн тэмдэглэл хадгалагдлаа.':action==='accept'?'Таны зөвшөөрөл хадгалагдлаа.':action==='outcome'?'Таны тэмдэглэгээ хадгалагдлаа.':action==='start'?'Болзоо эхэллээ. Хамтдаа тухтай байгаарай.':action==='end'?'Өнөөдрийн болзоог өндөрлөлөө. Хүсвэл өөртөө дурсамж үлдээгээрэй.':'Өөрчлөлт хадгалагдлаа.');
        return true;
      }catch(error){
        if(error.status===403||error.status===401){plan=null;hide('plan-content',true);hide('plan-editor',true);editorOpen=false;showAccess(pendingJoin);}
        showError(error,false);return false;
      }finally{setBusy(false);}
    }
    function proposal() {
      var date=$('plan-time').value;
      var iso=date?new Date(date+'+08:00'):null;
      if(iso&&!Number.isFinite(iso.getTime()))throw new Error('Өдөр, цагаа дахин шалгаарай.');
      return {template_id:$('plan-template').value,title:$('plan-title').value.trim(),scheduled_at:iso?iso.toISOString():null,location:$('plan-location').value.trim(),budget:$('plan-budget').value.trim(),steps:['before','together','after'].map(function(id,i){return {id:id,text:$('plan-step-'+i).value.trim()};})};
    }
    function confirm(action,copy) {if(busy)return;confirmedAction=action;text('confirm-copy',copy);hide('confirm-panel',false);$('confirm-action').focus();}
    catalog.ideas.forEach(function(idea){var option=element('option','',idea.emoji+' '+idea.title);option.value=idea.id;$('plan-template').appendChild(option);});
    text('timezone-label','Улаанбаатарын цаг · UTC+8');
    $('plan-form').addEventListener('input',function(){editorDirty=true;});
    $('plan-template').addEventListener('change',function(){
      var idea=catalog.get(this.value);if(!idea)return;
      selectedIdea=idea;$('plan-title').value=idea.title;idea.steps.forEach(function(step,i){$('plan-step-'+i).value=step.title+' — '+step.description;});editorDirty=true;
    });
    $('plan-form').addEventListener('submit',function(event){event.preventDefault();if(busy)return;if(!$('plan-form').reportValidity())return;try{run(plan?'propose':'create',proposal());}catch(error){showError(error,false);}});
    $('close-editor').addEventListener('click',function(){hide('plan-editor',true);editorOpen=false;});
    $('edit-plan').addEventListener('click',function(){openEditor(plan,editorDirty);$('plan-title').focus();});
    $('accept-plan').addEventListener('click',function(){run('accept');});
    $('start-plan').addEventListener('click',function(){run('start');});
    $('end-plan').addEventListener('click',function(){confirm('end','Өнөөдрийн болзоог өндөрлөх үү? Бүх алхмыг хийх шаардлагагүй. Өндөрлөсний дараа хувийн дурсамжаа хадгалж болно.');});
    $('decline-plan').addEventListener('click',function(){confirm('decline','Энэ удаа боломжгүй гэж тэмдэглэх үү? Энэ төлөвлөгөө хаагдана. Дараа шинэ урилгаар дахин төлөвлөж болно.');});
    $('cancel-plan').addEventListener('click',function(){confirm('cancel','Энэ төлөвлөгөөг цуцлах уу? Хоёр талд цуцалсан гэж харагдана. Үйлчилгээний захиалга тусдаа тул эндээс цуцлагдахгүй.');});
    $('rotate-claim').addEventListener('click',function(){confirm('rotate_claim','Шинэ холбоос гаргавал өмнөх оролцогчийн эрх, зөвшөөрөл цуцлагдана. Нөгөө хүн шинэ холбоосоор орж, төлөвлөгөөг дахин зөвшөөрөх хэрэгтэй. Үргэлжлүүлэх үү?');});
    $('confirm-action').addEventListener('click',function(){if(confirmedAction)run(confirmedAction);});
    $('dismiss-confirm').addEventListener('click',function(){hide('confirm-panel',true);confirmedAction=null;});
    $('memory-text').addEventListener('input',function(){memoryDirty=true;});
    $('memory-form').addEventListener('submit',function(event){event.preventDefault();run('memory',{text:$('memory-text').value.trim()});});
    $('refresh-plan').addEventListener('click',function(){load({review:editorDirty||memoryDirty});});
    $('retry-load').addEventListener('click',function(){load();});
    $('reload-conflict').addEventListener('click',function(){load({review:true});});
    $('claim-plan').addEventListener('click',async function(){
      if(busy)return;clearError();setBusy(true);
      try{plan=await api.claim(invite);pendingJoin=false;render();status('Оролцох эрхээ энэ browser дээр хадгаллаа. Төлөвлөгөөг хараад тохиролцоорой.');}
      catch(error){showError(error,false);}finally{setBusy(false);}
    });
    $('copy-join').addEventListener('click',async function(){
      if(busy)return;clearError();var link=api.joinLink(invite);if(!link){showError(new Error('Энэ browser дээр оролцох холбоос олдсонгүй. Төлөвлөгөөг үүсгэсэн browser-оор нээгээрэй.'),false);return;}
      try{if(!root.navigator.clipboard||!root.navigator.clipboard.writeText)throw new Error('manual');await root.navigator.clipboard.writeText(link);status('Оролцох холбоос хуулагдлаа. Зөвхөн хамт болзох хүндээ илгээгээрэй.');}
      catch(_){$('manual-copy').value=link;hide('manual-copy-wrap',false);$('manual-copy').focus();$('manual-copy').select();status('Доорх холбоосыг сонгоод өөрөө хуулаарай.');}
    });
    async function download(mode) {
      if(busy||!plan)return;clearError();
      if(!root.BolzooTicket||!root.BolzooTicket.save){showError(new Error('Зураг үүсгэх хэрэгсэл ачаалагдсангүй. Хуудсыг дахин ачаалаад оролдоорой.'),false);return;}
      setBusy(true);
      try{
        var date=ulaanbaatarTime(plan.scheduled_at);
        var data={mode:mode,statusText:plan.state==='ended'?'БОЛЗООНЫ ДУРСАМЖ':'ХОЁУЛАА ТОХИРЛОО'};
        if(mode==='card')Object.assign(data,{dateText:date?date.text:'Өдрөө тохирно',dateDots:date?date.date:'Хамтдаа',time:date?date.time+' · УБ':'Цагаа тохирно',kindTicket:plan.title,ticketNo:String(plan.id||'').slice(0,8).toUpperCase(),locationName:plan.location||'Газар тохироогүй',subtitle:plan.state==='ended'?'Бидний болзооны дурсамж':'Хоёулаа тохирсон төлөвлөгөө'});
        await root.BolzooTicket.save(data);status(mode==='story'?'Хувийн нэр, өдөр, газар, холбоосгүй зураг бэлэн боллоо.':'Тикетийн зураг бэлэн боллоо. Энэ нь үйлчилгээний тасалбар биш.');
      }catch(_){showError(new Error('Тикетийн зургийг үүсгэж чадсангүй. Дахин оролдоорой.'),false);}finally{setBusy(false);}
    }
    $('download-ticket').addEventListener('click',function(){download('card');});
    $('download-story').addEventListener('click',function(){download('story');});
    root.addEventListener('beforeunload',function(event){if(editorDirty||memoryDirty){event.preventDefault();event.returnValue='';}});
    try{
      pendingJoin=api.captureJoin(invite);
      if(!invite||!/^[A-Za-z0-9_-]{8,64}$/.test(invite)){showAccess(false,'Урилгын холбоос дутуу байна. Миний урилгууд дээрээс болзооны төлөвлөгөөгөө нээгээрэй.');return;}
      if(pendingJoin&&!api.hasOwner(invite)){showAccess(true);return;}
      if(!api.hasAuth(invite)){showAccess(false);return;}
      load();
    }catch(error){hide('plan-loading',true);showError(error,false);}
    root.BolzooDatePlanPage={reload:load,getPlan:function(){return plan;}};
  }
  if(!catalog||(d.body.dataset.page==='date-plan'&&!root.BolzooDatePlanAPI)){
    // Even a failed script load must not leave a secret in the address bar.
    if(root.location.hash)root.history.replaceState(null,'',root.location.pathname+root.location.search);
    hide('plan-loading',true);
    var failure=element('p','message message-error','Хуудасны хэрэгсэл бүрэн ачаалагдсангүй. Холболтоо шалгаад хуудсыг дахин ачаалаарай.');failure.setAttribute('role','alert');$('main').prepend(failure);return;
  }
  if(d.body.dataset.page==='ideas')initIdeas();
  else if(d.body.dataset.page==='date-plan')initPlan();
}(window));
