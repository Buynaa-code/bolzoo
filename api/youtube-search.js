'use strict';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET,OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type'
};

const YOUTUBE_API_KEY = String(process.env.YOUTUBE_API_KEY || process.env.GOOGLE_API_KEY || '');

function sendJSON(res, status, payload, cache) {
  res.statusCode = status;
  Object.keys(CORS).forEach((key) => res.setHeader(key, CORS[key]));
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  if (cache) res.setHeader('Cache-Control', cache);
  res.end(JSON.stringify(payload));
}

function pickThumbnail(thumbnails) {
  const t = thumbnails || {};
  return (t.medium && t.medium.url) || (t.high && t.high.url) || (t.default && t.default.url) || '';
}

function decodeEntities(value) {
  return String(value || '')
    .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(Number(n)))
    .replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCharCode(parseInt(n, 16)))
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>');
}

function youtubeUserError(data) {
  const err = data && data.error;
  const reason = err && err.errors && err.errors[0] && err.errors[0].reason;
  const details = (err && err.details) || [];
  const detailReason = details.map((d) => d && d.reason).filter(Boolean).join(' ');
  const message = (err && err.message) || '';
  if (reason === 'quotaExceeded' || reason === 'dailyLimitExceeded') {
    return 'Өнөөдрийн YouTube хайлтын quota дууссан байна. Маргааш дахин оролдоно уу.';
  }
  if (/API_KEY_SERVICE_BLOCKED|SERVICE_DISABLED|accessNotConfigured/i.test(detailReason + ' ' + message)) {
    return 'Google Cloud дээр YouTube Data API v3 идэвхжээгүй эсвэл API key restriction хайлтыг блоклосон байна.';
  }
  if (reason === 'keyInvalid' || /API key not valid/i.test(message)) {
    return 'YouTube API key буруу байна. Google Cloud credential-ээ шалгана уу.';
  }
  return 'YouTube хайлт хийх үед алдаа гарлаа.';
}

module.exports = async function handler(req, res) {
  if (req.method === 'OPTIONS') return sendJSON(res, 204, {});
  if (req.method !== 'GET') return sendJSON(res, 405, { error: 'GET only' });
  if (!YOUTUBE_API_KEY) {
    return sendJSON(res, 503, {
      error: 'YOUTUBE_API_KEY тохируулаагүй байна.',
      user_error: 'YouTube хайлт түр идэвхгүй байна. API key тохиргоог шалгана уу.'
    });
  }

  try {
    const url = new URL(req.url, 'https://' + req.headers.host);
    const q = String(url.searchParams.get('q') || '').trim();
    const max = Math.max(1, Math.min(10, Number(url.searchParams.get('maxResults') || 10)));
    if (q.length < 2) return sendJSON(res, 400, { error: 'Хайх үг хамгийн багадаа 2 тэмдэгт байна.' });

    const params = new URLSearchParams({
      part: 'snippet',
      type: 'video',
      maxResults: String(max),
      q,
      key: YOUTUBE_API_KEY,
      videoEmbeddable: 'true',
      safeSearch: 'none'
    });

    const response = await fetch('https://www.googleapis.com/youtube/v3/search?' + params.toString());
    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      const reason = data.error && data.error.errors && data.error.errors[0] && data.error.errors[0].reason;
      return sendJSON(res, response.status, {
        error: (data.error && data.error.message) || 'YouTube API error',
        reason: reason || null,
        user_error: youtubeUserError(data)
      });
    }

    const items = (data.items || []).map((item) => {
      const videoId = item.id && item.id.videoId;
      const snippet = item.snippet || {};
      return videoId ? {
        videoId,
        title: decodeEntities(snippet.title),
        channelTitle: decodeEntities(snippet.channelTitle),
        thumbnail: pickThumbnail(snippet.thumbnails),
        publishedAt: snippet.publishedAt || '',
        url: 'https://www.youtube.com/watch?v=' + videoId
      } : null;
    }).filter(Boolean);

    return sendJSON(res, 200, { items }, 'public, s-maxage=86400, stale-while-revalidate=604800');
  } catch (e) {
    return sendJSON(res, 500, {
      error: e.message || 'YouTube search error',
      user_error: 'YouTube хайлт хийх үед алдаа гарлаа.'
    });
  }
};
