// Android Back checks for TaskRadar, on a dedicated emulator with the QA
// package installed (scripts/test-android-qa.ps1 builds and installs it).
//
//   node tests/android/run-back.mjs [--only <name part>] [--pass N]
//
// Starts its own synthetic API, runs every row of taskradar/back-scenarios.mjs
// through lib/back-contract.mjs, writes results/back-pass-N.json, restores
// the emulator settings it touched and exits non-zero on any failure. No
// retries: a flaky row is a finding, not something to hide.
import { mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { Device, find, summarize } from './lib/device.mjs';
import { startFaultServer } from './lib/fault-server.mjs';
import { Recorder, expectScreen, runCleanBackScenario, runFieldScenario } from './lib/back-contract.mjs';
import { createTaskRadarApi } from './taskradar/fake-api.mjs';
import { QA, apiStatus, freshSignIn } from './taskradar/app.mjs';
import { SCREENS, SIGNED_IN, SIGNED_OUT } from './taskradar/back-scenarios.mjs';

const args = process.argv.slice(2);
const only = args.includes('--only') ? args[args.indexOf('--only') + 1] : null;
const pass = args.includes('--pass') ? args[args.indexOf('--pass') + 1] : '1';
const results = fileURLToPath(new URL('./results/', import.meta.url));

const device = new Device();
if (!device.adb(['shell', 'pm', 'path', QA.pkg], { allowFail: true })) {
  throw new Error(`${QA.pkg} is not installed; run scripts/test-android-qa.ps1 first`);
}
const server = await startFaultServer({ api: createTaskRadarApi(), port: QA.hostPort, log: () => {} });
const ctx = { device, pkg: QA.pkg, status: apiStatus };
const report = { pass, device: device.serial, started: new Date().toISOString(), scenarios: [] };

// Emulator setup that is not app behaviour: API 36's Gboard stylus tutorial
// can steal focus from injected taps. Restored in `finally`.
const handwriting = device.setting('secure', 'stylus_handwriting_enabled');
device.putSetting('secure', 'stylus_handwriting_enabled', 0);
device.radios(true);

async function run(scenario) {
  if (only && !scenario.name.includes(only)) return;
  const started = Date.now();
  let rec;
  try {
    rec = scenario.kind === 'field' ? await runFieldScenario(ctx, scenario)
      : scenario.kind === 'clean' ? await runCleanBackScenario(ctx, scenario)
        : await scenario.run(ctx);
    report.scenarios.push({ name: scenario.name, ok: true, ms: Date.now() - started, steps: rec.steps });
    console.log(`PASS ${scenario.name}`);
  } catch (error) {
    const steps = ctx.current?.steps ?? [];
    const screen = error.screen ?? steps.at(-1)?.screen ?? summarize(device.dump());
    report.scenarios.push({ name: scenario.name, ok: false, ms: Date.now() - started, error: error.message, steps, screen });
    console.log(`FAIL ${scenario.name}\n  ${error.message}\n  screen: ${screen.slice(0, 25).join(' | ')}`);
  }
}

// The full stack, one level at a time, ending outside the app.
const hierarchy = {
  name: 'hierarchy / board -> project -> task, then Back to the launcher',
  async run(c) {
    const rec = new Recorder(this.name);
    c.current = rec;
    device.forceStop(QA.pkg);
    device.launch(QA.pkg);
    await expectScreen(device, rec, 'board', SCREENS.board, { timeoutMs: 20000 });
    device.tap(await device.waitFor((n) => find(n, { text: 'Ремонт кухни' })));
    await expectScreen(device, rec, 'project', SCREENS.project);
    device.tap(await device.waitFor((n) => find(n, { text: 'Купить плитку' })));
    await expectScreen(device, rec, 'task', SCREENS.task);
    device.back();
    await expectScreen(device, rec, 'back: project', SCREENS.project);
    device.back();
    await expectScreen(device, rec, 'back: board', SCREENS.board);
    device.back();
    const deadline = Date.now() + 5000;
    while (device.focusedPackage() === QA.pkg && Date.now() < deadline) await new Promise((r) => setTimeout(r, 200));
    if (device.focusedPackage() === QA.pkg) rec.fail('back: launcher', 'app still in front', summarize(device.dump()));
    rec.ok('back: launcher', device.focusedPackage());
    device.launch(QA.pkg);
    await expectScreen(device, rec, 'relaunch: still signed in, board', SCREENS.board, { timeoutMs: 20000 });
    return rec;
  },
};

let failed = 0;
try {
  for (const scenario of SIGNED_OUT) await run(scenario);
  const needsSignIn = [...SIGNED_IN, hierarchy].some((s) => !only || s.name.includes(only));
  if (needsSignIn) {
    await freshSignIn(device);
    for (const scenario of SIGNED_IN) await run(scenario);
    await run(hierarchy);
  }
  const status = await apiStatus();
  report.unexpectedApiCalls = status.unexpected;
} finally {
  device.putSetting('secure', 'stylus_handwriting_enabled', handwriting);
  server.close();
  failed = report.scenarios.filter((s) => !s.ok).length;
  report.finished = new Date().toISOString();
  report.summary = { total: report.scenarios.length, failed };
  await mkdir(results, { recursive: true });
  await writeFile(`${results}back-pass-${pass}.json`, JSON.stringify(report, null, 2));
  console.log(`\n${report.scenarios.length - failed}/${report.scenarios.length} passed; report: tests/android/results/back-pass-${pass}.json`);
}
process.exit(failed ? 1 : 0);
