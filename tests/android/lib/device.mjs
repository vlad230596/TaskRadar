// Android emulator control over plain adb: no npm dependencies, so this file
// can be copied into another project as is. Everything app-specific (package,
// selectors, screens) lives in the project adapter, not here.
import { execFileSync } from 'node:child_process';

const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

export class Device {
  constructor(serial = process.env.QA_ANDROID_DEVICE ?? 'emulator-5554') {
    // A dedicated emulator only: this code clears app data and toggles radios.
    if (!/^emulator-\d+$/.test(serial)) throw new Error(`Refusing non-emulator device ${serial}`);
    this.serial = serial;
  }

  adb(args, { timeout = 30000, allowFail = false } = {}) {
    try {
      return execFileSync(process.env.ADB_PATH ?? 'adb', ['-s', this.serial, ...args], {
        encoding: 'utf8', timeout, maxBuffer: 32 * 1024 * 1024, stdio: ['ignore', 'pipe', 'pipe'],
      }).trim();
    } catch (error) {
      if (allowFail) return null;
      throw new Error(`adb ${args.join(' ')} failed: ${error.stderr || error.message}`);
    }
  }

  shell(...args) { return this.adb(['shell', ...args]); }

  // ---- app lifecycle -----------------------------------------------------

  clearApp(pkg) {
    if (this.shell('pm', 'clear', pkg) !== 'Success') throw new Error(`Cannot clear ${pkg}`);
  }

  launch(pkg) {
    this.shell('monkey', '-p', pkg, '-c', 'android.intent.category.LAUNCHER', '1');
  }

  forceStop(pkg) { this.shell('am', 'force-stop', pkg); }

  /** The package whose activity currently has focus ('' when unknown). */
  focusedPackage() {
    const out = this.adb(['shell', 'dumpsys', 'window', 'displays'], { allowFail: true }) ?? '';
    const line = out.split('\n').find((l) => l.includes('mFocusedApp=') || l.includes('mCurrentFocus='));
    return line?.match(/ ([a-z][\w.]+)\/[\w.$]+/i)?.[1] ?? '';
  }

  // ---- input ---------------------------------------------------------------

  back() { this.shell('input', 'keyevent', 'KEYCODE_BACK'); }

  tapPoint(x, y) { this.shell('input', 'tap', String(Math.round(x)), String(Math.round(y))); }

  tap(node) {
    const { x, y } = center(node);
    this.tapPoint(x, y);
  }

