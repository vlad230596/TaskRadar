// TaskRadar's project adapter: the package, the API address, the synthetic
// account and how to get from a cleared package to a signed-in board. Only
// this file and the scenario tables next to it know anything about TaskRadar.
import { find } from '../lib/device.mjs';
import { SEED_USER } from './fake-api.mjs';

export const QA = {
  pkg: 'com.taskradar.app.qa',
  hostPort: 18743,
  apiOrigin: 'http://127.0.0.1:18743',
  emulatorApi: 'http://10.0.2.2:18743',
  logTag: 'TaskRadarQa',
  // The first screen that proves a signed-in board with real data on it.
  boardReady: { text: 'Купить плитку' },
};

export async function control(body) {
  const response = await fetch(`${QA.apiOrigin}/__qa/control`, { method: 'POST', body: JSON.stringify(body) });
  if (!response.ok) throw new Error(`Synthetic API control failed: ${response.status}`);
}

export async function apiStatus() {
  return (await fetch(`${QA.apiOrigin}/__qa/status`)).json();
}

/** Clears only the QA package and signs in through the real login form. */
export async function freshSignIn(device) {
  await control({ mode: 'online', reseed: true, resetLog: true });
  device.forceStop(QA.pkg);
  device.clearApp(QA.pkg);
  device.launch(QA.pkg);
  const email = await device.waitFor((n) => find(n, { text: 'Email', editable: true }), { what: 'login form', timeoutMs: 20000 });
  device.tap(email);
  await device.waitIme(true);
  device.typeAscii(SEED_USER.email);
  const password = find(device.dump(), { text: 'Пароль', editable: true });
  device.tap(password);
  device.typeAscii(SEED_USER.password);
  device.back(); // keyboard down, so the button is not hidden behind it
  await device.waitIme(false);
  device.tap(await device.waitFor((n) => find(n, { exact: 'Войти' }), { what: 'sign-in button' }));
  await device.waitFor((n) => find(n, QA.boardReady), { what: 'board after sign-in', timeoutMs: 20000 });
}
