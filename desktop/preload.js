// desktop/preload.js - Secure bridge for Electron desktop features
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('NamazDesktop', {
  isDesktop: true,
  updateTray: (data) => ipcRenderer.send('update-tray', data),
  syncConfig: (cfg) => ipcRenderer.send('sync-config', cfg)
});