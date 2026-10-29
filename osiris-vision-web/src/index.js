export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;

    const corsHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    };

    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }

    // 1. Endpoint tra cứu version cập nhật OTA (luôn tươi mới, không cache lâu để nhận diện ngay)
    if (path === '/version.json') {
      try {
        const obj = await env.BUCKET.get('version.json');
        if (obj) {
          return new Response(obj.body, {
            headers: {
              ...corsHeaders,
              'Content-Type': 'application/json; charset=utf-8',
              'Cache-Control': 'no-cache, no-store, must-revalidate',
            },
          });
        }
      } catch (_) {}

      // Fallback mặc định
      const fallback = {
        version: "1.0.0",
        versionCode: 1,
        releasedAt: new Date().toISOString(),
        releaseNotes: "• Nhận diện vật thể thời gian thực bằng camera & video ngoại vi.\n• Vẽ vùng giám sát bằng cảm ứng tay & cảnh báo rung khi vi phạm.\n• Tự động kiểm tra và nâng cấp phiên bản trực tiếp trong app (In-App OTA).",
        android: {
          downloadUrl: "https://vision.jimmyvu.me/dl/OsirisCameraVision-release.apk",
          filename: "OsirisCameraVision-release.apk",
          fileSize: 77908992
        }
      };
      return new Response(JSON.stringify(fallback, null, 2), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json; charset=utf-8',
          'Cache-Control': 'no-cache, no-store, must-revalidate',
        },
      });
    }

    // 2. Endpoint tải file APK tốc độ cao trực tiếp từ R2 kèm Edge CDN Cache & Range support chuẩn
    if (path.startsWith('/dl/')) {
      let filename = path.replace('/dl/', '');
      if (!filename || filename === '') filename = 'OsirisCameraVision-release.apk';

      const hasRange = request.headers.has('range');
      const cache = caches.default;
      const cacheKey = new Request(url.toString(), request);

      // Nếu không có Range và là GET, thử lấy từ Cloudflare Edge Cache
      if (!hasRange && request.method === 'GET') {
        const cached = await cache.match(cacheKey);
        if (cached) return cached;
      }

      let object = await env.BUCKET.get(filename, {
        range: hasRange ? request.headers : undefined,
        onlyIf: request.headers,
      });

      if (!object) {
        object = await env.BUCKET.get('OsirisCameraVision-release.apk', {
          range: hasRange ? request.headers : undefined,
          onlyIf: request.headers,
        });
        if (!object) {
          return new Response('File not found in storage', { status: 404, headers: corsHeaders });
        }
      }

      const headers = new Headers();
      object.writeHttpMetadata(headers);
      headers.set('etag', object.httpEtag);
      headers.set('Content-Type', 'application/vnd.android.package-archive');
      headers.set('Content-Disposition', `attachment; filename="${filename}"`);
      headers.set('Accept-Ranges', 'bytes');
      headers.set('Access-Control-Allow-Origin', '*');
      headers.set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
      headers.set('Access-Control-Allow-Headers', 'Content-Type, Range');
      headers.set('Access-Control-Expose-Headers', 'Content-Length, Content-Range, Accept-Ranges, ETag');
      headers.set('Cache-Control', 'public, max-age=86400');
      headers.set('CDN-Cache-Control', 'public, max-age=604800');

      // CHỈ trả về 206 Partial Content khi client THỰC SỰ gửi header Range!
      if (hasRange && object.range) {
        headers.set('Content-Range', `bytes ${object.range.offset}-${object.range.offset + object.range.length - 1}/${object.size}`);
        headers.set('Content-Length', `${object.range.length}`);
        return new Response(request.method === 'HEAD' ? null : object.body, { headers, status: 206 });
      }

      // Luôn trả về 200 OK chuẩn xác kèm Content-Length khi tải bình thường
      headers.set('Content-Length', `${object.size}`);
      const fullResponse = new Response(request.method === 'HEAD' ? null : object.body, { headers, status: 200 });

      // Lưu vào Cloudflare Edge PoP cache nếu là GET đầy đủ
      if (request.method === 'GET' && !hasRange) {
        try {
          ctx.waitUntil(cache.put(cacheKey, fullResponse.clone()));
        } catch (_) {}
      }

      return fullResponse;
    }

    // 3. Landing page trực quan
    const html = `<!DOCTYPE html>
<html lang="vi">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Osiris Camera Vision — Realtime Edge AI</title>
  <style>
    :root { --primary: #06b6d4; --bg: #090d16; --card: #131b2e; }
    body { margin: 0; font-family: system-ui, -apple-system, sans-serif; background: var(--bg); color: #f8fafc; display: flex; flex-direction: column; align-items: center; justify-content: center; min-height: 100vh; text-align: center; padding: 20px; }
    .badge { background: rgba(6,182,212,0.15); color: var(--primary); padding: 6px 14px; border-radius: 99px; font-weight: 600; font-size: 0.85rem; border: 1px solid rgba(6,182,212,0.3); margin-bottom: 20px; display: inline-block; }
    h1 { font-size: 2.75rem; margin: 0 0 12px 0; background: linear-gradient(to right, #38bdf8, #818cf8); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
    p { max-width: 580px; color: #94a3b8; font-size: 1.1rem; line-height: 1.6; margin: 0 auto 32px auto; }
    .btn { background: var(--primary); color: #020617; text-decoration: none; padding: 14px 32px; border-radius: 12px; font-weight: 700; font-size: 1.1rem; box-shadow: 0 8px 24px rgba(6,182,212,0.3); transition: transform 0.2s, background 0.2s; display: inline-flex; align-items: center; gap: 8px; }
    .btn:hover { transform: translateY(-2px); background: #22d3ee; }
    .card-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 16px; max-width: 780px; width: 100%; margin-top: 48px; text-align: left; }
    .card { background: var(--card); border: 1px solid rgba(255,255,255,0.06); padding: 20px; border-radius: 16px; }
    .card h3 { margin: 0 0 8px 0; font-size: 1.1rem; color: #e2e8f0; }
    .card p { font-size: 0.9rem; margin: 0; color: #64748b; }
  </style>
</head>
<body>
  <div class="badge">🚀 Mobile Edge AI • Chạy 100% Offline</div>
  <h1>Osiris Camera Vision</h1>
  <p>Nhận diện và theo dõi vật thể thời gian thực bằng camera điện thoại và xem lại video ngoại vi. Tăng tốc phần cứng trên chip di động, bảo mật tuyệt đối.</p>
  <a href="/dl/OsirisCameraVision-release.apk" class="btn">
    <svg width="24" height="24" viewBox="0 0 24 24" fill="currentColor"><path d="M17.523 15.3414c-.5511 0-.9993-.4486-.9993-.9997s.4482-.9993.9993-.9993c.551 0 .9993.4482.9993.9993.0001.5511-.4483.9997-.9993.9997m-11.046 0c-.5511 0-.9993-.4486-.9993-.9997s.4482-.9993.9993-.9993c.5511 0 .9993.4482.9993.9993 0 .5511-.4482.9997-.9993.9997m11.4045-6.02l1.9973-3.4592a.416.416 0 00-.1521-.5676.416.416 0 00-.5676.1521l-2.0223 3.503C15.5896 8.4116 13.8576 8 12 8s-3.5896.4116-5.1368.9507L4.8409 5.4477a.416.416 0 00-.5676-.1521.416.416 0 00-.1521.5676l1.9973 3.4592C2.6889 11.1867.3432 14.6589 0 18.761h24c-.3432-4.1021-2.6889-7.5743-6.1185-9.4396"/></svg>
    Tải APK Cài Đặt (Android)
  </a>

  <div class="card-grid">
    <div class="card">
      <h3>⚡ Camera Realtime</h3>
      <p>Quét trực tiếp từng khung hình, nhận diện Người, Xe cộ, Đồ dùng với tốc độ cao.</p>
    </div>
    <div class="card">
      <h3>🎯 Vẽ Vùng Bằng Cảm Ứng</h3>
      <p>Dùng ngón tay khoanh vùng cấm ngay trên màn hình để báo động khi có xâm nhập.</p>
    </div>
    <div class="card">
      <h3>🔄 Tự Động Cập Nhật OTA</h3>
      <p>Ứng dụng tự phát hiện bản phát hành mới qua hệ thống JimmyVu Edge Stack.</p>
    </div>
  </div>
</body>
</html>`;

    return new Response(html, {
      headers: { ...corsHeaders, 'Content-Type': 'text/html; charset=utf-8' },
    });
  },
};
