const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const projectDir = path.resolve(__dirname, '..');
const packageJsonPath = path.join(projectDir, 'package.json');
const packageLockPath = path.join(projectDir, 'package-lock.json');
const mainSourcePath = path.join(projectDir, 'src', 'main.js');
const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'));
const packageLock = JSON.parse(fs.readFileSync(packageLockPath, 'utf8'));
const mainSource = fs.readFileSync(mainSourcePath, 'utf8');

test('pins Electron 43.4.0 exactly in package metadata and lockfile', () => {
  assert.equal(packageJson.devDependencies.electron, '43.4.0');
  assert.equal(packageLock.packages[''].devDependencies.electron, '43.4.0');
  assert.equal(packageLock.packages['node_modules/electron'].version, '43.4.0');
  assert.match(packageLock.packages['node_modules/electron'].resolved, /electron-43\.4\.0\.tgz$/);
  assert.doesNotMatch(packageJson.devDependencies.electron, /[~^*<>=|]/);
});

test('uses the diagnostic product identity', () => {
  assert.equal(packageJson.productName, 'FloatTabs Monterey Chromium Baseline');
  assert.match(mainSource, /const PRODUCT_NAME = 'FloatTabs Monterey Chromium Baseline';/);
  assert.match(fs.readFileSync(path.join(projectDir, 'scripts', 'build-c0.sh'), 'utf8'), /com\.lost0rz\.FloatTabs\.MontereyChromiumBaseline/);
  assert.doesNotMatch(mainSource, /com\.lost0rz\.FloatTabs(?:['".]|$)/);
});

test('isolates user data and uses the required persistent partition', () => {
  assert.match(mainSource, /app\.setPath\('userData', path\.join\(app\.getPath\('appData'\), PRODUCT_NAME\)\)/);
  assert.match(mainSource, /const PARTITION = 'persist:floattabs-monterey-chromium-c0';/);
  assert.match(mainSource, /const PARTITION = 'persist:/);
  assert.match(mainSource, /partition: PARTITION/);
});

test('keeps remote ChatGPT content under the required security settings', () => {
  assert.match(mainSource, /nodeIntegration: false/);
  assert.match(mainSource, /contextIsolation: true/);
  assert.match(mainSource, /sandbox: true/);
  assert.match(mainSource, /webSecurity: true/);
  assert.match(mainSource, /allowRunningInsecureContent: false/);
  assert.doesNotMatch(mainSource, /\bpreload\s*:/);
  assert.doesNotMatch(mainSource, /remote\s*:/);
});

test('loads the exact baseline URL without request or authentication manipulation', () => {
  assert.match(mainSource, /const INITIAL_URL = 'https:\/\/chatgpt\.com\/';/);
  assert.match(mainSource, /window\.loadURL\(INITIAL_URL\)/);
  assert.doesNotMatch(mainSource, /setUserAgent|userAgent/);
  assert.doesNotMatch(mainSource, /executeJavaScript/);
  assert.doesNotMatch(mainSource, /webRequest|interceptHttp|onBeforeRequest/);
  assert.doesNotMatch(mainSource, /cookies\.(set|remove)|session\.cookies/);
});

test('provides a targeted Chromium session reset action', () => {
  assert.match(mainSource, /label: 'Reset Chromium Session'/);
  assert.match(mainSource, /session\.fromPartition\(PARTITION\)/);
  assert.match(mainSource, /await diagnosticSession\.clearCache\(\)/);
  assert.match(mainSource, /await diagnosticSession\.clearStorageData\(\{ storages: STORAGE_TYPES \}\)/);
  assert.match(mainSource, /await diagnosticSession\.clearAuthCache\(\)/);

  const storageTypesMatch = mainSource.match(/const STORAGE_TYPES = \[([\s\S]*?)\];/);
  assert.ok(storageTypesMatch, 'production STORAGE_TYPES list is present');
  const productionStorageTypes = [...storageTypesMatch[1].matchAll(/'([^']+)'/g)].map((match) => match[1]);
  for (const storageType of [
    'cookies',
    'filesystem',
    'localstorage',
    'shadercache',
    'indexdb',
    'serviceworkers',
    'cachestorage'
  ]) {
    assert.ok(productionStorageTypes.includes(storageType), `production reset includes ${storageType}`);
  }
  assert.equal(productionStorageTypes.includes('indexeddb'), false, 'stale indexeddb token is absent');
});

test('builds only the Intel artifact with a Monterey minimum', () => {
  const buildScript = fs.readFileSync(path.join(projectDir, 'scripts', 'build-c0.sh'), 'utf8');
  assert.match(buildScript, /--platform=darwin/);
  assert.match(buildScript, /--arch=x64/);
  assert.match(buildScript, /LSMinimumSystemVersion -string 12\.0/);
  assert.doesNotMatch(buildScript, /arm64|universal|@electron\/universal/);
});

test('keeps MC-C0 to one ordinary BrowserWindow and no production Swift changes', () => {
  assert.equal((mainSource.match(/new BrowserWindow\(/g) || []).length, 1);
  const changedPaths = execFileSync('git', ['diff', '--name-only', 'd00e184bc588fe763c725a9fad317eb1ac2fe7dd'], {
    cwd: path.resolve(projectDir, '../..'),
    encoding: 'utf8'
  }).trim().split('\n').filter(Boolean);
  assert.equal(changedPaths.some((filePath) => /^(FloatTabs|FloatTabsTests|FloatTabs\.xcodeproj)\//.test(filePath)), false);
});
