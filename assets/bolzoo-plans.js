/**
 * Bolzoo — багцын тодорхойлолт (нэг эх сурвалж).
 *
 * Үнэ эсвэл багцад багтах зүйлээ өөрчлөх бол ЗӨВХӨН энэ файлыг засна.
 * create.html-ийн хаалт, admin.html-ийн сонгогч, unelgee.html-ийн хүснэгт
 * бүгд эндээс уншина.
 *
 * ⚠️ Энэ бол зөвхөн UI талын хаалт. Жинхэнэ хамгаалалт нь
 * sql/schema.sql доторх create_invite_with_code() (болон server.js) дээр —
 * тэнд Энгийн багцын урилгаас премиум талбаруудыг сервер тал дээр таслана.
 * Хоёр газарт зэрэг шинэчилж байхаа мартуузай.
 *
 * Хэрэглээ:
 *   BolzooPlans.get('basic')                  → багцын обьект
 *   BolzooPlans.allowsPaper(plan, 'kraft')    → тухайн цаас зөвшөөрөгдсөн эсэх
 *   BolzooPlans.limit(plan, 'letterMax')      → хязгаар унших
 *   BolzooPlans.money(9900)                   → "9,900₮"
 */
(function(){
  'use strict';

  // Багцгүй (хуучин) кодыг аль багцад тооцох вэ.
  // Өмнө нь зарагдсан кодыг доошлуулахгүйн тулд 'premium' гэж үзнэ.
  var DEFAULT_PLAN = 'premium';

  var ALL_PAPERS   = ['cream','blush','hearts','linen','ruled','grid','kraft','vintage'];
  var ALL_STICKERS = ['roses','party','draw','none'];

  var PLANS = {
    basic: {
      id: 'basic',
      label: 'Энгийн',
      emoji: '💌',
      price: 9900,
      tagline: 'Урилга бүрэн ажиллана',
      blurb: 'Анхны урилга илгээхэд хангалттай. Бүх үндсэн зүйл багтсан.',

      papers:      ['cream','blush','ruled'],
      stickers:    ['draw','none'],
      maxPromises: 0,
      letterMax:   300,
      location:    false,
      specialLetter: false,

      perks: [
        { ok:true,  text:'1 урилга — болзоо эсвэл аргадах' },
        { ok:true,  text:'8 тема өнгө' },
        { ok:true,  text:'Өөрийн YouTube дуу' },
        { ok:true,  text:'Захидал 300 тэмдэгт хүртэл' },
        { ok:true,  text:'3 үндсэн цаасны текстур' },
        { ok:true,  text:'Зурсан муурын дүрс' },
        { ok:true,  text:'Хариу шууд имэйлээр' },
        { ok:true,  text:'Тасалбар + Story зураг татах' },
        { ok:false, text:'Бүх 8 цаасны текстур' },
        { ok:false, text:'Жинхэнэ муурын гэрэл зураг' },
        { ok:false, text:'Амлалтын купон' },
        { ok:false, text:'Уулзах газар + Google Maps' }
      ]
    },

    premium: {
      id: 'premium',
      label: 'Онцгой',
      emoji: '✨',
      price: 14900,
      tagline: 'Бүх боломж нээлттэй',
      blurb: 'Хамгийн их өөрчлөх боломжтой. Онцгой өдөр, эвлэрэхэд тохиромжтой.',

      papers:      ALL_PAPERS,
      stickers:    ALL_STICKERS,
      maxPromises: 5,
      letterMax:   600,
      location:    true,
      specialLetter: true,

      perks: [
        { ok:true, text:'Энгийн багцын бүх зүйл' },
        { ok:true, text:'Бүх 8 цаасны текстур' },
        { ok:true, text:'Жинхэнэ муурын гэрэл зураг 🌹🎂' },
        { ok:true, text:'Амлалтын купон 5 хүртэл' },
        { ok:true, text:'Уулзах газар + Google Maps товч' },
        { ok:true, text:'Захидал 600 тэмдэгт хүртэл' },
        { ok:true, text:'Тусгай захидал (болзооны горимд)' }
      ]
    }
  };

  var ORDER = ['basic','premium'];

  function normalize(plan){
    var id = (plan && plan.id) ? plan.id : plan;
    return PLANS[id] ? id : DEFAULT_PLAN;
  }

  function get(plan){
    return PLANS[normalize(plan)];
  }

  function limit(plan, key){
    return get(plan)[key];
  }

  function allowsPaper(plan, paperId){
    return get(plan).papers.indexOf(paperId) !== -1;
  }

  function allowsSticker(plan, stickerId){
    return get(plan).stickers.indexOf(stickerId) !== -1;
  }

  /* 9900 → "9,900₮" */
  function money(n){
    return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ',') + '₮';
  }

  /**
   * Тухайн багцад зөвшөөрөгдөөгүй утгуудыг config-оос цэвэрлэнэ.
   * create.html хадгалахын өмнө дуудна — сервер тал дээр мөн адил шалгалт бий.
   */
  function sanitizeConfig(cfg, plan){
    var p = get(plan);
    var out = {};
    for(var k in cfg){ out[k] = cfg[k]; }

    out.plan = p.id;

    if(out.paper && !allowsPaper(p, out.paper)){ out.paper = p.papers[0]; }
    if(out.sticker && !allowsSticker(p, out.sticker)){ out.sticker = p.stickers[0]; }

    if(Array.isArray(out.promises)){ out.promises = out.promises.slice(0, p.maxPromises); }
    if(out.sorryLetter){ out.sorryLetter = String(out.sorryLetter).slice(0, p.letterMax); }

    if(!p.location){ delete out.locationName; delete out.locationUrl; }
    if(!p.specialLetter){ delete out.specialLetter; }

    return out;
  }

  window.BolzooPlans = {
    DEFAULT_PLAN: DEFAULT_PLAN,
    PLANS: PLANS,
    ids: ORDER,
    LIST: ORDER.map(function(id){ return PLANS[id]; }),
    get: get,
    normalize: normalize,
    limit: limit,
    allowsPaper: allowsPaper,
    allowsSticker: allowsSticker,
    money: money,
    sanitizeConfig: sanitizeConfig
  };
})();
