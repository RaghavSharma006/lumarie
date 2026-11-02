const http = require('http');
const fs = require('fs');
const path = require('path');

const root = fs.existsSync(path.join(process.cwd(), 'web', 'index.html'))
  ? path.resolve(process.cwd(), 'web')
  : path.resolve(process.cwd(), 'apps', 'mobile', 'build', 'web');
if (!fs.existsSync(path.join(root, 'index.html'))) {
  process.stderr.write('Flutter Web build missing. Run flutter build web --release in apps/mobile.\n');
  process.exit(1);
}

const types = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.webp': 'image/webp',
  '.svg': 'image/svg+xml', '.wasm': 'application/wasm', '.otf': 'font/otf',
  '.ttf': 'font/ttf', '.ico': 'image/x-icon',
};

http.createServer((req, res) => {
  const raw = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
  const requested = path.resolve(root, '.' + raw);
  if (requested !== root && !requested.startsWith(root + path.sep)) {
    res.writeHead(403); res.end(); return;
  }
  const file = fs.existsSync(requested) && fs.statSync(requested).isFile()
    ? requested : path.join(root, 'index.html');
  res.setHeader('Content-Type', types[path.extname(file)] || 'application/octet-stream');
  res.setHeader('Cache-Control', 'no-store');
  fs.createReadStream(file).pipe(res);
}).listen(8787, '127.0.0.1', () => {
  process.stdout.write('Lumairie simulator: http://localhost:8787\n');
});
