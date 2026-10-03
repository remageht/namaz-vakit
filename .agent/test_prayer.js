// Verification test for prayer calculation logic
const assert = require('assert');

const timings = {
  Fajr: "04:54",
  Sunrise: "06:36",
  Dhuhr: "12:19",
  Asr: "16:01",
  Maghrib: "18:00",
  Isha: "19:42"
};

const ORDER = ['Fajr', 'Sunrise', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'];
const PRAYERS = ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'];

function parseTime(tstr, baseDate = new Date()) {
  const match = (tstr || '').match(/(\d{1,2}):(\d{2})/);
  if (!match) return null;
  const d = new Date(baseDate);
  d.setHours(parseInt(match[1], 10), parseInt(match[2], 10), 0, 0);
  return d;
}

function formatDateKey(d) {
  const dd = String(d.getDate()).padStart(2, '0');
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const yyyy = d.getFullYear();
  return `${dd}-${mm}-${yyyy}`;
}

function calcNext(timings, now) {
  let found = null;
  for (const k of PRAYERS) {
    const d = parseTime(timings[k], now);
    if (d && d > now) {
      found = { key: k, date: d, isTomorrow: false };
      break;
    }
  }
  if (!found) {
    const d = parseTime(timings['Fajr'], now);
    d.setDate(d.getDate() + 1);
    found = { key: 'Fajr', date: d, isTomorrow: true };
  }
  return found;
}

function formatCountdown(diff) {
  const totalSeconds = Math.max(0, Math.floor(diff / 1000));
  const h = Math.floor(totalSeconds / 3600);
  const m = Math.floor((totalSeconds % 3600) / 60);
  const s = totalSeconds % 60;
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
}

// Test cases:
const base = new Date(2026, 9, 3); // Oct 3, 2026

// Case 1: Early morning before Fajr (03:00) -> next is Fajr today
const t1 = new Date(2026, 9, 3, 3, 0, 0);
const n1 = calcNext(timings, t1);
assert.strictEqual(n1.key, 'Fajr');
assert.strictEqual(n1.isTomorrow, false);
console.log('Test 1 Passed: 03:00 -> Fajr today');

// Case 2: Between Fajr and Sunrise (05:30) -> next is Dhuhr (Sunrise skipped!)
const t2 = new Date(2026, 9, 3, 5, 30, 0);
const n2 = calcNext(timings, t2);
assert.strictEqual(n2.key, 'Dhuhr');
console.log('Test 2 Passed: 05:30 -> Dhuhr (Sunrise correctly skipped)');

// Case 3: Between Dhuhr and Asr (14:00) -> next is Asr
const t3 = new Date(2026, 9, 3, 14, 0, 0);
const n3 = calcNext(timings, t3);
assert.strictEqual(n3.key, 'Asr');
console.log('Test 3 Passed: 14:00 -> Asr');

// Case 4: After Isha (21:00) -> next is Fajr tomorrow
const t4 = new Date(2026, 9, 3, 21, 0, 0);
const n4 = calcNext(timings, t4);
assert.strictEqual(n4.key, 'Fajr');
assert.strictEqual(n4.isTomorrow, true);
assert.strictEqual(n4.date.getDate(), 4); // Oct 4
console.log('Test 4 Passed: 21:00 -> Fajr tomorrow (smooth wrap-around)');

// Deduplication key test
const k10 = `n10_${n4.key}_${formatDateKey(n4.date)}`;
const k0 = `n0_${n4.key}_${formatDateKey(n4.date)}`;
assert.strictEqual(k10, 'n10_Fajr_04-10-2026');
assert.strictEqual(k0, 'n0_Fajr_04-10-2026');
console.log('Test 5 Passed: Deduplication keys:', k10, k0);

// Countdown format test
const diffMs = (2 * 3600 + 15 * 60 + 42) * 1000;
const cd = formatCountdown(diffMs);
assert.strictEqual(cd, '02:15:42');
console.log('Test 6 Passed: Countdown format:', cd);

console.log('ALL UNIT TESTS PASSED!');
