'use strict';

const { createDatePlanHandler } = require('../lib/date-plan-handler');
const { createSupabaseDatePlanRepository } = require('../lib/date-plan-repository');

module.exports = createDatePlanHandler({ repo: createSupabaseDatePlanRepository() });
