// The Android Back contract, as executable checks. Project-agnostic: a
// scenario names the screen, the field and what Back must do; this file holds
// the protocol every field goes through. See docs/android-back-testing-guide.md.
//
//   1. open the screen               -> its identity is on screen
//   2. tap the field                 -> keyboard up, the field focused
//   3. type                          -> the field holds exactly what was typed
//   4. Back                          -> keyboard down; same screen; text kept
//   5. Back                          -> the screen's own rule:
//        'confirm'  a "discard changes?" dialog; «stay» keeps everything,
//                   a second Back + «discard» leaves to the parent
//        'leave'    straight to the parent (nothing is lost by leaving)
//        'close'    a dialog/sheet closes, its parent screen stays
//        'exit'     the app goes to the background (root screen)
//   6. the parent's identity is on screen, and nothing else is left over
//
// Each step records an observation; a failed expectation stops the scenario
// with the screen summary attached, never retried.
import { find, findAll, summarize } from './device.mjs';

export class Recorder {
  constructor(name) { this.name = name; this.steps = []; this.started = Date.now(); }
  ok(step, detail = '') { this.steps.push({ step, ok: true, detail }); }
  fail(step, detail, screen) {
    this.steps.push({ step, ok: false, detail, screen });
    const error = new Error(`${this.name}: ${step}: ${detail}`);
    error.recorded = true;
    throw error;
  }
}

export async function expectScreen(device, rec, step, selector, { timeoutMs = 8000 } = {}) {
  try {
    const node = await device.waitFor((n) => find(n, selector), { timeoutMs, what: JSON.stringify(selector) });
    rec.ok(step, JSON.stringify(selector));
    return node;
  } catch (error) {
    rec.fail(step, `expected ${JSON.stringify(selector)}`, error.screen);
  }
}

export async function expectGone(device, rec, step, selector, { timeoutMs = 5000 } = {}) {
  try {
    await device.waitFor((n) => !find(n, selector), { timeoutMs, what: `no ${JSON.stringify(selector)}` });
    rec.ok(step, `gone: ${JSON.stringify(selector)}`);
  } catch (error) {
    rec.fail(step, `still visible: ${JSON.stringify(selector)}`, error.screen);
  }
}

async function expectIme(device, rec, step, shown) {
  if (await device.waitIme(shown)) rec.ok(step, `keyboard ${shown ? 'shown' : 'hidden'}`);
  else rec.fail(step, `keyboard expected ${shown ? 'shown' : 'hidden'}`, summarize(device.dump()));
}

/** Does a field hold what was typed? A password field shows dots, so only the length can be checked. */
// Case-insensitive: a field with sentence capitalisation turns the first
// typed "qa" into "Qa", which is the keyboard doing its job.
const holds = (node, scenario, before = '') => (scenario.secret
  ? node.text.length >= before.length + scenario.text.length
  : node.text.toLowerCase().includes(scenario.text.toLowerCase()));

/** The focused editable field, or the one matching [field]. */
function fieldNode(nodes, field) {
  return find(nodes, { ...field, editable: true }) ?? null;
}

/**
 * Runs the Back protocol for one text field.
 *
 * scenario = {
 *   name, open(ctx), screen: selector, field: selector, text: 'ascii',
 *   back: 'confirm' | 'leave' | 'close' | 'exit',
 *   parent: selector (where Back #2 / discard must land),
 *   dialog: { title, stay, discard },   // for 'confirm'
 *   after(ctx)?                          // extra assertions, e.g. nothing saved
 * }
 */
