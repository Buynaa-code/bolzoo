'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {classify, appointment, readiness, formatTimestamp, safeWebUrl, createCalendar, responseVersion, planPresentation, createPlanCalendar} = require('../assets/responses');
const response = fields => ({id:'invite-1', response:fields});
const scheduled = {dateISO:'2026-09-08', date:'2026 оны 9-р сар 8', time:'02:15'};
const unfold = text => text.replace(/\r\n /g, '');

test('an alternate date stays a proposal even with a selected date and time', () => {
  const inv = response({...scheduled, answer:'later'});
  assert.equal(classify(inv).key, 'later');
  assert.equal(classify(inv).accepted, false);
  assert.equal(classify(inv).hasResponse, true);
  assert.equal(classify(inv).waiting, false);
  assert.equal(createCalendar(inv), null);
});

test('yes counts as accepted before scheduling, no never does', () => {
  assert.equal(classify(response({answer:'yes'})).accepted, true);
  assert.equal(createCalendar(response({answer:'yes'})), null);
  assert.equal(classify(response({...scheduled, answer:'no'})).key, 'declined');
  assert.equal(classify(response({...scheduled, answer:'no'})).accepted, false);
});

test('legacy date responses count as accepted without an answer field', () => {
  assert.equal(classify(response({date:'2026 оны 9-р сар 8'})).accepted, true);
  assert.equal(classify(response({date:'2026.09.08'})).accepted, true);
  assert.equal(classify(response({dateISO:'2026-09-08'})).accepted, true);
  assert.equal(classify(response({dateISO:'2026-02-30'})).accepted, false);
  for(const date of ['bad date', '2026 оны 2-р сар 30', '2026.13.01', '  ', false]){
    assert.equal(classify(response({date})).accepted, false);
  }
});

test('unknown answers never inherit acceptance from a selected date', () => {
  for(const answer of ['maybe', '', 'YES', true, 1, 'constructor']){
    const info = classify(response({...scheduled, answer}));
    assert.equal(info.key, 'unknown');
    assert.equal(info.accepted, false);
    assert.equal(info.hasResponse, true);
  }
});

test('response timestamps and incomplete payloads never appear as waiting', () => {
  for(const payload of [null, {}, undefined, 'bad response', []]){
    const info = classify({response:payload, responded_at:'2026-09-07T06:30:00Z'});
    assert.equal(info.key, 'unknown');
    assert.equal(info.hasResponse, true);
    assert.equal(info.waiting, false);
    assert.match(info.label, /бүрэн/);
  }
  assert.equal(classify(response({sentAt:'2026-09-07T06:30:00Z'})).key, 'unknown');
});

test('opening a link is distinct from a recipient reading or answering', () => {
  assert.equal(classify({}).key, 'unopened');
  assert.equal(classify({}).waiting, true);
  const opened = classify({opened_at:'2026-09-07T00:00:00Z'});
  assert.equal(opened.key, 'waiting');
  assert.match(opened.label, /Линк нээгдсэн/);
  assert.doesNotMatch(opened.label, /уншсан/);
  assert.equal(classify(response({})).hasResponse, false);
});

test('each apology status preserves exactly the recipient choice without acceptance', () => {
  for(const status of ['needs_space', 'read', 'message', 'meet', 'stop']){
    const inv = response({type:'apology', status, ...scheduled, readinessPercent:100});
    const info = classify(inv);
    assert.equal(info.key, status);
    assert.equal(info.accepted, false);
    assert.equal(info.hasResponse, true);
    assert.equal(info.waiting, false);
    assert.equal(createCalendar(inv), null);
  }
  assert.match(classify(response({type:'apology', status:'meet'})).description, /уучилсан гэсэн үг биш/);
  assert.match(classify(response({type:'apology', status:'stop'})).description, /дахин холбоо барихгүй/);
});

test('unknown apology statuses cannot be relabeled as accepted or forgiven', () => {
  for(const status of ['forgiven', '', 'constructor', 'toString', '__proto__']){
    const inv = {config:{experienceType:'apology'}, response:{status, answer:'yes', readinessPercent:100, ...scheduled}};
    assert.equal(classify(inv).key, 'unknown');
    assert.equal(classify(inv).accepted, false);
  }
});

