'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { parseLocalDateTime, toUtcCompact, buildIcs, icsEscape } = require('../api/invite-ics');

test('parseLocalDateTime reads dateISO + time', () => {
  const dt = parseLocalDateTime({ dateISO: '2026-08-15', time: '19:30' });
  assert.deepEqual(dt, { y: 2026, m: 7, d: 15, hh: 19, mm: 30 });
});

test('parseLocalDateTime returns null when dateISO is missing', () => {
  assert.equal(parseLocalDateTime({ time: '19:30' }), null);
  assert.equal(parseLocalDateTime(null), null);
});

test('parseLocalDateTime defaults time to 18:00', () => {
  const dt = parseLocalDateTime({ dateISO: '2026-08-15' });
  assert.equal(dt.hh, 18);
  assert.equal(dt.mm, 0);
});

test('toUtcCompact converts Ulaanbaatar wall time to UTC with 8h offset', () => {
  // 19:30 UB on 2026-08-15 → 11:30 UTC
  assert.equal(toUtcCompact(2026, 7, 15, 19, 30), '20260815T113000Z');
});

test('toUtcCompact rolls the date backward when UTC is the previous day', () => {
  // 02:00 UB on 2026-08-15 → 18:00 UTC on 2026-08-14
  assert.equal(toUtcCompact(2026, 7, 15, 2, 0), '20260814T180000Z');
});

test('icsEscape handles special characters', () => {
  assert.equal(icsEscape('foo, bar; baz\nqux\\zap'), 'foo\\, bar\\; baz\\nqux\\\\zap');
});

test('buildIcs emits a VCALENDAR with the required VEVENT fields', () => {
  const ics = buildIcs({
    inviteId:    'testAbc12',
    title:       'Bolzoo — Ану · сюрприз',
    description: 'A message',
    location:    'Улаанбаатар',
    start:       '20260815T113000Z',
    end:         '20260815T133000Z',
    host:        'bolzoo.mn'
  });
  assert.match(ics, /^BEGIN:VCALENDAR\r\n/);
  assert.match(ics, /VERSION:2\.0/);
  assert.match(ics, /BEGIN:VEVENT/);
  assert.match(ics, /UID:testAbc12@bolzoo/);
  assert.match(ics, /DTSTART:20260815T113000Z/);
  assert.match(ics, /DTEND:20260815T133000Z/);
  assert.match(ics, /SUMMARY:Bolzoo — Ану · сюрприз/);
  assert.match(ics, /LOCATION:Улаанбаатар/);
  assert.match(ics, /URL:https:\/\/bolzoo\.mn\/bolzoo\.html\?id=testAbc12/);
  assert.match(ics, /END:VCALENDAR\r\n$/);
});