export async function runFieldScenario(ctx, scenario) {
  const { device } = ctx;
  const rec = new Recorder(scenario.name);
  ctx.current = rec;

  await scenario.open(ctx);
  await expectScreen(device, rec, 'screen identity', scenario.screen);

  const field = await device.waitFor((n) => fieldNode(n, scenario.field), { what: `field ${JSON.stringify(scenario.field)}` })
    .catch((error) => rec.fail('field present', JSON.stringify(scenario.field), error.screen));
  rec.ok('field present', JSON.stringify(scenario.field));
  device.tap(field);
  await expectIme(device, rec, 'tap: keyboard', true);
  const focused = find(device.dump(), { focused: true, editable: true });
  if (!focused) rec.fail('tap: focus', 'no focused field after tap', summarize(device.dump()));
  rec.ok('tap: focus', focused.hint || focused.text);
  const before = focused.text;

  device.typeAscii(scenario.text);
  const typed = await device.waitFor((n) => {
    const f = find(n, { focused: true, editable: true });
    return f && holds(f, scenario, before) ? f : null;
  }, { what: 'typed text in the field', timeoutMs: 5000 })
    .catch((error) => rec.fail('type', `field does not hold "${scenario.text}"`, error.screen));
  rec.ok('type', typed.text.slice(0, 60));

  // Back #1: the keyboard only.
  device.back();
  await expectIme(device, rec, 'back 1: keyboard hidden', false);
  await expectScreen(device, rec, 'back 1: same screen', scenario.screen, { timeoutMs: 3000 });
  const kept = findAll(device.dump(), { editable: true }).find((n) => holds(n, scenario, before));
  if (!kept) rec.fail('back 1: text kept', `"${scenario.text}" vanished from the field`, summarize(device.dump()));
  rec.ok('back 1: text kept');

  // Back #2: the screen's own rule.
  device.back();
  if (scenario.back === 'confirm') {
    const d = scenario.dialog;
    await expectScreen(device, rec, 'back 2: confirm dialog', { text: d.title });
    device.tap(find(device.dump(), { exact: d.stay }));
    await expectGone(device, rec, 'stay: dialog closed', { text: d.title });
    await expectScreen(device, rec, 'stay: same screen', scenario.screen);
    const still = findAll(device.dump(), { editable: true }).find((n) => holds(n, scenario, before));
    if (!still) rec.fail('stay: text kept', `"${scenario.text}" lost after «${d.stay}»`, summarize(device.dump()));
    rec.ok('stay: text kept');
    if (await device.waitIme(true, 600)) rec.fail('stay: no keyboard', 'keyboard reopened by itself', []);
    device.back();
    await expectScreen(device, rec, 'back 3: confirm again', { text: d.title });
    device.tap(find(device.dump(), { exact: d.discard }));
    await expectScreen(device, rec, 'discard: parent', scenario.parent);
  } else if (scenario.back === 'leave' || scenario.back === 'close') {
    await expectScreen(device, rec, `back 2: ${scenario.back} to parent`, scenario.parent);
    if (scenario.back === 'close') await expectGone(device, rec, 'dialog gone', scenario.screen);
  } else if (scenario.back === 'exit') {
    const deadline = Date.now() + 5000;
    while (device.focusedPackage() === ctx.pkg && Date.now() < deadline) await new Promise((r) => setTimeout(r, 200));
    if (device.focusedPackage() === ctx.pkg) rec.fail('back 2: app backgrounded', 'app still in front', summarize(device.dump()));
    rec.ok('back 2: app backgrounded', device.focusedPackage());
  } else {
    throw new Error(`Unknown back rule ${scenario.back}`);
  }
  if (await device.waitIme(true, 400)) rec.fail('end: keyboard', 'keyboard is up on the parent', []);
  rec.ok('end: no keyboard');

  if (scenario.after) await scenario.after(ctx, rec);
  return rec;
}

/** Back with nothing typed: leaves at once, no dialog (a read-only Back must never ask). */
export async function runCleanBackScenario(ctx, scenario) {
  const { device } = ctx;
  const rec = new Recorder(scenario.name);
  ctx.current = rec;
  await scenario.open(ctx);
  await expectScreen(device, rec, 'screen identity', scenario.screen);
  device.back();
  if (scenario.back === 'exit') {
    const deadline = Date.now() + 5000;
    while (device.focusedPackage() === ctx.pkg && Date.now() < deadline) await new Promise((r) => setTimeout(r, 200));
    if (device.focusedPackage() === ctx.pkg) rec.fail('back: app backgrounded', 'app still in front', summarize(device.dump()));
    rec.ok('back: app backgrounded');
  } else {
    await expectScreen(device, rec, 'back: parent, no dialog', scenario.parent);
    if (scenario.gone) await expectGone(device, rec, 'back: overlay closed', scenario.gone);
    if (scenario.noDialog) await expectGone(device, rec, 'no confirm dialog', { text: scenario.noDialog }, { timeoutMs: 1500 });
  }
  return rec;
}