test('expired unanswered apology links stop waiting while existing responses stay visible', () => {
  const inv = {config:{experienceType:'apology', expiresAt:'2026-09-07T00:00:00Z'}};
  const now = '2026-09-07T01:00:00Z';
  assert.equal(classify(inv, now).key, 'expired');
  assert.equal(classify(inv, now).waiting, false);
  assert.equal(classify(inv, now).hasResponse, false);
  assert.equal(classify({...inv, response:{status:'read'}}, now).key, 'read');
  assert.equal(classify({...inv, config:{experienceType:'apology', expiresAt:'bad date'}}, now).key, 'unopened');
  assert.equal(classify({...inv, config:{experienceType:'date', expiresAt:inv.config.expiresAt}}, now).key, 'unopened');
});

test('readiness distinguishes missing data from a genuine zero', () => {
  for(const value of [null, undefined, '', '  ', true, false, [], {}, NaN, Infinity, -1, 101, 'wat', '0x10']){
    assert.equal(readiness(value), null, 'invalid readiness: ' + String(value));
  }
  for(const value of [0, '0', ' 0 ', 60, '60', 100, '100', 42.5]){
    assert.equal(readiness(value), Number(value));
  }
});

test('appointments prefer machine dates and keep free text only as display fallback', () => {
  assert.deepEqual(appointment(response({...scheduled, date:'stale display'})), {
    date:'2026 оны 9-р сарын 8', dateISO:'2026-09-08', time:'02:15', scheduled:true
  });
  assert.deepEqual(appointment({date:'Маргааш', time:'19:30'}), {
    date:'Маргааш', dateISO:'', time:'19:30', scheduled:false
  });
  assert.deepEqual(appointment(null), {date:'', dateISO:'', time:'', scheduled:false});
});

test('invalid calendar dates do not roll into another day or become scheduled', () => {
  for(const dateISO of ['2026-02-29', '2026-02-30', '2026-04-31', '2026-13-01', '2026-00-01', '0000-01-01', '2026-1-01', '2026-01-00']){
    assert.equal(appointment({dateISO, time:'12:00'}).scheduled, false, dateISO);
  }
  assert.equal(appointment({dateISO:'2028-02-29', time:'12:00'}).scheduled, true);
  assert.equal(appointment({dateISO:'2000-02-29', time:'12:00'}).scheduled, true);
  assert.equal(appointment({dateISO:'1900-02-29', time:'12:00'}).scheduled, false);
});

test('missing or malformed time is never replaced with a guessed calendar time', () => {
  for(const time of [undefined, null, '', ' ', '9:30', '24:00', '12:60', '12:00:00', true]){
    const inv = response({answer:'yes', dateISO:'2026-09-08', time});
    assert.equal(appointment(inv).time, '');
    assert.equal(appointment(inv).scheduled, false);
    assert.equal(createCalendar(inv), null);
  }
});

test('timestamps display Ulaanbaatar time and invalid values show a dash', () => {
  const shown = formatTimestamp('2026-09-07T20:30:00Z');
  assert.equal(shown, '2026.09.08 · 04:30');
  assert.equal(formatTimestamp('2026-09-07T10:30:00Z'), '2026.09.07 · 18:30');
  assert.equal(formatTimestamp('2026-12-31T16:00:00Z'), '2027.01.01 · 00:00');
  for(const invalid of [null, undefined, '', ' ', 'bad date', '0', '12', true, false, NaN, '2026-02-30T00:00:00Z', '2026-09-08T24:00:00Z']){
    assert.equal(formatTimestamp(invalid), '—');
  }
});

test('location links accept absolute web URLs and reject executable or relative schemes', () => {
  assert.equal(safeWebUrl('https://maps.example/place?q=coffee'), 'https://maps.example/place?q=coffee');
  assert.equal(safeWebUrl(' http://example.com '), 'http://example.com/');
  for(const unsafe of ['javascript:alert(1)', 'javascript://example.com', 'data:text/html,<script>', 'file:///etc/passwd', '/place', '//example.com', 'https:example.com', 'https://', 'https://exam\nple.com', null]){
    assert.equal(safeWebUrl(unsafe), '', String(unsafe));
  }
});

test('calendar events use explicit Ulaanbaatar times and stable invitation IDs', () => {
  const inv = {...response({...scheduled, answer:'yes'}), config:{recipientName:'Номин', locationName:'Cafe, A; B\\C\n2 давхар'}};
  const result = createCalendar(inv, {now:'2026-09-07T00:00:00Z'});
  const ics = unfold(result);
  assert.match(ics, /^BEGIN:VCALENDAR\r\n/);
  assert.match(ics, /UID:invite-1@bolzoo\r\n/);
  assert.match(ics, /DTSTAMP:20260907T000000Z\r\n/);
  assert.match(ics, /DTSTART:20260907T181500Z\r\n/);
  assert.match(ics, /DTEND:20260907T191500Z\r\n/);
  assert.ok(ics.includes('LOCATION:Cafe\\, A\\; B\\\\C\\n2 давхар\r\n'));
  assert.match(ics, /END:VCALENDAR\r\n$/);
});

