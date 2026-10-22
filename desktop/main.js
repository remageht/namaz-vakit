// main.js — Electron-оболочка «Намаз» (Windows / macOS / Linux)
// Своё окно, трей, уведомления от PWA, автозапуск, офлайн из desktop/app.
const { app, BrowserWindow, Tray, Menu, nativeImage, session, shell } = require('electron');
const path = require('path');

const SMOKE = process.argv.includes('--smoke');
let win = null;
let tray = null;
let quitting = false;

if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.on('second-instance', () => showWin());
}

app.setAppUserModelId('com.remageht.namazvakit');

function showWin() {
  if (!win) return;
  if (win.isMinimized()) win.restore();
  win.show();
  win.focus();
}

function createWindow() {
  win = new BrowserWindow({
    width: 480,
    height: 780,
    minWidth: 400,
    minHeight: 600,
    backgroundColor: '#06281F',
    icon: path.join(__dirname, 'app', 'icon-512.png'),
    autoHideMenuBar: true,
    title: 'Намаз — время и Кибла',
    webPreferences: {
      backgroundThrottling: false,
      spellcheck: false
    }
  });

  win.setMenuBarVisibility(false);
  win.loadFile(path.join(__dirname, 'app', 'index.html'));

  win.on('close', (e) => {
    if (!quitting && !SMOKE) {
      e.preventDefault();
      win.hide();
      if (tray) tray.displayBalloon && tray.displayBalloon({
        title: 'Намаз',
        content: 'Приложение свёрнуто в трей и продолжает напоминать о намазах.'
      });
    }
  });

  win.webContents.on('console-message', (...args) => {
    const d = args[1];
    if (d && typeof d === 'object' && d.message !== undefined) {
      console.log(`[renderer:${d.level}] ${d.message}`);
    } else {
      console.log(`[renderer:${args[1]}] ${args[2]} (${args[4]}:${args[3]})`);
    }
  });

  win.webContents.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url);
    return { action: 'deny' };
  });

  if (SMOKE) {
    let errors = 0;
    win.webContents.on('console-message', (...args) => {
      const d = args[1];
      const level = (d && typeof d === 'object') ? d.level : args[1];
      if (level === 'error' || level === 3) errors++;
    });
    setTimeout(() => {
      console.log(errors === 0 ? 'SMOKE-OK no renderer errors' : `SMOKE-FAIL ${errors} renderer errors`);
      app.quit();
    }, 9000);
  }
}

function allowPermissions() {
  const allow = new Set(['notifications', 'geolocation', 'media']);
  session.defaultSession.setPermissionRequestHandler((wc, permission, cb) => {
    cb(allow.has(permission));
  });
  try {
    session.defaultSession.setPermissionCheckHandler((wc, permission) =>
      allow.has(permission)
    );
  } catch {}
}

function autostartEnabled() {
  try {
    return app.getLoginItemSettings().openAtLogin;
  } catch {
    return false;
  }
}

function buildTrayMenu() {
  return Menu.buildFromTemplate([
    { label: 'Открыть', click: () => showWin() },
    { type: 'separator' },
    {
      label: 'Запускать при входе',
      type: 'checkbox',
      checked: autostartEnabled(),
      click: (mi) => {
        try {
          app.setLoginItemSettings({ openAtLogin: mi.checked });
        } catch {}
      }
    },
    { type: 'separator' },
    {
      label: 'Выход',
      click: () => {
        quitting = true;
        app.quit();
      }
    }
  ]);
}

function createTray() {
  const img = nativeImage.createFromPath(path.join(__dirname, 'app', 'icon-192.png'));
  tray = new Tray(img.resize({ width: 16, height: 16 }));
  tray.setToolTip('Намаз');
  tray.setContextMenu(buildTrayMenu());
  tray.on('double-click', () => showWin());
  if (process.platform === 'win32') {
    tray.on('click', () => showWin());
  }
}

app.whenReady().then(() => {
  allowPermissions();
  createWindow();
  createTray();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
    else showWin();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin' && quitting) app.quit();
});

app.on('before-quit', () => {
  quitting = true;
});
