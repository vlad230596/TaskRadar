// Offline read checks for TaskRadar on a dedicated emulator, the TaskRadar
// port of CashFlow's offline suite (docs/offline-testing-guide.md).
//
//   node tests/android/run-offline.mjs [--pass N]
//
// 1. online:   clear the QA package, sign in through the form, visit the board,
//              the "in work" set and a project's notes so every cache is written
// 2. offline:  radios off AND the API drops connections; cold start -> the
//              cached board within the budget (Android "Fully drawn"), no API
//              answer; project, task, notes and the work set readable; a write
//              fails out loud
// 3. restore:  radios on, the server renamed a task; Повторить -> new title,
//              the stale banner goes
// 4. hanging:  the API accepts and never answers; cold start -> the cached
//              board within the budget with a request really pending; still
//              usable after 30 s; releasing the API refreshes it in place
//
// Settings it touches are restored in `finally`. No retries.
import { mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';
import { Device, find, summarize } from './lib/device.mjs';
import { startFaultServer } from './lib/fault-server.mjs';
import { Recorder, expectGone, expectScreen } from './lib/back-contract.mjs';
import { createTaskRadarApi } from './taskradar/fake-api.mjs';
import { QA, apiStatus, control, freshSignIn } from './taskradar/app.mjs';
import { SCREENS } from './taskradar/back-scenarios.mjs';

const args = process.argv.slice(2);
const pass = args.includes('--pass') ? args[args.indexOf('--pass') + 1] : '1';
const budgetMs = Number(process.env.OFFLINE_STARTUP_BUDGET_MS ?? 2000);
const holdMs = 30000;
const results = fileURLToPath(new URL('./results/', import.meta.url));
const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const device = new Device();
const server = await startFaultServer({ api: createTaskRadarApi(), port: QA.hostPort, log: () => {} });
const rec = new Recorder('offline');
const report = { pass, device: device.serial, budgetMs, started: new Date().toISOString(), startups: [], overBudget: [] };

const saved = {
  wifi: device.setting('global', 'wifi_on'),
  data: device.setting('global', 'mobile_data'),
  handwriting: device.setting('secure', 'stylus_handwriting_enabled'),
};

const see = (step, selector, timeoutMs) => expectScreen(device, rec, step, selector, { timeoutMs });
const tap = async (selector) => {
  device.tap(await device.waitFor((n) => find(n, selector), { what: JSON.stringify(selector) }));
  await pause(500);
};

/** Cold start, then the Android "Fully drawn" time of this launch only. */
async function coldStart(mode) {
  device.forceStop(QA.pkg);
  // Let the system finish tearing the old process down (and settle after a
  // radio change) before the clock starts: the metric is this app's cold
  // start, not the previous process's exit. Measured: launching straight
  // after force-stop adds 0.3-0.5 s of noise on the emulator.
  await pause(2000);
  const marker = randomUUID();
  device.log(QA.logTag, marker);
  const launchedAt = Date.now();
  device.launch(QA.pkg);
  await see(`${mode}: cached board`, { text: 'Купить плитку' }, 15000);
  let line;
  let lines = [];
  const deadline = Date.now() + 5000;
  while (!line && Date.now() < deadline) {
    const log = device.adb(['logcat', '-d', '-v', 'brief', '-s', `${QA.logTag}:I`, 'ActivityTaskManager:I']);
    lines = log.slice(log.lastIndexOf(marker)).split('\n');
    line = lines.find((l) => l.includes(`Fully drawn ${QA.pkg}/`));
    if (!line) await pause(200);
  }
  if (!line) rec.fail(`${mode}: fully drawn`, 'no "Fully drawn" for this launch', summarize(device.dump()));
  const units = { ms: 1, s: 1000, m: 60000 };
  const ms = (l) => [...(l?.match(/\+([\dhms]+)/)?.[1] ?? '').matchAll(/(\d+)(ms|s|m)/g)]
    .reduce((sum, part) => sum + Number(part[1]) * units[part[2]], 0);
  const usefulFrameMs = ms(line);
  const firstFrameMs = ms(lines.find((l) => l.includes(`Displayed ${QA.pkg}/`)));
  report.startups.push({ mode, usefulFrameMs, firstFrameMs, budgetMs, wallClockToTreeMs: Date.now() - launchedAt });
  // Hardware-independent: the cached board is on the first frame Android
  // counts, so nothing between process start and the rows waited for the
  // network. The absolute budget below depends on the emulator.
  if (firstFrameMs && usefulFrameMs - firstFrameMs > 100) {
    rec.fail(`${mode}: cache on the first frame`, `board ${usefulFrameMs - firstFrameMs} ms after the first frame`, []);
  }
  rec.ok(`${mode}: cache on the first frame`, `first ${firstFrameMs} ms, board ${usefulFrameMs} ms`);
  // Over budget fails the pass, but only at the end: one slow cold start must
  // not hide whether the rest of the offline behaviour works.
  if (usefulFrameMs > budgetMs) {
    report.overBudget.push(`${mode}: ${usefulFrameMs} ms > ${budgetMs} ms`);
    rec.steps.push({ step: `${mode}: startup budget`, ok: false, detail: `${usefulFrameMs} ms > ${budgetMs} ms` });
  } else {
    rec.ok(`${mode}: startup budget`, `${usefulFrameMs} ms`);
  }
}

try {
  device.putSetting('secure', 'stylus_handwriting_enabled', 0);
  device.radios(true);
  await device.waitRoute();

  // 1. online: every cache written through the real UI.
  await freshSignIn(device);
  await see('online: board', SCREENS.board);
  await tap({ text: 'Работа' });
  await see('online: work set', { text: 'Купить плитку' });
  await tap({ text: 'План' });
  await tap({ text: 'Ремонт кухни' });
  await tap({ text: 'Заметки' });
  await see('online: notes', { text: 'Размеры' });
  device.back();
  await see('online: back on board', SCREENS.board);
  const warm = Date.now() + 10000;
  const needed = ['/board', '/focus', '/scopes', '/projects/prj_kitchen/notes'];
  while (!needed.every((p) => (apiStatus.cache?.calls ?? []).some((c) => c.path === p && c.completed))) {
    apiStatus.cache = await apiStatus();
    if (Date.now() > warm) rec.fail('online: caches written', `missing ${needed.join(', ')}`, []);
    await pause(200);
  }
  await pause(1000); // the writes behind the answers
  rec.ok('online: caches written');

  // 2. offline.
  await control({ mode: 'offline', resetLog: true });
  device.radios(false);
  if (device.setting('global', 'wifi_on') !== '0') rec.fail('offline: radios', 'Wi-Fi still on', []);
  await coldStart('offline');
  await see('offline: stale banner', { text: 'Показан локальный снимок' });
  if ((await apiStatus()).calls.some((c) => c.completed)) rec.fail('offline: no API answer', 'the API answered', []);
  rec.ok('offline: no API answer');
  await tap({ text: 'Ремонт кухни' });
  await see('offline: project from snapshot', { text: 'Показан локальный снимок' });
  await tap({ text: 'Купить плитку' });
  await see('offline: task opens from snapshot', SCREENS.task);
  device.back();
  await see('offline: back to project', SCREENS.project);
  await tap({ text: 'Отметить сделанной' });
  await see('offline: a write fails out loud', { text: 'Нет связи с сервером' });
  await tap({ text: 'Заметки' });
  await see('offline: notes from the copy', { text: 'Размеры' });
  await see('offline: notes say they are a copy', { text: 'Локальная копия' });
  device.back();
  await tap({ text: 'Работа' });
  await see('offline: work set from the copy', { text: 'Купить плитку' });
  await see('offline: work set says it is a copy', { text: 'Локальная копия' });
  await tap({ text: 'План' });

  // 3. restore, with a change made "elsewhere".
  device.radios(true);
  await device.waitRoute();
  await control({ mode: 'online', mutate: { renameTask: { id: 'tsk_tiles', title: 'Купить плитку и клей' } } });
  await tap({ text: 'Повторить' });
  await see('restore: fresh title', { text: 'Купить плитку и клей' });
  await expectGone(device, rec, 'restore: stale banner gone', { text: 'Показан локальный снимок' });

  // 4. hanging.
  await control({ mode: 'hanging', resetLog: true });
  const holdStarted = Date.now();
  await coldStart('hanging');
  const held = await apiStatus();
  if (!held.pending) rec.fail('hanging: request pending', 'nothing is actually waiting on the API', []);
  if (held.calls.some((c) => c.completed)) rec.fail('hanging: no answer', 'the API answered', []);
  rec.ok('hanging: request pending', `${held.pending} pending`);
  await pause(Math.max(0, holdMs - (Date.now() - holdStarted)));
  // Nothing may have been answered. Pending may be 0 by now, and that is the
  // client behaving: dio gives up after its 10-15 s timeouts and closes the
  // socket (CashFlow's client held on for the whole window; this one does not
  // have to). What matters is that the screen never depended on an answer.
  const after = await apiStatus();
  if (after.calls.some((c) => c.completed)) rec.fail('hanging: held 30 s', 'the API answered while held', []);
  rec.ok('hanging: held 30 s', `${after.calls.length} requests, ${after.pending} still open`);
  report.hanging = { requests: after.calls.length, stillOpenAfter30s: after.pending };
  await see('hanging: still usable after 30 s', { text: 'Купить плитку и клей' });
  await control({ mode: 'online', mutate: { renameTask: { id: 'tsk_tiles', title: 'Купить плитку, клей и затирку' } } });
  await tap({ text: 'Повторить' }).catch(() => {}); // the banner may already have refreshed itself
  await see('hanging: released, refreshed in place', { text: 'Купить плитку, клей и затирку' }, 20000);
  report.ok = report.overBudget.length === 0;
  if (!report.ok) report.error = `startup over budget: ${report.overBudget.join('; ')}`;
  if (!report.ok) console.log(`FAIL ${report.error}`);
} catch (error) {
  report.ok = false;
  report.error = error.message;
  console.log(`FAIL ${error.message}`);
} finally {
  device.putSetting('secure', 'stylus_handwriting_enabled', saved.handwriting);
  device.shell('svc', 'wifi', saved.wifi === '0' ? 'disable' : 'enable');
  device.shell('svc', 'data', saved.data === '0' ? 'disable' : 'enable');
  report.unexpectedApiCalls = (await apiStatus().catch(() => ({ unexpected: [] }))).unexpected;
  server.close();
  report.steps = rec.steps;
  report.finished = new Date().toISOString();
  await mkdir(results, { recursive: true });
  await writeFile(`${results}offline-pass-${pass}.json`, JSON.stringify(report, null, 2));
  for (const s of report.startups) console.log(`startup ${s.mode}: board ${s.usefulFrameMs} ms, first frame ${s.firstFrameMs} ms (budget ${s.budgetMs})`);
  console.log(`${report.ok ? 'PASS' : 'FAIL'} offline pass ${pass}; report: tests/android/results/offline-pass-${pass}.json`);
}
process.exit(report.ok ? 0 : 1);
