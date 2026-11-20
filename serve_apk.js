const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = 8080;
const APK_PATH = path.join(__dirname, 'Tirvona-Field-Agent.apk');

const server = http.createServer((req, res) => {
  if (req.url === '/download' || req.url === '/Tirvona-Field-Agent.apk') {
    if (!fs.existsSync(APK_PATH)) {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      return res.end('APK file not found');
    }
    const stat = fs.statSync(APK_PATH);
    res.writeHead(200, {
      'Content-Type': 'application/vnd.android.package-archive',
      'Content-Length': stat.size,
      'Content-Disposition': 'attachment; filename="Tirvona-Field-Agent.apk"',
    });
    fs.createReadStream(APK_PATH).pipe(res);
  } else {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(`
      <!DOCTYPE html>
      <html>
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Tirvona Field Agent APK Download</title>
        <style>
          body { font-family: -apple-system, sans-serif; text-align: center; padding: 40px 20px; background: #f8fafc; }
          .card { background: white; max-width: 420px; margin: 0 auto; padding: 30px; border-radius: 20px; box-shadow: 0 10px 25px rgba(0,0,0,0.08); }
          h2 { color: #0f172a; margin-bottom: 8px; }
          p { color: #64748b; font-size: 14px; margin-bottom: 24px; }
          .btn { display: block; background: #0066cc; color: white; padding: 16px; border-radius: 12px; font-weight: bold; font-size: 16px; text-decoration: none; box-shadow: 0 4px 12px rgba(0,102,204,0.3); }
          .btn:active { transform: scale(0.98); }
          .meta { margin-top: 16px; font-size: 12px; color: #94a3b8; }
        </style>
      </head>
      <body>
        <div class="card">
          <div style="font-size: 48px; margin-bottom: 12px;">📲</div>
          <h2>Tirvona Field Agent</h2>
          <p>Latest Release APK with Mandatory Location Permission and Shift Attendance</p>
          <a class="btn" href="/download">⬇️ Download APK (55 MB)</a>
          <div class="meta">Version: Latest • Updated: Just now</div>
        </div>
      </body>
      </html>
    `);
  }
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`APK Download Server running at http://localhost:${PORT}/ and http://192.168.1.8:${PORT}/`);
});
