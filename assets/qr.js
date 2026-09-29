/** Local invitation QR preview and PNG download. Requires vendor/qrcode.js. */
(function(){
  'use strict';
  var cachedUrl = '', cachedImage = null;

  function create(value){
    var url = new URL(value);
    var id = url.searchParams.get('id');
    if(!/^https?:$/.test(url.protocol) || url.username || url.password ||
       !/\/bolzoo(?:\.html)?$/.test(url.pathname) || !id || !id.trim()){
      throw new Error('Урилгын линк олдсонгүй.');
    }
    // Share only the recipient link, even if a caller supplied extra parameters.
    url.search = '?id=' + encodeURIComponent(id);
    url.hash = '';
    if(cachedUrl === url.href && cachedImage) return cachedImage;
    if(typeof window.qrcode !== 'function') throw new Error('QR үүсгэгч ачаалагдаагүй байна.');

    var qr = window.qrcode(0, 'M');
    qr.addData(url.href, 'Byte');
    qr.make();
    var count = qr.getModuleCount(), margin = 4;
    // Whole pixels and a four-module white border keep the exported QR scannable.
    var scale = Math.ceil(1024 / (count + margin * 2));
    var canvas = document.createElement('canvas');
    canvas.width = canvas.height = (count + margin * 2) * scale;
    var context = canvas.getContext('2d');
    if(!context) throw new Error('QR зураг үүсгэж чадсангүй.');
    context.fillStyle = '#ffffff';
    context.fillRect(0, 0, canvas.width, canvas.height);
    context.fillStyle = '#000000';
    for(var row = 0; row < count; row++){
      for(var col = 0; col < count; col++){
        if(qr.isDark(row, col)) context.fillRect((col + margin) * scale, (row + margin) * scale, scale, scale);
      }
    }
    var dataUrl = canvas.toDataURL('image/png');
    if(!/^data:image\/png;base64,/.test(dataUrl)) throw new Error('QR зураг хадгалж чадсангүй.');
    var suffix = id.replace(/[^a-zA-Z0-9_-]/g, '').slice(0, 64) || 'invite';
    cachedImage = {dataUrl: dataUrl, filename: 'bolzoo-qr-' + suffix + '.png'};
    cachedUrl = url.href;
    return cachedImage;
  }

  function download(url, container){
    var result = create(url);
    var link = document.createElement('a');
    link.href = result.dataUrl;
    link.download = result.filename;
    link.hidden = true;
    (container || document.body).appendChild(link);
    try { link.click(); }
    finally { link.remove(); }
    return result;
  }

  window.BolzooQR = {create: create, download: download};
})();