test('calendar text cannot inject events and Unicode lines fold by UTF-8 bytes', () => {
  const inv = response({...scheduled, answer:'yes'});
  const title = 'Номин 🌷 '.repeat(15) + '\r\nBEGIN:VEVENT';
  const result = createCalendar(inv, {title, description:'Нэг\rХоёр\nГурав', now:'2026-09-07T00:00:00Z', durationMinutes:90});
  assert.equal((result.match(/(?:^|\r\n)BEGIN:VEVENT\r\n/g) || []).length, 1);
  for(const line of result.split('\r\n')) assert.ok(Buffer.byteLength(line, 'utf8') <= 75);
  assert.ok(unfold(result).includes('SUMMARY:' + title.replace(/\r\n/g, '\\n')));
  assert.match(unfold(result), /DTEND:20260907T194500Z/);
  assert.ok(unfold(result).includes('DESCRIPTION:Нэг\\nХоёр\\nГурав'));
});

test('calendar generation refuses malformed options and unscheduled or unknown responses', () => {
  for(const answer of ['later', 'no', 'maybe']) assert.equal(createCalendar(response({...scheduled, answer})), null);
  assert.equal(createCalendar({...response({...scheduled, answer:'yes'}), id:''}), null);
  for(const durationMinutes of [null, '60', 0, -1, 1441, NaN]){
    assert.equal(createCalendar(response({...scheduled, answer:'yes'}), {durationMinutes}), null);
  }
  assert.equal(createCalendar(response({...scheduled, answer:'yes'}), {now:'invalid'}), null);
});

test('new-response fingerprints are stable across property order and unrelated invitation changes', () => {
  const first={response:{answer:'yes',time:'18:30',dateISO:'2026-10-01'},responded_at:'2026-09-21T01:00:00Z'};
  const reordered={response:{dateISO:'2026-10-01',time:'18:30',answer:'yes'},responded_at:first.responded_at,opened_at:'2026-09-22',owner_token:'private'};
  assert.equal(responseVersion(first),responseVersion(reordered));
  assert.match(responseVersion(first),/^[0-9a-f]{16}$/);
  assert.notEqual(responseVersion(first),responseVersion({...first,response:{...first.response,answer:'later'}}));
  assert.notEqual(responseVersion(first),responseVersion({...first,responded_at:'2026-09-21T01:00:01Z'}));
  assert.equal(responseVersion({opened_at:'2026-09-21'}),'');
});

test('a mutual plan needs exact revision consent and an explicit compatible lifecycle state', () => {
  const plan={id:'plan-1',state:'agreed',revision:3,accepted:{creator:3,partner:2},scheduled_at:'2026-10-01T10:30:00Z'};
  assert.equal(planPresentation(plan),null);
  assert.equal(createPlanCalendar(plan),null);
  const agreed={...plan,accepted:{creator:3,partner:3}};
  assert.equal(planPresentation(agreed).label,'Хоёулаа тохирлоо');
  assert.equal(planPresentation(agreed).time,'18:30');
  assert.equal(planPresentation({...agreed,state:'proposed'}),null);
  assert.equal(planPresentation({...agreed,state:'invented'}),null);
  assert.equal(planPresentation({...agreed,scheduled_at:'2026-10-01T18:30:00'}).scheduled,false);
});

test('plan calendars use agreed plan dates and locations, while proposals and closed dates never export', () => {
  const plan={id:'plan-1',state:'agreed',revision:2,accepted:{creator:2,partner:2},scheduled_at:'2026-12-31T16:05:00Z',title:'Шинэ төлөвлөгөө',location:'Шинэ газар'};
  const output=createPlanCalendar(plan,{now:'2026-09-21T00:00:00Z'});
  assert.match(output,/DTSTART:20261231T160500Z/);
  assert.match(output,/LOCATION:Шинэ газар/);
  assert.match(output,/UID:plan-plan-1@bolzoo/);
  assert.equal(planPresentation(plan).dateISO,'2027-01-01');
  for(const state of ['cancelled','declined','ended'])assert.equal(createPlanCalendar({...plan,state}),null);
  assert.equal(createPlanCalendar({...plan,state:'proposed',accepted:{creator:2,partner:null}}),null);
});
