'use strict';
const { sendJSON } = require('../lib/payment-api');
// Simulation is only exposed by the local server, never by Vercel.
module.exports = async (req, res) => sendJSON(res, 403, { error: 'Mock payment simulation is disabled' });
