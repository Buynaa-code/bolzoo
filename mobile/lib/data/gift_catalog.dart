class DateIdea {
  const DateIdea({required this.id, required this.title, required this.description,
    required this.category, required this.duration, required this.placeType,
    required this.image, required this.invitationTitle, required this.steps});
  final String id, title, description, category, duration, placeType, image, invitationTitle;
  final List<String> steps;
}

const dateIdeas = [
  DateIdea(id: 'coffee', title: 'Кофе, бас яриа',
    description: 'Сайхан яриа бүхнийг ойртуулдаг.', category: 'Дотор',
    duration: '1–2 цаг', placeType: 'Кафе', image: 'assets/gifts/coffee.jpg',
    invitationTitle: 'Кофе уух уу?',
    steps: ['Хоёулаа тохиромжтой цагаа сонгоё.', 'Утсаа түр хойш тавиад бие биенээ сонсъё.', 'Сайхан мөчөө дурсамж болгоё.']),
  DateIdea(id: 'walk', title: 'Хамтдаа алхъя',
    description: 'Жаахан алхлаа, их дурсамж.', category: 'Гадаа',
    duration: '1–2 цаг', placeType: 'Парк', image: 'assets/gifts/walk.jpg',
    invitationTitle: 'Хоёулаа алхах уу?',
    steps: ['Ойрхон, тухтай замаа хамт сонгоё.', 'Дуртай ундаагаа аваад тайван алхъя.', 'Өнөөдрийн хамгийн гоё мөчөө ярилцъя.']),
  DateIdea(id: 'mountains', title: 'Хотоос түр холдъё',
    description: 'Цэвэр агаар, зөвхөн бид хоёр.', category: 'Гадаа',
    duration: 'Хагас өдөр', placeType: 'Байгаль', image: 'assets/gifts/mountains.jpg',
    invitationTitle: 'Нэг өдрийг хамт өнгөрөөе',
    steps: ['Хоёуланд тохирох газраа сонгоё.', 'Ус, хоол, дулаан хувцсаа бэлдье.', 'Зураг авч, эргэн санах нэг өдөр бүтээе.']),
  DateIdea(id: 'cinema', title: 'Нэг кино, хоёр сэтгэгдэл',
    description: 'Дараа нь дуртай хэсгээ ярилцъя.', category: 'Дотор',
    duration: '2–3 цаг', placeType: 'Кино театр', image: '',
    invitationTitle: 'Кино үзэх үү?',
    steps: ['Хоёул үзмээр байгаа киногоо сонгоё.', 'Тохиромжтой цаг, суудлаа ярилцъя.', 'Дараа нь сэтгэгдлээ хуваалцъя.']),
];

DateIdea ideaFor(String id) => dateIdeas.firstWhere((idea) => idea.id == id,
  orElse: () => dateIdeas.first);

const flowerOccasions = ['Зүгээр л', 'Төрсөн өдөр', 'Баярлалаа'];
const flowerColors = ['rose', 'sage', 'peach'];
const flowerTemplates = ['letter', 'garden', 'bloom'];
