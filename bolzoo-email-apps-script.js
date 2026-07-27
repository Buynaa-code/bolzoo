const OWNER_EMAIL = 'name@gmail.com';

function doPost(e) {
  const data = JSON.parse(e.postData.contents || '{}');
  const subject = 'Болзооны хариу 💕';
  const body = [
    'Сайн уу 💕',
    '',
    'Болзооны хариу ирлээ:',
    '📅 Өдөр: ' + (data.date || ''),
    '🕐 Цаг: ' + (data.time || ''),
    '💝 Төрөл: ' + (data.kind || ''),
    '🎟️ Seat: ' + (data.seat || 'beside you'),
    '🎫 Ticket no: ' + (data.ticketNo || ''),
    '',
    data.countdown || '',
    '',
    '📸 Screen shot хийгээд илгээгээрэй.',
    '',
    'Илгээсэн: ' + (data.sentAt || new Date())
  ].join('\n');

  MailApp.sendEmail(OWNER_EMAIL, subject, body);

  return ContentService
    .createTextOutput(JSON.stringify({ ok: true }))
    .setMimeType(ContentService.MimeType.JSON);
}
