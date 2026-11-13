// Baut mac/app/: kopiert wallet-werkbank.html als index.html und legt die
// JavaScript-Bibliotheken lokal ab, damit die App auch offline startet.
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const src = join(here, '..', 'wallet-werkbank.html');
const out = join(here, 'app');

// URL im HTML → lokaler Dateiname, mit SHA-256 zur Prüfung des Downloads
const VENDOR = [
  ['https://cdnjs.cloudflare.com/ajax/libs/jszip/3.10.1/jszip.min.js', 'jszip.min.js'],
  ['https://cdnjs.cloudflare.com/ajax/libs/forge/1.3.1/forge.min.js', 'forge.min.js'],
  ['https://cdnjs.cloudflare.com/ajax/libs/qrcode-generator/1.4.4/qrcode.min.js', 'qrcode.min.js'],
  ['https://cdn.jsdelivr.net/npm/jsqr@1.4.0/dist/jsQR.min.js', 'jsQR.min.js']
];
const hashes = JSON.parse(await readFile(join(here, 'vendor-hashes.json'), 'utf8'));

let html = await readFile(src, 'utf8');
await mkdir(join(out, 'vendor'), { recursive: true });
for (const [url, name] of VENDOR) {
  if (!html.includes(`src="${url}"`)) throw new Error(`Skript nicht im HTML gefunden: ${url}`);
  const res = await fetch(url);
  if (!res.ok) throw new Error(`${url}: HTTP ${res.status}`);
  const buf = Buffer.from(await res.arrayBuffer());
  const sha = createHash('sha256').update(buf).digest('hex');
  if (hashes[name] !== sha) throw new Error(`${name}: Prüfsumme stimmt nicht (${sha})`);
  await writeFile(join(out, 'vendor', name), buf);
  html = html.replace(`src="${url}"`, `src="vendor/${name}"`);
  console.log(`✓ ${name}`);
}
await writeFile(join(out, 'index.html'), html);
console.log('✓ app/index.html');
