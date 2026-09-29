/**
 * Shared response presentation rules. No network, DOM, storage, or HTML output.
 * appointment accepts an invitation ({response: {...}}) or a raw response.
 * Its date is display text; scheduled requires a valid dateISO AND explicit time.
 * All calendar times are the recipient's Ulaanbaatar wall time (UTC+08:00).
 */
(function(root, factory){
  var api = factory();
  if(typeof module === 'object' && module.exports) module.exports = api;
  if(root) root.BolzooResponses = api;
})(typeof window !== 'undefined' ? window : globalThis, function(){
  'use strict';

  function record(value){ return !!value && typeof value === 'object' && !Array.isArray(value); }
  function clean(value){ return typeof value === 'string' ? value.trim() : ''; }
  function pad(value){ return String(value).padStart(2, '0'); }

  function calendarDate(value){
    var match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(clean(value));
    if(!match) return null;
    var y = Number(match[1]), m = Number(match[2]), d = Number(match[3]);
    if(y < 1 || m < 1 || m > 12 || d < 1 || d > 31) return null;
    var date = new Date(0);
    date.setUTCFullYear(y, m - 1, d);
    date.setUTCHours(0, 0, 0, 0);
    if(date.getUTCFullYear() !== y || date.getUTCMonth() !== m - 1 || date.getUTCDate() !== d) return null;
    return { y:y, m:m, d:d, iso:match[0] };
  }

  function appointment(value){
    var r = record(value) && Object.prototype.hasOwnProperty.call(value, 'response') ? value.response : value;
    r = record(r) ? r : {};
    var date = calendarDate(r.dateISO);
    var time = /^(?:[01]\d|2[0-3]):[0-5]\d$/.test(clean(r.time)) ? clean(r.time) : '';
    return {
      date:date ? date.y + ' оны ' + date.m + '-р сарын ' + date.d : clean(r.date),
      dateISO:date ? date.iso : '',
      time:time,
      scheduled:!!date && !!time
    };
  }

  function legacyCalendarDate(value){
    var input = clean(value);
    var iso = calendarDate(input);
    if(iso) return iso;
    var match = /^(\d{4}) оны (\d{1,2})-р сар(?:ын)? (\d{1,2})$/.exec(input)
      || /^(\d{4})\.(\d{1,2})\.(\d{1,2})$/.exec(input);
    return match ? calendarDate(match[1] + '-' + pad(match[2]) + '-' + pad(match[3])) : null;
  }

  function readiness(value){
    if(typeof value !== 'number' && typeof value !== 'string') return null;
    if(typeof value === 'string' && !/^\d+(?:\.\d+)?$/.test(value.trim())) return null;
    var number = Number(value);
    return Number.isFinite(number) && number >= 0 && number <= 100 ? number : null;
  }

  function timestampDate(value){
    if(value == null || typeof value === 'boolean' || (typeof value === 'string' && !value.trim())) return null;
    if(typeof value !== 'string' && typeof value !== 'number' && !(value instanceof Date)) return null;
    if(typeof value === 'string'){
      // API timestamps are ISO values. Date.parse also accepts strings such as
      // "0" or "12", which should never appear as a real response timestamp.
      if(!/^\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}:?\d{2})?)?$/.test(value.trim())) return null;
      var iso = /^(\d{4}-\d{2}-\d{2})/.exec(value.trim());
      if(iso && !calendarDate(iso[1])) return null;
      var time = /^\d{4}-\d{2}-\d{2}[T ](\d{2}):(\d{2})(?::(\d{2}))?/.exec(value.trim());
      if(time && (Number(time[1]) > 23 || Number(time[2]) > 59 || Number(time[3] || 0) > 59)) return null;
    }
    var date = new Date(value);
    return Number.isFinite(date.getTime()) ? date : null;
  }

  function formatTimestamp(value){
    var date = timestampDate(value);
    if(!date) return '—';
    var parts = new Intl.DateTimeFormat('en-GB', {
      timeZone:'Asia/Ulaanbaatar', year:'numeric', month:'2-digit', day:'2-digit',
      hour:'2-digit', minute:'2-digit', hourCycle:'h23', numberingSystem:'latn'
    }).formatToParts(date);
    var values = {};
    parts.forEach(function(part){ values[part.type] = part.value; });
    return values.year.padStart(4, '0') + '.' + values.month + '.' + values.day
      + ' · ' + values.hour + ':' + values.minute;
  }

  function safeWebUrl(value){
    var input = clean(value);
    if(!/^https?:\/\//i.test(input) || /[\u0000-\u0020\u007f]/.test(input)) return '';
    try {
      var url = new URL(input);
      return (url.protocol === 'https:' || url.protocol === 'http:') && url.hostname ? url.href : '';
    } catch(_) { return ''; }
  }

  var APOLOGY = {
    needs_space:{label:'Хугацаа хэрэгтэй', icon:'🕊️', description:'Хүлээн авагч өөрт нь хугацаа хэрэгтэй гэж хариулсан. Хэзээ бэлэн болохыг нь өөрт нь үлдээгээрэй.'},
    read:{label:'Захиаг уншсан', icon:'💌', description:'Хүлээн авагч захиаг уншсанаа мэдэгдсэн. Уучилсан эсвэл ярилцахад бэлэн гэсэн хариу өгөөгүй.'},
    message:{label:'Мессежээр ярилцаж болно', icon:'💬', description:'Хүлээн авагч мессежээр ярилцаж болно гэж хариулсан. Уулзах эсвэл эвлэрэх шийдвэр хараахан илэрхийлээгүй.'},
    meet:{label:'Уулзаж ярилцахад бэлэн', icon:'☕', description:'Хүлээн авагч уулзаж ярилцахад бэлэн гэж хариулсан. Энэ нь уучилсан гэсэн үг биш.'},
    stop:{label:'Дахиж холбоо барихгүй байхыг хүссэн', icon:'🛑', description:'Хүлээн авагч дахин холбоо барихгүй байхыг хүссэн. Энэ хүсэлтийг нь хүндэтгэж, дахин холбоо барихгүй байгаарай.'}
  };

  function status(key, label, description, icon, hasResponse, accepted, waiting){
    return {key:key, label:label, description:description, icon:icon,
      hasResponse:!!hasResponse, accepted:!!accepted, waiting:!!waiting};
  }

  function classify(value, now){
    var inv = record(value) ? value : {};
    var r = record(inv.response) ? inv.response : {};
    var hasPayload = Object.keys(r).length > 0 || (inv.response != null && !record(inv.response));
    var hasResponse = hasPayload || !!inv.responded_at;
    var cfg = record(inv.config) ? inv.config : {};
    var isApology = cfg.experienceType === 'apology' || r.type === 'apology';
    if(!hasResponse){
      var expires = isApology ? timestampDate(cfg.expiresAt) : null;
      var current = now === undefined ? Date.now() : timestampDate(now);
      if(expires && current !== null && expires.getTime() <= Number(current)){
        return status('expired', 'Урилгын хугацаа дууссан', 'Энэ урилгын линк идэвхгүй болсон. Хугацаа дуусахаас өмнө хариу ирээгүй байна.', '⌛', false, false, false);
      }
      if(inv.opened_at){
        return status('waiting', 'Линк нээгдсэн · Хариу хүлээж байна', 'Урилгын линк нээгдсэн байна. Хүлээн авагчийн хариу хараахан ирээгүй.', '👀', false, false, true);
      }
      return status('unopened', 'Линк хараахан нээгдээгүй', 'Урилгын линкээ илгээгээрэй. Хариу ирэхэд энд харагдана.', '💌', false, false, true);
    }
    if(isApology && Object.prototype.hasOwnProperty.call(APOLOGY, r.status)){
      var apology = APOLOGY[r.status];
      return status(r.status, apology.label, apology.description, apology.icon, true, false, false);
    }
    if(!isApology){
      var plan = appointment(r);
      if(r.answer === 'later'){
        return status('later', 'Өөр өдөр санал болгосон', plan.date
          ? 'Тухайн өдөр амжихгүй гэж хариулаад өөр өдөр санал болгосон байна. Шинэ өдөр, цагаа хоорондоо тохироорой.'
          : 'Тухайн өдөр амжихгүй гэж хариулсан. Шинэ өдөр хараахан сонгоогүй байна.', '📅', true, false, false);
      }
      if(r.answer === 'no'){
        return status('declined', 'Энэ удаа татгалзсан', 'Хүлээн авагч энэ удаа урилгаас татгалзсан. Сонголтыг нь хүндэтгэе.', '💌', true, false, false);
      }
      var legacyDate = r.answer == null && r.status == null && (!!plan.dateISO || !!legacyCalendarDate(r.date));
      if(r.answer === 'yes' || legacyDate){
        return status('accepted', 'Урилгыг зөвшөөрсөн', plan.scheduled
          ? 'Урилгыг зөвшөөрч, уулзах өдөр болон цагаа сонгосон байна.'
          : 'Урилгыг зөвшөөрсөн байна. Уулзах өдөр, цагийг бүрэн сонгоогүй байна.', '💕', true, true, false);
      }
    }
    return status('unknown', 'Хариуны мэдээлэл бүрэн харагдахгүй байна', 'Хариу бүртгэгдсэн ч сонголтыг нь тодорхой харуулах боломжгүй байна. Шинэчлэх товчоор дахин шалгаарай.', '💬', true, false, false);
  }

  function icsEscape(value){
    return String(value == null ? '' : value).replace(/\\/g, '\\\\').replace(/\r\n|\r|\n/g, '\\n').replace(/;/g, '\\;').replace(/,/g, '\\,');
  }

  // RFC 5545 limits content lines to 75 UTF-8 octets, including continuation space.
  function foldLine(line){
    var folded = '', bytes = 0;
    Array.from(line).forEach(function(character){
      var point = character.codePointAt(0);
      var size = point < 0x80 ? 1 : point < 0x800 ? 2 : point < 0x10000 ? 3 : 4;
      if(bytes + size > 75){ folded += '\r\n '; bytes = 1; }
      folded += character;
      bytes += size;
    });
    return folded;
  }

  function utcCompact(date){ return date.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z'); }

  function createCalendar(inv, options){
    if(!record(inv) || !classify(inv).accepted || !clean(inv.id)) return null;
    var plan = appointment(inv);
    if(!plan.scheduled) return null;
    options = record(options) ? options : {};
    var duration = options.durationMinutes === undefined ? 60 : options.durationMinutes;
    if(typeof duration !== 'number' || !Number.isInteger(duration) || duration < 1 || duration > 1440) return null;
    var cfg = record(inv.config) ? inv.config : {};
    var r = record(inv.response) ? inv.response : {};
    var start = new Date(plan.dateISO + 'T' + plan.time + ':00+08:00');
    var end = new Date(start.getTime() + duration * 60000);
    var stamp = options.now === undefined ? new Date() : timestampDate(options.now);
    if(!stamp) return null;
    var title = clean(options.title) || 'Болзоо' + (clean(cfg.recipientName) ? ' · ' + clean(cfg.recipientName) : '');
    var location = options.location === undefined ? clean(cfg.locationName) : clean(options.location);
    var description = options.description === undefined ? (clean(r.choice) || clean(r.kind)) : clean(options.description);
    var lines = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Bolzoo//Invitation//MN', 'CALSCALE:GREGORIAN',
      'BEGIN:VEVENT', 'UID:' + encodeURIComponent(inv.id) + '@bolzoo', 'DTSTAMP:' + utcCompact(stamp),
      'DTSTART:' + utcCompact(start), 'DTEND:' + utcCompact(end), 'SUMMARY:' + icsEscape(title)];
    if(description) lines.push('DESCRIPTION:' + icsEscape(description));
    if(location) lines.push('LOCATION:' + icsEscape(location));
    var url = safeWebUrl(options.url);
    if(url) lines.push('URL:' + url);
    lines.push('END:VEVENT', 'END:VCALENDAR');
    return lines.map(foldLine).join('\r\n') + '\r\n';
  }

  // A browser-local read marker, containing no response text or access token.
  function responseVersion(inv){
    if(!classify(inv).hasResponse)return '';
    function stable(value){
      if(Array.isArray(value))return '['+value.map(stable).join(',')+']';
      if(record(value))return '{'+Object.keys(value).sort().map(function(key){return JSON.stringify(key)+':'+stable(value[key]);}).join(',')+'}';
      return JSON.stringify(value===undefined?null:value);
    }
    var input=stable({response:inv.response,responded_at:inv.responded_at}),a=2166136261,b=5381;
    for(var i=0;i<input.length;i++){a=Math.imul(a^input.charCodeAt(i),16777619);b=Math.imul(b,33)^input.charCodeAt(i);}
    return (a>>>0).toString(16).padStart(8,'0')+(b>>>0).toString(16).padStart(8,'0');
  }

  function planPresentation(plan){
    if(!record(plan)||!Number.isInteger(plan.revision)||plan.revision<1)return null;
    var labels={proposed:'Шинэ төлөвлөгөөг тохирч байна',agreed:'Хоёулаа тохирлоо',in_progress:'Болзоо үргэлжилж байна',ended:'Болзоогоо өндөрлөсөн',declined:'Энэ төлөвлөгөө боломжгүй болсон',cancelled:'Төлөвлөгөөг цуцалсан'};
    if(!Object.prototype.hasOwnProperty.call(labels,plan.state))return null;
    var accepted=record(plan.accepted)?plan.accepted:{};
    var both=accepted.creator===plan.revision&&accepted.partner===plan.revision;
    if(['agreed','in_progress','ended'].includes(plan.state)&&!both)return null;
    if(plan.state==='proposed'&&both)return null;
    var date=typeof plan.scheduled_at==='string'&&/(?:Z|[+-]\d{2}:\d{2})$/.test(plan.scheduled_at)?timestampDate(plan.scheduled_at):null,iso='',time='';
    if(date){var local=new Date(date.getTime()+8*3600000);iso=local.toISOString().slice(0,10);time=local.toISOString().slice(11,16);}
    var explanation='';
    if(plan.state==='proposed')explanation=accepted.creator===plan.revision?'Та энэ хувилбарыг зөвшөөрсөн. Нөгөө хүний зөвшөөрөл хүлээж байна.':accepted.partner===plan.revision?'Нөгөө хүн энэ хувилбарыг зөвшөөрсөн. Таны хариу хүлээж байна.':'Энэ хувилбарыг хоёр тал хараахан зөвшөөрөөгүй.';
    return {label:labels[plan.state],explanation:explanation,bothAccepted:both,state:plan.state,
      dateISO:iso,time:time,scheduled:!!iso&&!!time,title:clean(plan.title),location:clean(plan.location),revision:plan.revision};
  }

  function createPlanCalendar(plan, options){
    var view=planPresentation(plan);
    if(!view||!view.bothAccepted||!view.scheduled||!['agreed','in_progress'].includes(view.state)||!clean(plan.id))return null;
    return createCalendar({id:'plan-'+plan.id,config:{locationName:view.location},response:{answer:'yes',dateISO:view.dateISO,time:view.time}},
      Object.assign({},options||{},{title:view.title||'Бидний болзоо',location:view.location,description:'Хоёр тал зөвшөөрсөн төлөвлөгөө · хувилбар '+view.revision}));
  }

  return {classify:classify, appointment:appointment, readiness:readiness,
    formatTimestamp:formatTimestamp, safeWebUrl:safeWebUrl, createCalendar:createCalendar,
    responseVersion:responseVersion,planPresentation:planPresentation,createPlanCalendar:createPlanCalendar};
});
