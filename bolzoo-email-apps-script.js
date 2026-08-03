/**
 * Bolzoo — хариу ирэхэд илгээгч рүү имэйл илгээх Google Apps Script.
 *
 * ┌─ ТОХИРУУЛАХ (нэг удаа, ~5 минут) ─────────────────────────────────┐
 * │ 1. https://script.google.com → New project                        │
 * │ 2. Энэ файлын агуулгыг бүтнээр нь хуулж тавина                    │
 * │ 3. Доорх SUPABASE_URL / SUPABASE_ANON_KEY-г assets/config.js-ээс  │
 * │    хуулж бөглөнө                                                  │
 * │ 4. Deploy → New deployment → type: Web app                        │
 * │      Execute as:      Me                                          │
 * │      Who has access:  Anyone                                      │
 * │ 5. Гарсан Web app URL-ыг assets/config.js доторх                  │
 * │    emailWebhookUrl талбарт тавина                                 │
 * └───────────────────────────────────────────────────────────────────┘
 *
 * АЮУЛГҮЙ БАЙДАЛ: энэ endpoint зөвхөн inviteId хүлээж авна. Хүлээн авах
 * имэйл хаягийг Supabase доторх урилгын config-оос уншина — клиентээс
 * ирсэн хаяг руу ХЭЗЭЭ Ч илгээхгүй. Ингэснээр хэн нэгэн үүнийг дурын
 * хаяг руу спам илгээх relay болгон ашиглах боломжгүй.
 */

const SUPABASE_URL      = 'https://YOUR-PROJECT.supabase.co';
const SUPABASE_ANON_KEY = 'YOUR-PUBLISHABLE-KEY';

function doPost(e) {
  try {
    const body = JSON.parse((e && e.postData && e.postData.contents) || '{}');
    const inviteId = String(body.inviteId || '').trim();
    if (!inviteId) return json({ ok: false, error: 'inviteId required' });

    const invite = fetchInvite(inviteId);
    if (!invite)          return json({ ok: false, error: 'invite not found' });
    if (!invite.response) return json({ ok: false, error: 'no response yet' });

    const cfg = invite.config || {};
    const to = String(cfg.responseEmail || '').trim();
    if (!to) return json({ ok: false, error: 'invite has no responseEmail' });

    const mail = buildMail(cfg, invite.response);
    MailApp.sendEmail(to, mail.subject, mail.body);
    return json({ ok: true });
  } catch (err) {
    return json({ ok: false, error: String(err) });
  }
}

function fetchInvite(id) {
  const url = SUPABASE_URL.replace(/\/$/, '')
    + '/rest/v1/invites?id=eq.' + encodeURIComponent(id)
    + '&select=config,response,responded_at';
  const res = UrlFetchApp.fetch(url, {
    method: 'get',
    muteHttpExceptions: true,
    headers: { apikey: SUPABASE_ANON_KEY, Authorization: 'Bearer ' + SUPABASE_ANON_KEY }
  });
  if (res.getResponseCode() !== 200) return null;
  const rows = JSON.parse(res.getContentText() || '[]');
  return rows.length ? rows[0] : null;
}

function buildMail(cfg, r) {
  const who = cfg.recipientName || 'Хүлээн авагч';

  if (r && r.type === 'sorry') {
    return {
      subject: r.forgiven
        ? (who + ' чамайг уучиллаа 💗')
        : (who + '-д жаахан цаг хэрэгтэй байна 🫂'),
      body: [
        'Аргадах захидлын хариу ирлээ.',
        '',
        'Хэнд:      ' + who,
        'Хариу:     ' + (r.forgiven ? 'Уучилсан 💗' : 'Хараахан үгүй 🫂'),
        'Хэмжүүр:   ' + (r.level == null ? '—' : r.level + '%'),
        (r.reply ? 'Хэлсэн үг: ' + r.reply : ''),
        '',
        'Ирсэн: ' + fmtWhen(r.at)
      ].filter(Boolean).join('\n')
    };
  }

  return {
    subject: who + ' болзоонд зөвшөөрлөө 💕',
    body: [
      'Болзооны хариу ирлээ.',
      '',
      'Хэнд:    ' + who,
      'Өдөр:    ' + (r.date || ''),
      'Цаг:     ' + (r.time || ''),
      'Төрөл:   ' + (r.kind || ''),
      'Ticket:  ' + (r.ticketNo || ''),
      '',
      (r.countdown || ''),
      '',
      'Ирсэн: ' + (r.sentAt || fmtWhen(new Date().toISOString()))
    ].filter(Boolean).join('\n')
  };
}

function fmtWhen(iso) {
  if (!iso) return '';
  const d = new Date(iso);
  if (isNaN(d.getTime())) return String(iso);
  const p = (n) => (n < 10 ? '0' : '') + n;
  return d.getFullYear() + '.' + p(d.getMonth() + 1) + '.' + p(d.getDate())
    + ' ' + p(d.getHours()) + ':' + p(d.getMinutes());
}

function json(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}
