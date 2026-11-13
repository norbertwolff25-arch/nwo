'use strict';
// Wallet-Werkbank als Mac-App (Electron-Hülle um wallet-werkbank.html)
const { app, BrowserWindow, Menu, dialog, session, shell } = require('electron');
const fs = require('fs');
const path = require('path');

const OPENABLE = /\.(eml|ics|pkpass|vcf|txt|png|jpe?g|heic|gif|webp|pdf)$/i;
let win = null;
let ready = false; // Seite geladen und Werkbank bereit
const pending = [];

app.setName('Wallet-Werkbank');

/* Dateien an die Werkbank übergeben (Doppelklick, „Öffnen mit“, Dock, Menü) */
function sendFile(p) {
  if (!win || !ready) { pending.push(p); return; }
  try {
    const b64 = fs.readFileSync(p).toString('base64');
    win.webContents.executeJavaScript(`window.werkbankOpen && window.werkbankOpen(${JSON.stringify(path.basename(p))}, ${JSON.stringify(b64)})`);
    if (win.isMinimized()) win.restore();
    win.focus();
  } catch (e) {
    dialog.showErrorBox('Datei nicht lesbar', `${p}\n${e.message}`);
  }
}
app.on('open-file', (e, p) => { e.preventDefault(); sendFile(p); });

if (!app.requestSingleInstanceLock()) app.quit();
app.on('second-instance', (e, argv) => {
  if (win) { if (win.isMinimized()) win.restore(); win.focus(); }
  argv.slice(1).filter(a => OPENABLE.test(a) && fs.existsSync(a)).forEach(sendFile);
});

function createWindow() {
  win = new BrowserWindow({
    width: 1280, height: 900, minWidth: 380, minHeight: 560,
    title: 'Wallet-Werkbank', backgroundColor: '#f4f5f7', show: false,
    webPreferences: { contextIsolation: true, nodeIntegration: false, sandbox: true, spellcheck: true }
  });
  win.once('ready-to-show', () => win.show());
  win.loadFile(path.join(__dirname, 'app', 'index.html'));
  // Links (Recherche-Quellen usw.) im Standardbrowser öffnen
  win.webContents.setWindowOpenHandler(({ url }) => { if (/^https?:/i.test(url)) shell.openExternal(url); return { action: 'deny' }; });
  win.webContents.on('will-navigate', (e, url) => { if (!url.startsWith('file:')) { e.preventDefault(); if (/^https?:/i.test(url)) shell.openExternal(url); } });
  win.webContents.on('did-start-loading', () => { ready = false; });
  win.webContents.on('did-finish-load', () => { ready = true; pending.splice(0).forEach(sendFile); });
  win.on('closed', () => { win = null; ready = false; });
}

async function openDialog() {
  const r = await dialog.showOpenDialog(win, {
    title: 'Datei für die Werkbank öffnen', properties: ['openFile', 'multiSelections'],
    filters: [
      { name: 'Mails, Termine, Karten, Bilder', extensions: ['eml', 'ics', 'pkpass', 'vcf', 'txt', 'png', 'jpg', 'jpeg', 'heic', 'pdf'] },
      { name: 'Alle Dateien', extensions: ['*'] }
    ]
  });
  if (!r.canceled) r.filePaths.forEach(sendFile);
}

function menu() {
  const isMac = process.platform === 'darwin';
  return Menu.buildFromTemplate([
    ...(isMac ? [{ role: 'appMenu' }] : []),
    { label: 'Ablage', submenu: [
      { label: 'Datei öffnen …', accelerator: 'CmdOrCtrl+O', click: openDialog },
      { type: 'separator' },
      isMac ? { role: 'close' } : { role: 'quit' }
    ] },
    { role: 'editMenu', label: 'Bearbeiten' },
    { role: 'viewMenu', label: 'Darstellung' },
    { role: 'windowMenu', label: 'Fenster' },
    { role: 'help', label: 'Hilfe', submenu: [
      { label: 'Projekt auf GitHub', click: () => shell.openExternal('https://github.com/norbertwolff25-arch/nwo') },
      { label: 'Anthropic-API-Schlüssel anlegen', click: () => shell.openExternal('https://console.anthropic.com/settings/keys') }
    ] }
  ]);
}

app.whenReady().then(() => {
  const allowed = new Set(['clipboard-read', 'clipboard-sanitized-write', 'geolocation', 'notifications', 'fullscreen']);
  session.defaultSession.setPermissionRequestHandler((wc, perm, cb) => cb(allowed.has(perm)));
  session.defaultSession.setPermissionCheckHandler((wc, perm) => allowed.has(perm));
  // Exportierte Karten nach dem Speichern im Finder zeigen (z. B. per AirDrop ans iPhone)
  session.defaultSession.on('will-download', (e, item) => {
    item.once('done', (ev, state) => { if (state === 'completed') shell.showItemInFolder(item.getSavePath()); });
  });
  Menu.setApplicationMenu(menu());
  createWindow();
  process.argv.slice(1).filter(a => OPENABLE.test(a) && fs.existsSync(a)).forEach(sendFile);
  app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });
});

app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
