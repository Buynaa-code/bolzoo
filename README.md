# bolzoo 💌

Personalised Mongolian date invitation web app.

Хоёр төрлийн илгээлт:

- **🌸 Цэцэг + захидал** — нэг цэцэг, гар бичмэл фонттой захидал. Илгээгч 5 цэцгээс нэгийг,
  захидлын 5 цаасны нэгийг сонгож, бичвэрээ бичнэ. Хүлээн авагч нээгээд «Хүлээж авлаа»
  гээд богино хариу үг бичиж болно.
- **💌 Болзооны урилга** — хүлээн авагч өдөр, цаг, болзооны төрлөө сонгож хариу өгнө.

## Файлууд

- **create.html** — нүүр хуудас: горимоо сонгож, формоо бөглөөд линкээ авна
- **greet.html?id=xxx** — цэцэг + захидлын мэндчилгээ (хүлээн авагч талын хуудас)
- **bolzoo.html?id=xxx** — болзооны урилга (хүлээн авагч талын хуудас)
- **dashboard.html** — илгээсэн урилга, мэндчилгээ, ирсэн хариунууд
- **assets/bolzoo-garden.js** — 5 цэцгийн inline SVG + 5 захидлын цаасны тодорхойлолт
- **server.js** — pure Node local dev server (Supabase PostgREST API-г офлайнаар эмуляц хийнэ)
- **assets/config.js** — Supabase URL + publishable key
- **sql/schema.sql** — Supabase table + RLS policies

Цэцэг, захидлын цаас, гар бичмэл бичвэр бүгд `invites.config` (jsonb) дотор
`mode:'flower'`, `flower`, `paper`, `specialLetter` талбаруудаар хадгалагдана —
өгөгдлийн сангийн бүтэц өөрчлөгдөөгүй.

Гар бичмэл фонт: [Caveat](https://fonts.google.com/specimen/Caveat) (кирилл, `Ө/Ү` үсэг дэмждэг).

## Local dev

```bash
node server.js
# → http://localhost:8080
```

## Deploy

Vercel дээр цэвэр статик сайтаар deploy хийгддэг (build алхам байхгүй — `vercel.json`-д
`buildCommand: null`, `outputDirectory: "."`). Backend нь Supabase (`invites` хүснэгт, RLS-тэй).

Vercel-ийн GitHub integration холбогдсон бол `main` руу push хийх бүрд production,
бусад branch/PR дээр preview автоматаар deploy болно. CLI-аар гараар хийх бол:

```bash
npx vercel --prod
```

Deploy болсны дараа шалгах хуудсууд:

| Зам | Юу байх ёстой |
| --- | --- |
| `/` эсвэл `/create` | Нүүр хуудас — горим сонгох (цэцэг + захидал / болзооны урилга) |
| `/greet.html` | Цэцэг + захидлын мэндчилгээ (хүлээн авагч тал) |
| `/bolzoo.html` | Болзооны урилга (хүлээн авагч тал) |
| `/dashboard.html` | Илгээсэн зүйлс ба ирсэн хариунууд |
| `/assets/bolzoo-garden.js` | Цэцэг, захидлын цаасны сан — 200 буцаах ёстой |
