// sync-assets.js — копирует PWA в desktop/app, чтобы приложение работало офлайн
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const dst = path.join(__dirname, 'app');
fs.mkdirSync(dst, { recursive: true });

const files = ['index.html', 'sw.js', 'manifest.json', 'icon-192.png', 'icon-512.png'];
for (const f of files) {
  fs.copyFileSync(path.join(root, f), path.join(dst, f));
}

const buildDir = path.join(__dirname, 'build');
fs.mkdirSync(buildDir, { recursive: true });
fs.copyFileSync(path.join(root, 'icon-512.png'), path.join(buildDir, 'icon.png'));

console.log('synced', files.length, 'files to desktop/app');
