// test-windows-electron.js
const http = require('http');
const fs = require('fs');
const path = require('path');

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function getWsUrl(port = 9222) {
  return new Promise((resolve, reject) => {
    http.get(`http://127.0.0.1:${port}/json`, res => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          const list = JSON.parse(data);
          const page = list.find(p => p.type === 'page');
          if (page && page.webSocketDebuggerUrl) {
            resolve(page.webSocketDebuggerUrl);
          } else {
            reject(new Error('No page target found'));
          }
        } catch (e) { reject(e); }
      });
    }).on('error', reject);
  });
}

class CdpClient {
  constructor(wsUrl) {
    this.wsUrl = wsUrl;
    this.ws = null;
    this.id = 1;
    this.pending = new Map();
    this.events = [];
    this.consoleErrors = [];
  }

  async connect() {
    this.ws = new WebSocket(this.wsUrl);
    await new Promise((resolve, reject) => {
      this.ws.onopen = resolve;
      this.ws.onerror = reject;
    });

    this.ws.onmessage = (msg) => {
      const data = JSON.parse(msg.data);
      if (data.id && this.pending.has(data.id)) {
        const { resolve, reject } = this.pending.get(data.id);
        this.pending.delete(data.id);
        if (data.error) reject(data.error);
        else resolve(data.result);
      } else if (data.method) {
        if (data.method === 'Runtime.consoleAPICalled') {
          if (data.params.type === 'error') {
            this.consoleErrors.push(data.params.args.map(a => a.value || a.description).join(' '));
          }
        }
      }
    };
  }

  send(method, params = {}) {
    return new Promise((resolve, reject) => {
      const id = this.id++;
      this.pending.set(id, { resolve, reject });
      this.ws.send(JSON.stringify({ id, method, params }));
    });
  }

