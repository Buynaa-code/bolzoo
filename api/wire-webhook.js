'use strict';
module.exports = require('../lib/payment-handlers').handlers(require('../lib/payment-repository')).webhook;
// vercel.json disables Node body helpers at build/runtime so this handler
// receives the original signed bytes rather than a consumed request stream.