  /**
   * Types ASCII through `input text`. adb cannot type Cyrillic; keystrokes are
   * what the test needs anyway -- the language of the text is irrelevant to
   * focus, keyboard and Back behaviour.
   */
  typeAscii(text) {
    if (!/^[\x20-\x7e]*$/.test(text)) throw new Error('typeAscii only accepts printable ASCII');
    const escaped = text.replace(/([\\"'`$&|;<>()*?!#~])/g, '\\$1').replace(/ /g, '%s');
    this.shell('input', 'text', escaped);
  }

  // ---- keyboard ------------------------------------------------------------

  /** Is the soft keyboard on screen? `mInputShown` is the IME manager's own flag. */
  imeShown() {
    const out = this.adb(['shell', 'dumpsys', 'input_method'], { allowFail: true }) ?? '';
    return /mInputShown=true/.test(out);
  }

  async waitIme(shown, timeoutMs = 4000) {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      if (this.imeShown() === shown) return true;
      await pause(150);
    }
    return this.imeShown() === shown;
  }

  // ---- UI tree -------------------------------------------------------------

  /**
   * The accessibility tree via uiautomator. Flutter exposes its semantics
   * there: `Semantics(identifier:)` becomes `resource-id`, labels become
   * `content-desc`, an EditText's value is `text`.
   */
  dump() {
    for (let attempt = 0; attempt < 3; attempt++) {
      const out = this.adb(['exec-out', 'uiautomator', 'dump', '/dev/tty'], { allowFail: true, timeout: 20000 });
      const xml = out?.slice(out.indexOf('<?xml'), out.lastIndexOf('</hierarchy>') + 12);
      if (xml && xml.includes('<hierarchy')) return parseNodes(xml);
    }
    throw new Error('uiautomator dump failed three times');
  }

  async waitFor(predicate, { timeoutMs = 8000, what = 'condition' } = {}) {
    const deadline = Date.now() + timeoutMs;
    let nodes = [];
    while (Date.now() < deadline) {
      nodes = this.dump();
      const hit = predicate(nodes);
      if (hit) return hit;
      await pause(250);
    }
    const error = new Error(`Timed out waiting for ${what}`);
    error.screen = summarize(nodes);
    throw error;
  }

  // ---- network -------------------------------------------------------------

  radios(on) {
    this.shell('svc', 'wifi', on ? 'enable' : 'disable');
    this.shell('svc', 'data', on ? 'enable' : 'disable');
  }

  setting(namespace, key) { return this.shell('settings', 'get', namespace, key); }

  putSetting(namespace, key, value) {
    if (value === 'null' || value == null) this.shell('settings', 'delete', namespace, key);
    else this.shell('settings', 'put', namespace, key, String(value));
  }

  /** Waits for a real route to the host, instead of a fixed sleep after radios come back. */
  async waitRoute(host = '10.0.2.2', timeoutMs = 20000) {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      if (this.adb(['shell', 'ping', '-c', '1', '-W', '1', host], { allowFail: true }) !== null) return;
      await pause(200);
    }
    throw new Error(`No route to ${host}`);
  }

  log(tag, message) { this.shell('log', '-p', 'i', '-t', tag, message); }
}

// ---- tree helpers (pure) ---------------------------------------------------

export function parseNodes(xml) {
  const nodes = [];
  for (const match of xml.matchAll(/<node\b([^>]*?)\/?>/g)) {
    const attrs = {};
    for (const a of match[1].matchAll(/([\w-]+)="([^"]*)"/g)) attrs[a[1]] = decode(a[2]);
    const b = attrs.bounds?.match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/);
    nodes.push({
      text: attrs.text ?? '',
      desc: attrs['content-desc'] ?? '',
      hint: attrs.hint ?? '',
      id: (attrs['resource-id'] ?? '').replace(/^.*:id\//, ''),
      cls: attrs.class ?? '',
      pkg: attrs.package ?? '',
      focused: attrs.focused === 'true',
      clickable: attrs.clickable === 'true',
      editable: (attrs.class ?? '').endsWith('EditText'),
      bounds: b ? { left: +b[1], top: +b[2], right: +b[3], bottom: +b[4] } : null,
    });
  }
  return nodes;
}

const decode = (s) => s.replace(/&#10;/g, '\n').replace(/&quot;/g, '"').replace(/&apos;/g, "'")
  .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');

export const center = (node) => ({
  x: (node.bounds.left + node.bounds.right) / 2,
  y: (node.bounds.top + node.bounds.bottom) / 2,
});

const visible = (n) => n.bounds && n.bounds.right > n.bounds.left && n.bounds.bottom > n.bounds.top;

/**
 * Selector: { id } exact resource-id; { text } substring of text,
 * content-desc or hint (a Flutter field's label/hint lands in `hint`); { exact } whole text or content-desc; { editable: true };
 * { focused: true }. All given fields must match. Returns visible nodes.
 */
export function findAll(nodes, sel) {
  return nodes.filter((n) => visible(n)
    && (sel.id === undefined || n.id === sel.id)
    && (sel.text === undefined || n.text.includes(sel.text) || n.desc.includes(sel.text) || n.hint.includes(sel.text))
    && (sel.exact === undefined || n.text === sel.exact || n.desc === sel.exact)
    && (sel.editable === undefined || n.editable === sel.editable)
    && (sel.focused === undefined || n.focused === sel.focused));
}

export const find = (nodes, sel) => findAll(nodes, sel)[0] ?? null;

export function summarize(nodes) {
  return nodes.filter(visible).map((n) => [n.id && `#${n.id}`, n.desc && `"${n.desc}"`, n.text && `'${n.text}'`, n.hint && `(${n.hint})`, n.focused && '[focused]']
    .filter(Boolean).join(' ')).filter(Boolean).slice(0, 80);
}
