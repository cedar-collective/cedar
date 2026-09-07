// Synthetic acceptance shares the report tour instead of maintaining a second
// Course Dynamics walkthrough. Each report selects its authored fixture case.
import { runReportChecks } from './reports-smoke.test.mjs';

await runReportChecks({ scope: 'all', synthetic: true });
