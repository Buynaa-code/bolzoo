'use strict';

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { supabaseFetch } = require('./payment-api');

const columns = 'id,invite_id,version,document,created_at,updated_at';
const copy = value => value == null ? null : JSON.parse(JSON.stringify(value));

function createSupabaseDatePlanRepository({ fetch: request = supabaseFetch } = {}) {
  async function find(column, value) {
    const rows = await request('GET', '/date_plans?' + column + '=eq.' + encodeURIComponent(value) + '&select=' + columns + '&limit=1');
    return rows && rows[0] || null;
  }
  return {
    async getInvite(id) {
      const rows = await request('GET', '/invites?id=eq.' + encodeURIComponent(id) + '&select=id,owner_token,config&limit=1');
      return rows && rows[0] || null;
    },
    getByInvite: id => find('invite_id', id),
    getById: id => find('id', id),
    async create(row) {
      const rows = await request('POST', '/rpc/create_date_plan', { p_id: row.id, p_invite_id: row.invite_id, p_document: row.document });
      if (!rows || !rows[0]) throw new Error('Date plan creation did not return a row');
      return rows[0];
    },
    async commit(id, expectedVersion, document) {
      const rows = await request('POST', '/rpc/commit_date_plan', { p_id: id, p_expected_version: expectedVersion, p_document: document });
      return rows && rows[0] || null;
    }
  };
}

// The development server is a single Node process. Synchronous read/CAS/rename
// makes each mutation atomic within that process, including multiple factories.
// Hosted/multi-process deployments use PostgreSQL's atomic RPC above.
function createLocalDatePlanRepository({ file, getInvite, now = Date.now }) {
  if (!file || typeof getInvite !== 'function') throw new TypeError('file and getInvite are required');
  function read() {
    try {
      const data = JSON.parse(fs.readFileSync(file, 'utf8'));
      if (!data || typeof data !== 'object' || Array.isArray(data)) throw new Error('Invalid date plan store');
      return data;
    } catch (error) {
      if (error.code === 'ENOENT') return {};
      throw error; // Never replace a corrupt private store with an empty one.
    }
  }
  function write(data) {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const temp = file + '.' + crypto.randomUUID() + '.tmp';
    let fd;
    try {
      fd = fs.openSync(temp, 'wx', 0o600);
      fs.writeFileSync(fd, JSON.stringify(data));
      fs.fsyncSync(fd);
      fs.closeSync(fd); fd = undefined;
      fs.renameSync(temp, file);
    } finally {
      if (fd !== undefined) fs.closeSync(fd);
      try { fs.unlinkSync(temp); } catch (error) { if (error.code !== 'ENOENT') throw error; }
    }
  }
  return {
    async getInvite(id) { return copy(await getInvite(id)); },
    async getByInvite(id) { return copy(Object.values(read()).find(row => row.invite_id === id)); },
    async getById(id) { return copy(read()[id]); },
    async deleteByInvite(id) {
      const data = read();
      const row = Object.values(data).find(item => item.invite_id === id);
      if (!row) return false;
      delete data[row.id];
      write(data);
      return true;
    },
    async create(row) {
      const data = read();
      const existing = Object.values(data).find(item => item.invite_id === row.invite_id);
      if (existing) return copy(existing);
      if (Object.hasOwn(data, row.id)) throw new Error('Date plan id conflict');
      const timestamp = new Date(now()).toISOString();
      const saved = { id: row.id, invite_id: row.invite_id, version: 1, document: copy(row.document), created_at: timestamp, updated_at: timestamp };
      data[row.id] = saved;
      write(data);
      return copy(saved);
    },
    async commit(id, expectedVersion, document) {
      const data = read();
      if (!data[id] || data[id].version !== expectedVersion) return null;
      data[id] = { ...data[id], version: expectedVersion + 1, document: copy(document), updated_at: new Date(now()).toISOString() };
      write(data);
      return copy(data[id]);
    }
  };
}

module.exports = { createSupabaseDatePlanRepository, createLocalDatePlanRepository };
