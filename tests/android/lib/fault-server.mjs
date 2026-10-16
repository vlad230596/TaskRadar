// A real HTTP server around a project's synthetic API, with the network faults
// the offline checks need. Project-agnostic: the API itself is passed in.
//
//   online  -- answer normally;
//   offline -- drop the connection without a byte, like a dead route;
//   hanging -- keep the request open until the mode changes, so an app that
//              waits for the network before drawing its cache is caught.
//
// `/__qa/status` and `/__qa/control` belong to the test bench only. The log
// keeps method, path, mode and completion -- never bodies or headers, because
// those carry passwords and tokens.
import { createServer } from 'node:http';

export function startFaultServer({ api, port, host = '127.0.0.1', log = console.log }) {
  let mode = 'online';
  let calls = [];
  const pending = new Set();

  const send = (res, status, body) => {
    if (status === 204) { res.writeHead(204); res.end(); return; }
    res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
    res.end(JSON.stringify(body));
  };

  const releaseAll = () => {
    for (const release of pending) release();
    pending.clear();
  };

  const server = createServer(async (req, res) => {
    let raw = '';
    for await (const chunk of req) raw += chunk;
    const url = new URL(req.url, `http://${host}:${port}`);

    if (url.pathname === '/__qa/status') {
      return send(res, 200, {
        mode,
        pending: pending.size,
        calls,
        unexpected: api.unexpected,
        state: api.inspect(),
      });
    }
    if (url.pathname === '/__qa/control' && req.method === 'POST') {
      const control = raw ? JSON.parse(raw) : {};
      if (control.mode && !['online', 'offline', 'hanging'].includes(control.mode)) {
        return send(res, 400, { error: 'Invalid mode' });
      }
      if (control.mode) mode = control.mode;
      if (control.resetLog) calls = [];
      if (control.reseed) api.reseed();
      if (control.mutate) api.mutate(control.mutate);
      if (mode !== 'hanging') releaseAll();
      return send(res, 200, { mode });
    }

    const call = { method: req.method, path: url.pathname, mode, completed: false, at: Date.now() };
    calls.push(call);

    if (mode === 'offline') { req.socket.destroy(); return; }
    if (mode === 'hanging') {
      await new Promise((resolve) => {
        pending.add(resolve);
        res.on('close', () => { pending.delete(resolve); resolve(); });
      });
      if (res.destroyed || res.writableEnded) return;
    }

    let body;
    try { body = raw ? JSON.parse(raw) : undefined; } catch { return send(res, 400, { error: 'Bad JSON' }); }
    const answer = api.handle({
      method: req.method,
      path: url.pathname,
      query: Object.fromEntries(url.searchParams),
      body,
      authorization: req.headers.authorization,
    });
    send(res, answer.status, answer.body);
    call.status = answer.status;
    call.completed = true;
  });

  return new Promise((resolve) => {
    server.listen(port, host, () => {
      log(`Synthetic API ready on http://${host}:${port}`);
      resolve({ server, close: () => { releaseAll(); server.close(); } });
    });
  });
}
