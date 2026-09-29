import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fetchSnapshot } from './fetch-snapshot.mjs';
import { analyzeSnapshot } from './learning-report.mjs';
import { formatSnapshotReport } from './format-report.mjs';

// Server-to-server credentials stay in the caller's environment, never in a URL,
// browser bundle, printed command, or saved report. This CLI schedules nothing.
const [, , outputPath, ...extra] = process.argv;
try {
  if (extra.length || (outputPath && !/\.(md|json)$/i.test(outputPath))) {
    throw new Error('Usage: node tools/moch-learning/read-overview.mjs [new-report.md|new-report.json]');
  }
  const { MOCH_READER_URL: url, MOCH_READER_TOKEN: token } = process.env;
  let { MOCH_READER_FROM: from, MOCH_READER_TO: to } = process.env;
  if (Boolean(from) !== Boolean(to)) throw new Error('Set both MOCH_READER_FROM and MOCH_READER_TO, or neither.');
  if (!from) {
    // Seven completed calendar days in Ulaanbaatar (UTC+08:00).
    const shifted = new Date(Date.now() + 8 * 3600000);
    const end = Date.UTC(shifted.getUTCFullYear(), shifted.getUTCMonth(), shifted.getUTCDate()) - 8 * 3600000;
    from = new Date(end - 7 * 86400000).toISOString();
    to = new Date(end).toISOString();
  }
  const snapshot = await fetchSnapshot({ url, token, from, to });
  const reviewTime = { now: new Date().toISOString() };
  const output = outputPath?.toLowerCase().endsWith('.json')
    ? JSON.stringify(analyzeSnapshot(snapshot, reviewTime), null, 2) + '\n'
    : formatSnapshotReport(snapshot, reviewTime);
  if (outputPath) {
    await mkdir(dirname(resolve(outputPath)), { recursive: true });
    await writeFile(resolve(outputPath), output, { flag: 'wx' });
    process.stdout.write('Тайлан хадгаллаа. Зөвхөн нэгтгэсэн мэдээлэл уншсан; сайтад өөрчлөлт хийгээгүй.\n');
  } else process.stdout.write(output);
} catch (error) {
  process.stderr.write(`Тайлан гарсангүй: ${error.message}\n`);
  process.exitCode = 1;
}
