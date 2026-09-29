'use strict';

const crypto = require('node:crypto');
const INVITE_ID = /^[A-Za-z0-9_-]{8,64}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SECRET = /^[A-Za-z0-9_-]{43,128}$/;
const REQUEST_ID = /^[A-Za-z0-9_-]{16,80}$/;
const STEP_IDS = ['before', 'together', 'after'];
const OUTCOMES = new Set(['todo', 'done', 'skipped', 'adapted']);
const PLAN_KEYS = ['template_id', 'title', 'scheduled_at', 'location', 'budget', 'steps'];
const COMMON_KEYS = ['action', 'invite_id', 'request_id', 'expected_version'];
const ACTION_KEYS = {
  create: [...PLAN_KEYS, 'claim_token'], claim: ['claim_token', 'participant_token'],
  propose: PLAN_KEYS, accept: ['expected_revision'], start: [], outcome: ['step_id', 'outcome'],
  end: [], decline: [], cancel: [], memory: ['text'], rotate_claim: ['claim_token']
};
const messages = {
  invalid_request: 'Мэдээллээ шалгаад дахин оролдоно уу.', forbidden: 'Энэ болзоог нээх хувийн эрх олдсонгүй.',
  plan_not_found: 'Болзооны төлөвлөгөө хараахан үүсээгүй байна.', plan_exists: 'Энэ урилгад болзооны төлөвлөгөө үүссэн байна.',
  conflict: 'Төлөвлөгөө шинэчлэгдсэн байна. Шинэ мэдээллийг ачаалаад дахин оролдоно уу.',
  replay_conflict: 'Энэ хүсэлтийн дугаар өөр өөрчлөлтөд ашиглагдсан байна.',
  invalid_state: 'Болзооны одоогийн төлөвт энэ үйлдлийг хийх боломжгүй.',
  expired: 'Энэ болзооны хувийн эрхийн хугацаа дууссан байна.',
  claim_used: 'Энэ холбоосыг өөр төхөөрөмж дээр хүлээн авсан байна. Урилга илгээгчээс шинэ холбоос аваарай.',
  claim_expired: 'Хамтрагчаар нэгдэх холбоосын хугацаа дууссан байна. Урилга илгээгчээс шинэ холбоос аваарай.',
  apology_invite: 'Энэ хэсэг болзооны урилгад зориулагдсан.'
};
function fail(status, code) { const error = new Error(messages[code] || messages.invalid_request); error.status = status; error.code = code; error.publicMessage = true; throw error; }
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
function equal(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  return crypto.timingSafeEqual(Buffer.from(hash(a)), Buffer.from(hash(b)));
}
const clone = value => JSON.parse(JSON.stringify(value));
function object(value) { return value && typeof value === 'object' && !Array.isArray(value); }
function canonical(value) {
  if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']';
  if (object(value)) return '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}';
  return JSON.stringify(value);
}
function textField(value, max, required = false) {
  if (typeof value !== 'string' || value.length > max || /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/.test(value)) fail(400, 'invalid_request');
  const normalized = value.trim();
  if (required && !normalized) fail(400, 'invalid_request');
  return normalized;
}
function validateBody(body) {
  if (!object(body) || typeof body.action !== 'string' || !Object.hasOwn(ACTION_KEYS, body.action)) fail(400, 'invalid_request');
  if (typeof body.invite_id !== 'string' || !INVITE_ID.test(body.invite_id)) fail(400, 'invalid_request');
  if (typeof body.request_id !== 'string' || !REQUEST_ID.test(body.request_id)) fail(400, 'invalid_request');
  const allowed = new Set([...COMMON_KEYS, ...ACTION_KEYS[body.action]]);
  if (Object.keys(body).some(key => !allowed.has(key))) fail(400, 'invalid_request');
  if (!['create', 'claim'].includes(body.action) && (!Number.isSafeInteger(body.expected_version) || body.expected_version < 1)) fail(400, 'invalid_request');
  if (['create', 'claim', 'rotate_claim'].includes(body.action) && (typeof body.claim_token !== 'string' || !SECRET.test(body.claim_token))) fail(400, 'invalid_request');
  if (body.action === 'claim' && (typeof body.participant_token !== 'string' || !SECRET.test(body.participant_token) || equal(body.claim_token, body.participant_token))) fail(400, 'invalid_request');
  if (body.action === 'accept' && (!Number.isSafeInteger(body.expected_revision) || body.expected_revision < 1)) fail(400, 'invalid_request');
  if (body.action === 'outcome' && (!STEP_IDS.includes(body.step_id) || !OUTCOMES.has(body.outcome))) fail(400, 'invalid_request');
  if (body.action === 'memory') textField(body.text, 2000);
}

