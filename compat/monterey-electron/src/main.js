const path = require('node:path');
const { app, BrowserWindow, Menu, session } = require('electron');

const PRODUCT_NAME = 'FloatTabs Monterey Chromium Baseline';
const PARTITION = 'persist:floattabs-monterey-chromium-c0';
const INITIAL_URL = 'https://chatgpt.com/';
const STORAGE_TYPES = [
  'cookies',
  'filesystem',
  'localstorage',
  'shadercache',
  'websql',
  'indexdb',
  'serviceworkers',
  'cachestorage'
];

let mainWindow = null;
let resettingSession = false;

app.setPath('userData', path.join(app.getPath('appData'), PRODUCT_NAME));

function createWindow() {
  const window = new BrowserWindow({
    width: 1100,
    height: 800,
    webPreferences: {
      partition: PARTITION,
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: true,
      webSecurity: true,
      allowRunningInsecureContent: false
    }
  });

  mainWindow = window;
  window.on('closed', () => {
    if (mainWindow === window) {
      mainWindow = null;
    }
  });
  window.loadURL(INITIAL_URL);
}

async function resetChromiumSession() {
  if (resettingSession) {
    return;
  }

  resettingSession = true;
  try {
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.destroy();
    }

    const diagnosticSession = session.fromPartition(PARTITION);
    await diagnosticSession.clearCache();
    await diagnosticSession.clearStorageData({ storages: STORAGE_TYPES });
    await diagnosticSession.clearAuthCache();
    createWindow();
  } finally {
    resettingSession = false;
  }
}

function installApplicationMenu() {
  Menu.setApplicationMenu(Menu.buildFromTemplate([
    {
      label: 'Diagnostics',
      submenu: [
        {
          label: 'Reset Chromium Session',
          click: () => {
            void resetChromiumSession();
          }
        }
      ]
    }
  ]));
}

app.whenReady().then(() => {
  installApplicationMenu();
  createWindow();

  app.on('activate', () => {
    if (!mainWindow) {
      createWindow();
    }
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});
