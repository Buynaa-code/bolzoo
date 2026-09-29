/* A dated invitation keeps its original campaign meaning after the offer ends. */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory(null, require('./campaign'));
  else root.BolzooCampaignRecipient = factory(root, root.BolzooCampaign);
}(typeof window !== 'undefined' ? window : this, function (root, campaign) {
  'use strict';
  var DAY = 86400000;
  var OFFSET = 8 * 3600000;
  function enabled(config) {
    return !!campaign && campaign.ID === 'newyear100-2026' && !!config && config.campaign === campaign.ID && config.experienceType !== 'apology';
  }
  function timing(now) {
    var value = now === undefined ? Date.now() : typeof now === 'number' ? now : Date.parse(now);
    if (!Number.isFinite(value) || !campaign) return null;
    var today = Math.floor((value + OFFSET) / DAY);
    var target = Math.floor((Date.parse(campaign.NEW_YEAR_AT) + OFFSET) / DAY);
    return {days:Math.max(0, target - today),phase:today < target ? 'before' : today === target ? 'today' : 'past'};
  }
  function fold(line) {
    var result = '', bytes = 0;
    Array.from(line).forEach(function (character) {
      var point = character.codePointAt(0);
      var size = point < 128 ? 1 : point < 2048 ? 2 : point < 65536 ? 3 : 4;
      if (bytes + size > 75) { result += '\r\n '; bytes = 1; }
      result += character; bytes += size;
    });
    return result;
  }
  function createCalendar(now) {
    var value = now === undefined ? Date.now() : typeof now === 'number' ? now : Date.parse(now);
    if (!Number.isFinite(value)) return null;
    var stamp = new Date(value).toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
    return ['BEGIN:VCALENDAR','VERSION:2.0','PRODID:-//Bolzoo//New Year Idea//MN','CALSCALE:GREGORIAN',
      'BEGIN:VEVENT','UID:newyear100-2026-idea@bolzoo','DTSTAMP:'+stamp,'DTSTART;VALUE=DATE:20270101','DTEND;VALUE=DATE:20270102',
      'SUMMARY:Шинэ оны эхний жижиг дурсамж',
      'DESCRIPTION:Хүсвэл нэг кофе эсвэл нэг дуугаар шинэ оноо эхлүүлье. Энэ бол хувийн санааны сануулга. Болзооны тохирсон өдөр эсвэл газрын захиалга биш.',
      'TRANSP:TRANSPARENT','END:VEVENT','END:VCALENDAR'].map(fold).join('\r\n')+'\r\n';
  }
  function mount(options) {
    options = options || {};
    var doc = root.document;
    var badge = doc.getElementById('campaignInviteBadge');
    var card = doc.getElementById('campaignNewYearCard');
    var countdown = doc.getElementById('campaignDaysLeft');
    var caption = doc.getElementById('campaignTargetCaption');
    var button = doc.getElementById('campaignCalendar');
    var feedback = doc.getElementById('campaignCalendarStatus');
    var inviteCopy = doc.getElementById('campaignInviteCopy');
    var savedAcceptance = false;
    var timer = null;
    var now = options.now || function () { return Date.now(); };
    function config() { return typeof options.getConfig === 'function' ? options.getConfig() : options.config || {}; }
    function setText(node, text) { if (node && node.textContent !== text) node.textContent = text; }
    function update() {
      if (!badge || !card) return;
      var active = enabled(config());
      var clock = timing(now());
      badge.hidden = !active;
      card.hidden = !active || !savedAcceptance;
      if (!active || !clock) {
        if (timer) { root.clearInterval(timer); timer = null; }
        return;
      }
      if (!timer) timer = root.setInterval(function () { if (!doc.hidden) update(); }, 60000);
      setText(inviteCopy, clock.phase === 'past'
        ? 'Шинэ оныг угтсан нэг онцгой урилга. Хамтдаа жижиг дурсамж бүтээх үү?'
        : clock.phase === 'today' ? 'Шинэ оны эхний өдөр ирлээ. Хамтдаа нэг жижиг дурсамж бүтээх үү?'
        : 'Шинэ оны эхний өдрийг хүртэл хамтдаа дурсамж бүтээх үү?');
      setText(countdown, clock.phase === 'before' ? String(clock.days) : clock.phase === 'today' ? 'Өнөөдөр' : 'Дурсамж');
      setText(caption, clock.phase === 'before' ? 'шинэ он хүртэлх өдөр · Улаанбаатарын цагаар'
        : clock.phase === 'today' ? 'Шинэ оны эхний өдөр ирлээ.' : 'Шинэ оныг угтсан урилгын дурсамж.');
      setText(doc.getElementById('campaignTargetCopy'),clock.phase === 'past'
        ? 'Шинэ оны эхний өдөрт зориулсан урилгын дурсамж. Таны сонгосон болзооны өдөр, цаг тусдаа хэвээр.'
        : 'Хүсвэл энэ өдрийг нэг жижиг дурсамжаар эхлүүлээрэй. Энэ санаа таны сонгосон болзооны өдөр, цагийг өөрчлөхгүй.');
      button.hidden = clock.phase === 'past';
      doc.getElementById('campaignPreviewNote').hidden = !options.preview;
    }
    function setAccepted(answer) {
      savedAcceptance = answer === 'yes';
      if (feedback) feedback.textContent = '';
      update();
    }
    function download() {
      if (!enabled(config()) || !savedAcceptance || button.disabled) return;
      var clock = timing(now());
      if (!clock || clock.phase === 'past') { update(); return; }
      button.disabled = true;
      try {
        var file = createCalendar(now());
        if (!file || !root.URL || !root.URL.createObjectURL) throw new Error('unavailable');
        var url = root.URL.createObjectURL(new root.Blob([file], {type:'text/calendar;charset=utf-8'}));
        var link = doc.createElement('a');
        link.href = url; link.download = 'bolzoo-new-year-idea.ics';
        doc.body.appendChild(link); link.click(); link.remove();
        root.setTimeout(function () { root.URL.revokeObjectURL(url); }, 1000);
        setText(feedback, 'Календарийн файлаа нээгээд хүсвэл нэмээрэй. Энэ нь шинэ оны санааны сануулга.');
      } catch (_) {
        setText(feedback, 'Файлыг татаж чадсангүй. Хүсвэл 2027.01.01-нд хийх санаагаа календарьтаа гараар тэмдэглээрэй.');
      } finally { button.disabled = false; }
    }
    function onVisibility() { if (!doc.hidden) update(); }
    if (button) button.addEventListener('click', download);
    doc.addEventListener('visibilitychange', onVisibility);
    update();
    return {update:update,setAccepted:setAccepted,destroy:function () {
      if (timer) root.clearInterval(timer);
      if (button) button.removeEventListener('click', download);
      doc.removeEventListener('visibilitychange', onVisibility);
    }};
  }
  return {enabled:enabled,timing:timing,createCalendar:createCalendar,mount:mount};
}));