  async eval(expr) {
    const res = await this.send('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true });
    if (res.exceptionDetails) {
      throw new Error(res.exceptionDetails.text || 'Eval error');
    }
    return res.result ? res.result.value : undefined;
  }

  async screenshot(outputPath) {
    const res = await this.send('Page.captureScreenshot', { format: 'png' });
    fs.mkdirSync(path.dirname(outputPath), { recursive: true });
    fs.writeFileSync(outputPath, Buffer.from(res.data, 'base64'));
    console.log(`Saved screenshot: ${outputPath}`);
  }

  close() {
    if (this.ws) this.ws.close();
  }
}

async function runTests() {
  console.log('Connecting to Electron CDP on port 9222...');
  const wsUrl = await getWsUrl(9222);
  const client = new CdpClient(wsUrl);
  await client.connect();

  await client.send('Page.enable');
  await client.send('Runtime.enable');
  await client.send('Log.enable');

  console.log('\n--- 1. CONSOLE ERRORS CHECK ---');
  console.log(`Initial Console Errors: ${client.consoleErrors.length}`);

  console.log('\n--- 2. GEOLOCATION GPS TEST (CUSTOM OVERRIDE) ---');
  // Set custom geolocation override for Saki (45.1342, 33.60), accuracy 20m
  await client.send('Emulation.setGeolocationOverride', {
    latitude: 45.1342,
    longitude: 33.60,
    accuracy: 20
  });

  // Click GPS button
  await client.eval("document.getElementById('btnGeo').click()");
  console.log('Clicked GPS button, waiting for fix...');
  await sleep(1500);

  const gpsLocInfo = await client.eval("document.getElementById('locInfo').textContent");
  console.log('locInfo after GPS fix:', gpsLocInfo);
  const inLat = await client.eval("document.getElementById('inLat').value");
  const inLon = await client.eval("document.getElementById('inLon').value");
  console.log(`inLat: ${inLat}, inLon: ${inLon}`);

  await client.screenshot(path.join(__dirname, '..', 'screenshots', 'windows_gps_success.png'));

  console.log('\n--- 3. GEOLOCATION IP FALLBACK TEST ---');
  // Clear geolocation override to make Chromium network location fail (no Google API key on Windows Electron)
  await client.send('Emulation.clearGeolocationOverride');

  // Trigger GPS click and let it fall back to IP
  console.log('Testing IP fallback on Windows...');
  await client.eval("requestLocation()");
  // Wait up to 13s for watch timeout and IP fetch
  await sleep(13500);

  const ipLocInfo = await client.eval("document.getElementById('locInfo').textContent");
  console.log('locInfo after IP fallback:', ipLocInfo);
  await client.screenshot(path.join(__dirname, '..', 'screenshots', 'windows_gps_ip_fallback.png'));

  console.log('\n--- 4. COMPASS & MATHEMATICS VERIFICATION ---');
  // Restore Saki location for accurate Qibla math check
  await client.eval("saveLocationFix(45.1342, 33.60, 20, 'gps')");
  await client.eval("openPage('p-qibla')");
  await sleep(500);

  const qiblaDeg = await client.eval("document.getElementById('qiblaDeg').textContent");
  const qiblaDist = await client.eval("document.getElementById('qiblaDistKm').textContent");
  const declText = await client.eval("document.getElementById('compassNorthNote').textContent");
  console.log(`Qibla Bearing: ${qiblaDeg} (Target: ~165.8°)`);
  console.log(`Qibla Distance: ${qiblaDist} (Target: ~2697 км)`);
  console.log(`Declination Note: ${declText}`);

  // Test math for 3 test headings:
  // 1) Heading 90° (East):
  await client.eval("document.getElementById('simHeading').value = 90; document.getElementById('simHeading').dispatchEvent(new Event('input'))");
  const h90Delta = await client.eval("document.getElementById('deltaVal').textContent");
  const h90Status = await client.eval("document.getElementById('qiblaStatusBox').textContent");
  console.log(`Heading 90° -> Delta: ${h90Delta}, Status: ${h90Status}`);

  // 2) Heading 165.8° (Aligned on Kaaba):
  await client.eval("document.getElementById('simHeading').value = 165.8; document.getElementById('simHeading').dispatchEvent(new Event('input'))");
  const hAlignDelta = await client.eval("document.getElementById('deltaVal').textContent");
  const hAlignStatus = await client.eval("document.getElementById('qiblaStatusBox').textContent");
  console.log(`Heading 165.8° -> Delta: ${hAlignDelta}, Status: ${hAlignStatus}`);

  // 3) Heading 350°:
  await client.eval("document.getElementById('simHeading').value = 350; document.getElementById('simHeading').dispatchEvent(new Event('input'))");
  const h350Delta = await client.eval("document.getElementById('deltaVal').textContent");
  const h350Status = await client.eval("document.getElementById('qiblaStatusBox').textContent");
  console.log(`Heading 350° -> Delta: ${h350Delta}, Status: ${h350Status}`);

  // Capture portrait screenshot
  await client.screenshot(path.join(__dirname, '..', 'screenshots', 'windows_compass_portrait.png'));

  // Test tilt-compensation calculation:
  console.log('\n--- 5. TILT COMPENSATION MATRIX TEST ---');
  const tilt0 = await client.eval("calcTiltCompensatedHeading(0, 0, 0)");
  const tilt45 = await client.eval("calcTiltCompensatedHeading(0, 45, 0)");
  const tilt90 = await client.eval("calcTiltCompensatedHeading(0, 90, 0)");
  console.log(`Pitch 0° (flat): ${tilt0.toFixed(2)}°`);
  console.log(`Pitch 45° (tilted): ${tilt45.toFixed(2)}°`);
  console.log(`Pitch 90° (vertical): ${tilt90.toFixed(2)}°`);

  // Test landscape (screen angle 90)
  const tiltLand = await client.eval("((calcTiltCompensatedHeading(270, 0, 0) + 90) % 360)");
  console.log(`Landscape 90° facing North: ${tiltLand.toFixed(2)}°`);

  // Change window size to landscape and screenshot
  await client.send('Emulation.setDeviceMetricsOverride', {
    width: 780,
    height: 520,
    deviceScaleFactor: 1,
    mobile: false
  });
  await sleep(600);
  await client.screenshot(path.join(__dirname, '..', 'screenshots', 'windows_compass_landscape.png'));

  // Reset metrics
  await client.send('Emulation.clearDeviceMetricsOverride');

  console.log(`\nFinal Console Errors count: ${client.consoleErrors.length}`);
  if (client.consoleErrors.length > 0) {
    console.log('Console Errors:', client.consoleErrors);
  }

  client.close();
  console.log('\nALL ELECTRON TESTS FINISHED SUCCESSFULLY!');
}

runTests().catch(err => {
  console.error('Test error:', err);
  process.exit(1);
});
