'use strict';
const { supabaseFetch } = require('./payment-api');
const select = 'id,status,amount,amount_minor,currency,provider,provider_intent_id,next_action,code,created_at,expires_at,checkout_token_hash,return_to_create,return_origin,payment_description,livemode';
async function find(column, value) {
  const rows = await supabaseFetch('GET', '/payments?' + column + '=eq.' + encodeURIComponent(value) + '&select=' + select + '&limit=1');
  return rows && rows[0] || null;
}
module.exports = {
  get: (id) => find('id', id),
  findByToken: (hash) => find('checkout_token_hash', hash),
  findByProvider: (id) => find('provider_intent_id', id),
  async insert(row) {
    await supabaseFetch('POST', '/payments?on_conflict=id', row, 'resolution=ignore-duplicates');
    const saved = await find('id', row.id);
    if (!saved) throw new Error('Payment was not saved');
    return saved;
  },
  async bindProvider(id, providerId) {
    // Compare-and-set only the linkage. Never replace status/code/amount on a
    // concurrent retry or after a successful webhook has reconciled this row.
    await supabaseFetch('PATCH', '/payments?id=eq.' + encodeURIComponent(id) + '&provider_intent_id=is.null',
      { provider_intent_id: providerId, updated_at: new Date().toISOString() });
    const saved = await find('id', id);
    if (!saved) throw new Error('Payment reservation not found');
    return saved;
  },
  async reconcile(id, remote) {
    const rows = await supabaseFetch('POST', '/rpc/reconcile_wire_payment', { p_id: id, p_remote: remote });
    if (!rows || !rows[0]) throw new Error('Payment reconciliation returned no row');
    return rows[0];
  },
  async hasEvent(id) {
    const rows = await supabaseFetch('GET', '/webhook_events?id=eq.' + encodeURIComponent(id) + '&select=id&limit=1');
    return !!(rows && rows.length);
  },
  recordEvent: (event, id) => supabaseFetch('POST', '/webhook_events?on_conflict=id',
    { id: event.id, type: event.type, intent_id: id, raw: event }, 'resolution=ignore-duplicates')
};
