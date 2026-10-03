const assert = require('assert');

// Mock localStorage
const mockStorage = {};
const localStorage = {
  getItem: (k) => mockStorage[k] || null,
  setItem: (k, v) => { mockStorage[k] = String(v); },
  removeItem: (k) => { delete mockStorage[k]; }
};

let notificationLog = [];
function notify(title, body) {
  notificationLog.push({ title, body, timestamp: Date.now() });
}

function formatDateKey(d) {
  const dd = String(d.getDate()).padStart(2, '0');
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const yyyy = d.getFullYear();
  return `${dd}-${mm}-${yyyy}`;
}

const PRAYERS_RU = {
  Fajr: 'Фаджр 🌅',
  Dhuhr: 'Зухр ☀️',
  Asr: 'Аср 🌤',
  Maghrib: 'Магриб 🌇',
  Isha: 'Иша 🌙'
};

const S = {
  notif10: true,
  notif0: true
};

function checkNotif(diff, nextPrayer) {
  if (!nextPrayer) return;
  const dateKey = formatDateKey(nextPrayer.date);
  const k10 = `n10_${nextPrayer.key}_${dateKey}`;
  const k0 = `n0_${nextPrayer.key}_${dateKey}`;

  // 10 min warning (within last 10 minutes, but before prayer time)
  if (S.notif10 && diff <= 10 * 60 * 1000 && diff > 0 && !localStorage.getItem(k10)) {
    localStorage.setItem(k10, '1');
    notify('Подготовка к молитве', `Осталось 10 минут до: ${PRAYERS_RU[nextPrayer.key]}. Время совершить омовение (вуду).`);
  }

  // 0 min exact prayer time
  if (S.notif0 && diff <= 0 && !localStorage.getItem(k0)) {
    localStorage.setItem(k0, '1');
    notify(`Время намаза: ${PRAYERS_RU[nextPrayer.key]}`, `Наступило время молитвы ${PRAYERS_RU[nextPrayer.key]}.`);
  }
}

const mockPrayer = {
  key: 'Dhuhr',
  date: new Date(2026, 9, 3, 12, 19, 0)
};

// 15 mins before (900,000 ms) -> no notification
checkNotif(15 * 60 * 1000, mockPrayer);
assert.strictEqual(notificationLog.length, 0);

// 9 mins before (540,000 ms) -> triggers 10m notification
checkNotif(9 * 60 * 1000, mockPrayer);
assert.strictEqual(notificationLog.length, 1);
assert.strictEqual(notificationLog[0].title, 'Подготовка к молитве');
assert.strictEqual(localStorage.getItem('n10_Dhuhr_03-10-2026'), '1');

// 8 mins before (480,000 ms) -> should NOT trigger duplicate 10m notification
checkNotif(8 * 60 * 1000, mockPrayer);
assert.strictEqual(notificationLog.length, 1);

// 0 min exact -> triggers 0m notification
checkNotif(0, mockPrayer);
assert.strictEqual(notificationLog.length, 2);
assert.strictEqual(notificationLog[1].title, 'Время намаза: Зухр ☀️');
assert.strictEqual(localStorage.getItem('n0_Dhuhr_03-10-2026'), '1');

// Next second (-1000 ms) -> should NOT trigger duplicate 0m notification
checkNotif(-1000, mockPrayer);
assert.strictEqual(notificationLog.length, 2);

console.log('All Notification deduplication tests PASSED!');
