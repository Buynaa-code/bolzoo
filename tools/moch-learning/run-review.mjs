import { readFile, writeFile, stat } from 'node:fs/promises';
import { resolve } from 'node:path';
import { analyzeSnapshot } from './learning-report.mjs';
import { formatSnapshotReport } from './format-report.mjs';

const [, , inputPath, outputPath, ...extra] = process.argv;
if (!inputPath || extra.length) {
  process.stderr.write('Usage: node run-review.mjs <aggregate-snapshot.json> [report.json|report.md]\n');
  process.exitCode = 2;
} else {
  try {
    if ((await stat(resolve(inputPath))).size > 64 * 1024) throw new Error('Aggregate snapshot exceeds 64 KiB.');
    const input = await readFile(resolve(inputPath), 'utf8');
    if (Buffer.byteLength(input) > 64 * 1024) throw new Error('Aggregate snapshot exceeds 64 KiB.');
    const snapshot = JSON.parse(input);
    const reviewTime = { now: new Date().toISOString() };
    const output = outputPath?.toLowerCase().endsWith('.md')
      ? formatSnapshotReport(snapshot, reviewTime)
      : `${JSON.stringify(analyzeSnapshot(snapshot, reviewTime), null, 2)}\n`;
    if (outputPath) {
      if (resolve(inputPath).toLowerCase() === resolve(outputPath).toLowerCase()) {
        throw new Error('Output must not overwrite the input snapshot.');
      }
      await writeFile(resolve(outputPath), output, { flag: 'wx' });
      process.stdout.write('Report saved. No network request or production change was made.\n');
    } else {
      process.stdout.write(output);
    }
  } catch (error) {
    // Validation errors contain field paths only; never echo the input or raw records.
    const message = error instanceof SyntaxError ? 'Input is not valid JSON.' : error.message;
    process.stderr.write(`Review failed: ${message}\n`);
    process.exitCode = 1;
  }
}
