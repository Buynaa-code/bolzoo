/* Bolzoo · Эвлэрье — deterministic, no-AI apology templates. */
(function(root, factory){
  var api = factory();
  if(typeof module === 'object' && module.exports) module.exports = api;
  if(root) root.BolzooApology = api;
})(typeof window !== 'undefined' ? window : globalThis, function(){
  'use strict';

  var ISSUES = {
    harsh_words: {
      icon: '😔',
      label: 'Хатуу үг хэлсэн',
      fallback: 'Уурласан үедээ бодлогогүй, хатуу үг хэлсэн',
      impact: 'Миний хэлсэн үг чамайг гомдоож, үнэ цэнгүй мэт мэдрүүлсэн байж болохыг ойлгож байна.'
    },
    forgot: {
      icon: '📅',
      label: 'Амлалт эсвэл чухал өдрийг мартсан',
      fallback: 'Чамд чухал байсан амлалт эсвэл өдрийг мартсан',
      impact: 'Энэ нь чамд би бидний харилцаа, чамд чухал зүйлсийг тоодоггүй мэт мэдрүүлсэн байж болохыг ойлгож байна.'
    },
    neglected: {
      icon: '🥀',
      label: 'Анхаарал халамж дутсан',
      fallback: 'Чамд хэрэгтэй үед цаг гаргаж, анхаарал тавьж чадаагүй',
      impact: 'Энэ нь чамайг ганцаардсан эсвэл үл тоосон мэт мэдрүүлсэн байж болохыг ойлгож байна.'
    },
    cancelled: {
      icon: '⏰',
      label: 'Хоцорсон эсвэл төлөвлөгөөг цуцалсан',
      fallback: 'Бидний төлөвлөгөөнд хариуцлагагүй хандаж, чамайг хүлээлгэсэн',
      impact: 'Чиний цаг хугацаа, хүлээлтийг хүндлээгүй мэт болсон гэдгийг ойлгож байна.'
    },
    jealousy: {
      icon: '💭',
      label: 'Хардалт эсвэл буруу ойлголцол',
      fallback: 'Чамайг тайван сонсохын оронд хэтэрхий хурдан дүгнэсэн',
      impact: 'Энэ нь чамд итгэхгүй, үгийг чинь сонсохгүй байгаа мэт мэдрүүлсэн байж болохыг ойлгож байна.'
    },
    other: {
      icon: '✍️',
      label: 'Өөр асуудал',
      fallback: 'Чамайг гомдоосон үйлдэл гаргасан',
      impact: 'Миний үйлдэл чамд хүнд туссаныг би хөнгөнөөр авч үзэхгүй байна.'
    }
  };

  var TONES = {
    short: { icon: '💬', label: 'Богино бөгөөд чин сэтгэлийн' },
    gentle: { icon: '🌷', label: 'Зөөлөн, дулаан' },
    serious: { icon: '🤝', label: 'Нухацтай, хариуцлагатай' }
  };

  var STATUSES = {
    needs_space: { icon: '🕊️', label: 'Надад хугацаа хэрэгтэй', tone: 'space' },
    read:        { icon: '💌', label: 'Захиаг чинь уншлаа', tone: 'read' },
    message:     { icon: '💬', label: 'Мессежээр ярилцаж болно', tone: 'talk' },
    meet:        { icon: '☕', label: 'Уулзаж ярилцахад бэлэн', tone: 'meet' },
    stop:        { icon: '🛑', label: 'Дахиж холбоо барихгүй байхыг хүсэж байна', tone: 'stop' }
  };

  var PAPERS = {
    soft: {
      label: 'Зөөлөн цаас',
      image: 'assets/images/papers/8b2ddbd9d7627effe0613e92252acc6f.jpg'
    },
    dotted: {
      label: 'Цэгтэй захиа',
      image: 'assets/images/papers/985cdcac5e8a0a21491133ab684ed9d9.jpg'
    },
    grid: {
      label: 'Дэвтрийн нүд',
      image: 'assets/images/papers/a269cdd99f781310d7e8c7e3eebd9f1a.jpg'
    },
    handmade: {
      label: 'Гар хийцийн цаас',
      image: 'assets/images/papers/d526e90c0b2d6cdbc23f1ab6b5b42892.jpg'
    },
    linen: {
      label: 'Даавуун цаас',
      image: 'assets/images/papers/download.png'
    },
    clean: {
      label: 'Цэвэр texture',
      image: 'assets/images/papers/fcd5b00d25ef5d358119ba95917b8236.jpg'
    }
  };

  function clean(value, fallback){
    var out = String(value == null ? '' : value).replace(/\s+/g, ' ').trim();
    return out || fallback || '';
  }

  function issue(id){ return ISSUES[id] || ISSUES.other; }
  function tone(id){ return TONES[id] || TONES.gentle; }
  function status(id){ return STATUSES[id] || null; }
  function paper(id){ return PAPERS[id] || PAPERS.soft; }

  function buildLetter(config){
    config = config || {};
    var issueInfo = issue(config.apologyIssue);
    var recipient = clean(config.recipientName, 'Хайр минь');
    var sender = clean(config.senderName, '');
    var happened = clean(config.apologyWhatHappened, issueInfo.fallback);
    var regret = clean(
      config.apologyRegret,
      'Чамайг гомдоосноо хожуу биш, одоо ойлгож байгаагаа үнэнээр хэлэхийг хүссэн юм.'
    );
    var repair = clean(
      config.apologyRepair,
      'Үгээр зогсохгүй, дахин ийм байдал гаргахгүй байхын тулд бодит өөрчлөлт хийнэ.'
    );
    var selectedTone = TONES[config.apologyTone] ? config.apologyTone : 'gentle';
    var lines = [recipient + ' минь,'];

    if(selectedTone === 'short'){
      lines.push(
        '',
        'Би нэг зүйлдээ чин сэтгэлээсээ харамсаж байна: ' + happened + '.',
        issueInfo.impact,
        regret,
        'Үүнийг засахын тулд ' + repair + '.',
        'Чи шууд хариулах эсвэл уучлах албагүй. Чамд хэрэгтэй хугацааг хүндэтгэнэ.'
      );
    } else if(selectedTone === 'serious'){
      lines.push(
        '',
        'Би хийсэн зүйлээ өөрийгөө зөвтгөхгүйгээр хүлээн зөвшөөрмөөр байна: ' + happened + '.',
        issueInfo.impact,
        'Миний санаа ямар байсан нь биш, чамд яаж нөлөөлсөн нь энд чухал гэдгийг ойлгож байна.',
        regret,
        'Одоо үгээр амлахын оронд дараах зүйлийг бодитоор хийнэ: ' + repair + '.',
        'Намайг шууд уучлах албагүй. Хэзээ, хэрхэн ярилцахаа чи өөрөө шийдэх эрхтэй.'
      );
    } else {
      lines.push(
        '',
        'Чамд тайван бөгөөд чин сэтгэлээсээ нэг зүйл хэлэхийг хүсэж байна.',
        'Би ' + happened + '. Үүндээ үнэхээр харамсаж байна.',
        issueInfo.impact,
        regret,
        'Үүнийг засахын тулд ' + repair + '.',
        'Чамайг яаруулахгүй. Хариулахад хугацаа хэрэгтэй бол би тэр хугацааг чинь хүндэтгэнэ.'
      );
    }

    if(config.apologyDateOffer){
      lines.push('', 'Хэзээ нэгэн цагт бэлэн болсон үедээ тайван уулзаж ярилцахыг хүсвэл би нээлттэй байна.');
    }
    if(sender) lines.push('', '— ' + sender);
    return lines.join('\n');
  }

  function findPressurePhrases(value){
    var text = clean(value, '').toLowerCase();
    var rules = [
      { re: /гэхдээ\s+чи/, label: '“Гэхдээ чи…” гэж нөгөө хүнийг буруутгасан хэсэг байна.' },
      { re: /чи\s+ч\s+гэсэн/, label: '“Чи ч гэсэн…” гэж хариуцлагаа хуваах гэж оролдсон хэсэг байна.' },
      { re: /хэрэв\s+чи\s+гомдсон\s+бол/, label: '“Хэрэв чи гомдсон бол” гэдэг нь гомдлыг нь үгүйсгэж сонсогдож болно.' },
      { re: /уучлах\s+ёстой/, label: 'Уучлахыг шаардсан өгүүлбэрийг хасна уу.' },
      { re: /надад\s+хайртай\s+бол/, label: 'Хайраар нь барьцаалсан мэт сонсогдох хэсгийг хасна уу.' },
      { re: /би\s+угаасаа\s+ийм/, label: '“Би угаасаа ийм” гэдэг нь өөрчлөлтөөс зайлсхийсэн мэт сонсогдоно.' }
    ];
    return rules.filter(function(rule){ return rule.re.test(text); }).map(function(rule){ return rule.label; });
  }

  return {
    issues: ISSUES,
    tones: TONES,
    statuses: STATUSES,
    papers: PAPERS,
    issue: issue,
    tone: tone,
    status: status,
    paper: paper,
    buildLetter: buildLetter,
    findPressurePhrases: findPressurePhrases
  };
});