function createDatePlanService({ repo, now = Date.now, uuid = crypto.randomUUID, catalog }) {
  // Catalog is shared with the browser; dependency injection keeps service tests focused.
  const ideas = catalog || require('../assets/mission-catalog');
  function planFields(body, current, invite) {
    const templateId = body.template_id === undefined ? (current && current.template_id || invite.config && invite.config.missionIdeaId) : body.template_id;
    const template = typeof templateId === 'string' && ideas.get(templateId);
    const changedTemplate = !current || current.template_id !== templateId;
    if (changedTemplate && !template) fail(400, 'invalid_request');
    // A saved plan is an editorial snapshot. Retiring or updating the live
    // catalogue must not relabel existing steps or block practical date edits.
    const fields = { template_id: templateId, template_version: changedTemplate ? template.version || 1 : current.template_version || 1 };
    fields.title = textField(body.title === undefined ? (!changedTemplate ? current.title : template.title) : body.title, 120, true);
    fields.location = textField(body.location === undefined ? (current && current.location || '') : body.location, 240);
    fields.budget = textField(body.budget === undefined ? (current && current.budget || '') : body.budget, 120);
    const date = body.scheduled_at === undefined ? (current && current.scheduled_at || null) : body.scheduled_at;
    if (date == null || date === '') fields.scheduled_at = null;
    else {
      if (typeof date !== 'string' || date.length > 40 || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d{1,3})?)?(?:Z|[+-]\d{2}:\d{2})$/.test(date) || !Number.isFinite(Date.parse(date))) fail(400, 'invalid_request');
      const [year, month, day] = date.slice(0, 10).split('-').map(Number);
      const [hour, minute] = date.slice(11, 16).split(':').map(Number);
      const seconds = date.slice(16).match(/^:(\d{2})/);
      const calendarDate = new Date(Date.UTC(year, month - 1, day));
      if (year < 2000 || year > 2100 || hour > 23 || minute > 59 || (seconds && Number(seconds[1]) > 59) || calendarDate.getUTCFullYear() !== year || calendarDate.getUTCMonth() !== month - 1 || calendarDate.getUTCDate() !== day) fail(400, 'invalid_request');
      fields.scheduled_at = new Date(date).toISOString();
    }
    const inputSteps = body.steps === undefined ? (!changedTemplate ? current.steps.map(({ id, text }) => ({ id, text })) : template.steps.map(step => ({ id: step.id, text: step.title + (step.description ? ' — ' + step.description : '') }))) : body.steps;
    if (!Array.isArray(inputSteps) || inputSteps.length !== 3) fail(400, 'invalid_request');
    fields.steps = inputSteps.map((step, i) => {
      if (!object(step) || Object.keys(step).some(key => !['id', 'text'].includes(key)) || step.id !== STEP_IDS[i]) fail(400, 'invalid_request');
      return { id: step.id, text: textField(step.text, 600, true), outcomes: { creator: 'todo', partner: 'todo' } };
    });
    return fields;
  }
  function roleFor(invite, row, token) {
    if (typeof token !== 'string') return null;
    if (UUID.test(token) && equal(String(invite.owner_token || '').toLowerCase(), token.toLowerCase())) return 'creator';
    if (row && SECRET.test(token) && equal(row.document.participant_token_hash, hash(token))) return 'partner';
    return null;
  }
  function active(row) {
    if (!row.document || row.document.schema !== 1) throw new Error('Unsupported date plan document');
    if (Date.parse(row.document.expires_at) <= now()) fail(410, 'expired');
  }
  function snapshot(row, role, invite) {
    const d = row.document;
    return {
      id: row.id, invite_id: row.invite_id, version: row.version, revision: d.revision, state: d.state, role,
      template_id: d.template_id, template_version: d.template_version, title: d.title, scheduled_at: d.scheduled_at, location: d.location, budget: d.budget,
      steps: clone(d.steps), accepted: clone(d.accepted), partner_claimed: !!d.participant_token_hash,
      my_memory: d.memories[role] || '', created_at: row.created_at, updated_at: row.updated_at, expires_at: d.expires_at, claim_expires_at: d.claim_expires_at,
      senderName: String(invite.config && invite.config.senderName || '').slice(0, 100),
      recipientName: String(invite.config && invite.config.recipientName || '').slice(0, 100)
    };
  }
  function actorFor(role, body, token) {
    const credential = body.action === 'claim' ? body.participant_token : role === 'creator' ? token.toLowerCase() : token;
    return role + ':' + hash(credential);
  }
  function replay(document, body, actor) {
    const saved = document.requests.find(request => request.id === body.request_id);
    if (!saved) return false;
    if (!equal(saved.actor, actor) || !equal(saved.fingerprint, hash(canonical(body)))) fail(409, 'replay_conflict');
    return true;
  }
  function remember(document, body, actor) {
    document.requests.push({ id: body.request_id, actor, fingerprint: hash(canonical(body)) });
    if (document.requests.length > 256) document.requests.shift();
    document.audit.push({ action: body.action, role: actor.split(':')[0], at: new Date(now()).toISOString(), revision: document.revision });
    if (document.audit.length > 100) document.audit.shift();
  }
  async function get({ invite_id, id }, token) {
    if ((invite_id && !INVITE_ID.test(invite_id)) || (id && !UUID.test(id)) || (!invite_id && !id)) fail(400, 'invalid_request');
    const row = invite_id ? await repo.getByInvite(invite_id) : await repo.getById(id);
    if (!invite_id && !row) fail(403, 'forbidden');
    const invite = await repo.getInvite(invite_id || row.invite_id);
    if (!invite) fail(403, 'forbidden');
    const role = roleFor(invite, row, token);
    if (!role) fail(403, 'forbidden');
    if (!row) fail(404, 'plan_not_found');
    active(row);
    return snapshot(row, role, invite);
  }
  async function execute(body, token = '') {
    validateBody(body);
    const invite = await repo.getInvite(body.invite_id);
    if (!invite) fail(403, 'forbidden');
    let row = await repo.getByInvite(body.invite_id);
    let role = roleFor(invite, row, token);
    if (body.action === 'claim') {
      if (!row || !equal(row.document.claim_token_hash, hash(body.claim_token))) fail(403, 'forbidden');
      active(row);
      if (row.document.participant_token_hash && !equal(row.document.participant_token_hash, hash(body.participant_token))) fail(409, 'claim_used');
      role = 'partner';
    }
    if (!role) fail(403, 'forbidden');
    const actor = actorFor(role, body, token);
    if (row) {
      active(row);
      if (replay(row.document, body, actor)) return snapshot(row, role, invite);
    }
    if (body.action === 'create') {
      if (role !== 'creator') fail(403, 'forbidden');
      if (invite.config && invite.config.experienceType === 'apology') fail(400, 'apology_invite');
      if (row) fail(409, 'plan_exists');
      const document = {
        schema: 1, ...planFields(body, null, invite), revision: 1, state: 'proposed', accepted: { creator: 1, partner: null },
        claim_token_hash: hash(body.claim_token), participant_token_hash: null,
        memories: { creator: '', partner: '' }, requests: [], audit: [], expires_at: new Date(now() + 180 * 86400000).toISOString(),
        claim_expires_at: new Date(now() + 7 * 86400000).toISOString()
      };
      remember(document, body, actor);
      row = await repo.create({ id: uuid(), invite_id: invite.id, document });
      if (!replay(row.document, body, actor)) fail(409, 'plan_exists');
      return snapshot(row, role, invite);
    }
    if (!row) fail(404, 'plan_not_found');
    if (body.action === 'claim') {
      // Claim retries need no public version lookup and never create a new identity.
      for (let attempt = 0; attempt < 3; attempt++) {
        active(row);
        if (!equal(row.document.claim_token_hash, hash(body.claim_token))) fail(403, 'forbidden');
        if (row.document.participant_token_hash) {
          if (!equal(row.document.participant_token_hash, hash(body.participant_token))) fail(409, 'claim_used');
          return snapshot(row, role, invite);
        }
        if (Date.parse(row.document.claim_expires_at) <= now()) fail(410, 'claim_expired');
        if (!['proposed', 'agreed'].includes(row.document.state)) fail(409, 'invalid_state');
        const document = clone(row.document);
        document.participant_token_hash = hash(body.participant_token);
        remember(document, body, actor);
        const saved = await repo.commit(row.id, row.version, document);
        if (saved) return snapshot(saved, role, invite);
        row = await repo.getByInvite(body.invite_id);
        if (!row) fail(403, 'forbidden');
      }
      fail(409, 'conflict');
    }
    if (body.expected_version !== row.version) fail(409, 'conflict');
    const document = clone(row.document);
    const state = document.state;
    function requireState(states) { if (!states.includes(state)) fail(409, 'invalid_state'); }
    switch (body.action) {
      case 'propose':
        requireState(['proposed', 'agreed']);
        Object.assign(document, planFields(body, document, invite));
        document.revision++;
        document.accepted = { creator: null, partner: null };
        document.accepted[role] = document.revision;
        document.state = 'proposed';
        break;
      case 'accept':
        requireState(['proposed', 'agreed']);
        if (body.expected_revision !== document.revision) fail(409, 'conflict');
        document.accepted[role] = document.revision;
        if (document.accepted.creator === document.revision && document.accepted.partner === document.revision) document.state = 'agreed';
        break;
      case 'start':
        requireState(['agreed']);
        if (document.accepted.creator !== document.revision || document.accepted.partner !== document.revision) fail(409, 'invalid_state');
        document.state = 'in_progress';
        break;
      case 'outcome':
        requireState(['in_progress']);
        document.steps.find(step => step.id === body.step_id).outcomes[role] = body.outcome;
        break;
      case 'end': requireState(['in_progress']); document.state = 'ended'; break;
      case 'decline': requireState(['proposed', 'agreed']); document.state = 'declined'; break;
      case 'cancel': requireState(['proposed', 'agreed', 'in_progress']); document.state = 'cancelled'; break;
      case 'memory':
        requireState(['in_progress', 'ended']);
        document.memories[role] = textField(body.text, 2000);
        break;
      case 'rotate_claim':
        if (role !== 'creator') fail(403, 'forbidden');
        requireState(['proposed', 'agreed']);
        if (equal(document.claim_token_hash, hash(body.claim_token))) fail(400, 'invalid_request');
        document.claim_token_hash = hash(body.claim_token);
        document.claim_expires_at = new Date(now() + 7 * 86400000).toISOString();
        document.participant_token_hash = null;
        document.memories.partner = '';
        document.revision++;
        document.accepted = { creator: document.revision, partner: null };
        document.state = 'proposed';
        document.steps.forEach(step => { step.outcomes = { creator: 'todo', partner: 'todo' }; });
        break;
      default: fail(400, 'invalid_request');
    }
    remember(document, body, actor);
    const saved = await repo.commit(row.id, row.version, document);
    if (saved) return snapshot(saved, role, invite);
    const latest = await repo.getByInvite(body.invite_id);
    if (!latest || roleFor(invite, latest, token) !== role) fail(403, 'forbidden');
    if (replay(latest.document, body, actor)) return snapshot(latest, role, invite);
    fail(409, 'conflict');
  }
  return { get, execute };
}

module.exports = { createDatePlanService };
