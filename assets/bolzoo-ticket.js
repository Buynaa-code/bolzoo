/**
 * Bolzoo — canvas ticket renderer + PNG downloader.
 *
 * Хэрэглээ:
 *   BolzooTicket.save({
 *     mode: 'card' | 'story',
 *     dateText: '2025 оны 8-р сар 21',   // fmtDate(...)-с орж ирсэн
 *     time: '18:00',
 *     kindTicket: 'кофе болзоо',
 *     ticketNo: '123',
 *     countdownText: 'болзоонд үлдсэн: 3 өдөр 💗'
 *   });
 *
 * Fonts бэлэн болтол хүлээгээд PNG үүсгээд шууд download хийнэ.
 */
(function(){
  function roundedRect(ctx, x, y, w, h, r){
    ctx.beginPath();
    ctx.moveTo(x+r, y);
    ctx.lineTo(x+w-r, y);
    ctx.quadraticCurveTo(x+w, y, x+w, y+r);
    ctx.lineTo(x+w, y+h-r);
    ctx.quadraticCurveTo(x+w, y+h, x+w-r, y+h);
    ctx.lineTo(x+r, y+h);
    ctx.quadraticCurveTo(x, y+h, x, y+h-r);
    ctx.lineTo(x, y+r);
    ctx.quadraticCurveTo(x, y, x+r, y);
    ctx.closePath();
  }
  function centerText(ctx, text, x, y, maxWidth){ ctx.fillText(text, x, y, maxWidth || 520); }
  function capFirst(s){
    s = String(s || '').trim();
    return s ? s.charAt(0).toUpperCase() + s.slice(1) : '';
  }
  function drawSoftShadow(ctx, color, blur, y){
    ctx.shadowColor = color;
    ctx.shadowBlur = blur;
    ctx.shadowOffsetY = y;
  }

  function drawTicketOn(ctx, ox, oy, d){
    var hasLocation = !!String((d.locationName || '') + (d.locationAddress || '')).trim();
    ctx.save();
    ctx.translate(ox, oy);
    ctx.save();
    drawSoftShadow(ctx, 'rgba(170,61,101,.28)', 46, 22);
    roundedRect(ctx, 0, 0, 532, 744, 34);
    ctx.fillStyle = '#fffdfb'; ctx.fill();
    ctx.restore();

    ctx.save();
    var glow = ctx.createRadialGradient(266, 74, 20, 266, 74, 210);
    glow.addColorStop(0, 'rgba(255,108,151,.18)');
    glow.addColorStop(1, 'rgba(255,108,151,0)');
    ctx.fillStyle = glow;
    ctx.fillRect(0, 0, 532, 220);
    ctx.restore();

    ctx.textAlign = 'center';
    ctx.fillStyle = '#ffd9e4';
    roundedRect(ctx, 132, 36, 268, 36, 18); ctx.fill();
    ctx.fillStyle = '#f44583'; ctx.font = '800 15px Nunito, Arial, sans-serif';
    centerText(ctx, d.statusText || 'БОЛЗООНЫ САНАЛ', 266, 60, 240);

    ctx.fillStyle = '#4b173f'; ctx.font = '800 45px Comfortaa, Arial, sans-serif';
    centerText(ctx, capFirst(d.kindTicket || 'болзоо'), 266, 128, 480);
    ctx.fillStyle = '#82758c'; ctx.font = '800 18px Nunito, Arial, sans-serif';
    centerText(ctx, d.subtitle || 'Чиний тусгай хэн нэгэнтэй хамт', 266, 162, 460);

    ctx.textAlign = 'left';
    ctx.save();
    drawSoftShadow(ctx, 'rgba(116,45,88,.16)', 28, 14);
    ctx.fillStyle = '#ffffff';
    roundedRect(ctx, 42, 198, 448, 254, 26); ctx.fill();
    ctx.restore();
    ctx.strokeStyle = '#ffd0dc'; ctx.lineWidth = 1;
    roundedRect(ctx, 42, 198, 448, 254, 26); ctx.stroke();

    function infoRow(y, icon, label, value, sub, pill){
      ctx.fillStyle = icon === '🕐' ? '#f4e5ff' : '#ffe6ef';
      roundedRect(ctx, 66, y-31, 56, 56, 18); ctx.fill();
      ctx.textAlign = 'center'; ctx.font = '28px Arial, sans-serif'; ctx.fillStyle = '#f54f89';
      centerText(ctx, icon, 94, y+7, 48);
      ctx.textAlign = 'left';
      ctx.fillStyle = '#8c7d95'; ctx.font = '800 13px Nunito, Arial, sans-serif';
      ctx.fillText(label, 142, y-9, 210);
      ctx.fillStyle = '#4b173f'; ctx.font = '900 24px Nunito, Arial, sans-serif';
      ctx.fillText(value, 142, y+18, 230);
      if(sub){
        ctx.fillStyle = '#8b8092'; ctx.font = '700 13px Nunito, Arial, sans-serif';
        ctx.fillText(sub, 142, y+40, 300);
      }
      if(pill){
        ctx.fillStyle = '#ffe4ee';
        roundedRect(ctx, 376, y-25, 88, 34, 17); ctx.fill();
        ctx.fillStyle = '#ef4f88'; ctx.font = '900 13px Nunito, Arial, sans-serif';
        ctx.textAlign = 'center'; centerText(ctx, pill, 420, y-3, 70);
        ctx.textAlign = 'left';
      }
    }
    if(hasLocation){
      infoRow(252, '📅', 'Огноо', d.dateDots || d.dateText, '', d.weekday || '');
      ctx.strokeStyle = '#ffd8e2'; ctx.beginPath(); ctx.moveTo(66, 306); ctx.lineTo(466, 306); ctx.stroke();
      infoRow(340, '🕐', 'Цаг', d.time, '', '');
      ctx.strokeStyle = '#ffd8e2'; ctx.beginPath(); ctx.moveTo(66, 394); ctx.lineTo(466, 394); ctx.stroke();
      infoRow(424, '📍', 'Байршил', d.locationName, d.locationAddress || '', '');
    } else {
      // Байршил оруулаагүй үед хиймэл default харуулахгүй; огноо, цагийг
      // хоёр цэвэрхэн мөрөөр төвлөрүүлнэ.
      infoRow(280, '📅', 'Огноо', d.dateDots || d.dateText, '', d.weekday || '');
      ctx.strokeStyle = '#ffd8e2'; ctx.beginPath(); ctx.moveTo(66, 326); ctx.lineTo(466, 326); ctx.stroke();
      infoRow(382, '🕐', 'Цаг', d.time, '', '');
    }

    ctx.save();
    drawSoftShadow(ctx, 'rgba(116,45,88,.13)', 24, 12);
    ctx.fillStyle = '#ffffff';
    roundedRect(ctx, 42, 476, 448, 84, 22); ctx.fill();
    ctx.restore();
    ctx.strokeStyle = '#ffd0dc'; ctx.lineWidth = 1;
    roundedRect(ctx, 42, 476, 448, 84, 22); ctx.stroke();
    ctx.textAlign = 'center';
    ctx.fillStyle = '#8c7d95'; ctx.font = '800 14px Nunito, Arial, sans-serif';
    centerText(ctx, 'Дурсгалын тикет · Үйлчилгээний эрх биш', 266, 505, 410);
    ctx.fillStyle = '#4b173f'; ctx.font = '900 28px Nunito, Arial, sans-serif';
    centerText(ctx, String(d.ticketNo || 'Хамтдаа'), 266, 537, 390);
    ctx.fillStyle = '#8c7d95'; ctx.font = '700 11px Nunito, Arial, sans-serif';
    centerText(ctx, 'Үйлчилгээний төлбөр, захиалга ороогүй', 266, 553, 410);

    var cd = d.countdownParts || {};
    ctx.save();
    var cg = ctx.createLinearGradient(42, 592, 490, 680);
    cg.addColorStop(0, '#ffe5ee'); cg.addColorStop(.55, '#ffd4e6'); cg.addColorStop(1, '#fff0f6');
    drawSoftShadow(ctx, 'rgba(169,65,109,.18)', 30, 16);
    ctx.fillStyle = cg;
    roundedRect(ctx, 42, 590, 448, 112, 24); ctx.fill();
    ctx.restore();
    ctx.fillStyle = 'rgba(255,255,255,.82)';
    ctx.beginPath(); ctx.arc(92, 646, 33, 0, Math.PI*2); ctx.fill();
    ctx.font = '32px Arial, sans-serif'; ctx.textAlign = 'center'; centerText(ctx, '💘', 92, 658, 60);
    ctx.fillStyle = '#7e7388'; ctx.font = '800 15px Nunito, Arial, sans-serif';
    centerText(ctx, d.countdownParts ? 'Болзоонд үлдсэн хугацаа' : 'Хамт хийх жижиг зүйлс', 285, 626, 300);
    if(!d.countdownParts){
      ctx.fillStyle = '#4b173f'; ctx.font = '900 26px Nunito, Arial, sans-serif';
      centerText(ctx, 'Өөрсдийнхөө хэмнэлээр ♡', 285, 670, 300);
      ctx.restore();
      return;
    }
    ctx.fillStyle = '#4b173f'; ctx.font = '900 37px Nunito, Arial, sans-serif';
    centerText(ctx, cd.days || '00', 206, 670, 70);
    centerText(ctx, cd.hours || '00', 300, 670, 70);
    centerText(ctx, cd.mins || '00', 394, 670, 70);
    ctx.fillStyle = '#5f5269'; ctx.font = '900 13px Nunito, Arial, sans-serif';
    centerText(ctx, 'өдөр', 206, 692, 70);
    centerText(ctx, 'цаг', 300, 692, 70);
    centerText(ctx, 'мин', 394, 692, 70);
    ctx.restore();
  }

  function drawSaveInvite(d){
    var isStory = d.mode === 'story';
    var W = isStory ? 1080 : 640, H = isStory ? 1920 : 860, S = 2;
    var canvas = document.createElement('canvas');
    canvas.width = W*S; canvas.height = H*S;
    var ctx = canvas.getContext('2d');
    ctx.scale(S, S);
    var bg = ctx.createLinearGradient(0, 0, W, H);
    bg.addColorStop(0, '#fff6ef'); bg.addColorStop(.55, '#fff0f2'); bg.addColorStop(1, '#f4eaff');
    ctx.fillStyle = bg; ctx.fillRect(0, 0, W, H);
    ctx.globalAlpha = .55;
    if(isStory){
      ctx.fillStyle = '#ffcba8'; ctx.beginPath(); ctx.arc(120, 180, 220, 0, Math.PI*2); ctx.fill();
      ctx.fillStyle = '#ffd0e0'; ctx.beginPath(); ctx.arc(960, 260, 260, 0, Math.PI*2); ctx.fill();
      ctx.fillStyle = '#dcc9f4'; ctx.beginPath(); ctx.arc(880, 1780, 300, 0, Math.PI*2); ctx.fill();
      ctx.fillStyle = '#ffb3c0'; ctx.beginPath(); ctx.arc(180, 1650, 200, 0, Math.PI*2); ctx.fill();
    } else {
      ctx.fillStyle = '#ffcba8'; ctx.beginPath(); ctx.arc(72, 76, 120, 0, Math.PI*2); ctx.fill();
      ctx.fillStyle = '#ffd0e0'; ctx.beginPath(); ctx.arc(574, 112, 138, 0, Math.PI*2); ctx.fill();
      ctx.fillStyle = '#dcc9f4'; ctx.beginPath(); ctx.arc(512, 800, 160, 0, Math.PI*2); ctx.fill();
    }
    ctx.globalAlpha = 1;
    if(isStory){
      ctx.textAlign = 'center';
      ctx.fillStyle = '#f76a8e'; ctx.font = '800 58px Comfortaa, Arial, sans-serif';
      centerText(ctx, 'bolzoo · Хамтдаа', W/2, 300, W - 80);
      ctx.fillStyle = '#fffdfb';
      roundedRect(ctx, 130, 550, 820, 740, 38); ctx.fill();
      ctx.fillStyle = '#ac526e'; ctx.font = '100px Arial, sans-serif';
      centerText(ctx, '♡', W/2, 735, W - 120);
      ctx.fillStyle = '#4b173f'; ctx.font = '700 62px Comfortaa, Arial, sans-serif';
      centerText(ctx, 'Нэг санаа.', W/2, 900, W - 180);
      centerText(ctx, 'Хоёулангийн дурсамж.', W/2, 1000, W - 180);
      ctx.fillStyle = '#8b6578'; ctx.font = '500 31px Nunito, Arial, sans-serif';
      centerText(ctx, 'Хамтдаа шинэ зүйл хийе.', W/2, 1150, W - 180);
      ctx.fillStyle = '#9a6b84'; ctx.font = '800 34px Nunito, Arial, sans-serif';
      centerText(ctx, 'Болзооны санаа · Хамт хийх зүйлс', W/2, 1570, W - 80);
    } else {
      drawTicketOn(ctx, 54, 58, d);
    }
    var a = document.createElement('a');
    a.download = 'bolzoo-' + (isStory ? 'story' : 'ticket') + '.png';
    a.href = canvas.toDataURL('image/png');
    document.body.appendChild(a);
    a.click();
    a.remove();
  }

  function save(d){
    var run = function(){ drawSaveInvite(d); };
    if(document.fonts && document.fonts.ready){ return document.fonts.ready.then(run); }
    return Promise.resolve().then(run);
  }

  window.BolzooTicket = { save: save };
})();
