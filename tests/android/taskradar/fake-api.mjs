// The TaskRadar backend's contract, in memory, for the Android QA package.
//
// Shapes follow backend/src/routes/* and the Prisma models: the list routes
// annotate `isCurrent`, mutation routes answer the raw row without it, `/board`
// carries `noteCount`, `/focus` embeds `project: {id, name}`. Anything not
// listed here answers 404 and is recorded in `unexpected`, so a screen that
// started calling something new shows up as a contract gap in the run report
// instead of as a mysterious blank screen.
//
// Synthetic account only (see SEED_USER); this server must never be pointed at
// real data, and it binds to loopback in fault-server.mjs.
import { randomUUID } from 'node:crypto';

export const SEED_USER = { id: 'qa_user_1', email: 'qa@taskradar.test', password: 'qa-synthetic-password' };

const iso = (date) => date.toISOString();
const b64url = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
const tokenFor = (sub) => `${b64url({ alg: 'HS256', typ: 'JWT' })}.${b64url({ sub, qa: randomUUID() })}.qa`;

function seed(now = new Date()) {
  const day = (offset) => new Date(now.getTime() + offset * 86400000);
  const midnightUtc = (offset) => {
    const d = day(offset);
    return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  };
  const created = iso(day(-20));
  const ai = { aiSource: null, aiKind: null, aiResult: null };
  const task = (id, projectId, title, status, position, extra = {}) => ({
    id, projectId, title, description: null, status, position,
    remindAt: null, remindTime: null, categoryId: null, focusedAt: null, ...ai,
    createdAt: created, updatedAt: created, ...extra,
  });
  return {
    scopes: [{ id: 'scope_qa_main', userId: SEED_USER.id, name: 'Основной', position: 1000, createdAt: created, updatedAt: created }],
    projects: [
      { id: 'prj_kitchen', name: 'Ремонт кухни', scopeId: 'scope_qa_main', archivedAt: null, createdAt: created, updatedAt: created },
      { id: 'prj_trip', name: 'Отпуск', scopeId: 'scope_qa_main', archivedAt: null, createdAt: iso(day(-19)), updatedAt: created },
      { id: 'prj_old', name: 'Старый сайт', scopeId: 'scope_qa_main', archivedAt: iso(day(-5)), createdAt: iso(day(-30)), updatedAt: created },
    ],
    tasks: [
      task('tsk_measure', 'prj_kitchen', 'Снять размеры', 'done', 1000),
      task('tsk_tiles', 'prj_kitchen', 'Купить плитку', 'pending', 2000, { description: 'Белая, 20×20, с запасом 10%', focusedAt: iso(day(-1)) }),
      task('tsk_electric', 'prj_kitchen', 'Жду электрика', 'blocked', 3000, { remindAt: iso(midnightUtc(3)) }),
      task('tsk_tickets', 'prj_trip', 'Купить билеты', 'pending', 1000),
      task('tsk_site', 'prj_old', 'Перенести домен', 'done', 1000),
    ],
    notes: [
      { id: 'note_sizes', projectId: 'prj_kitchen', title: 'Размеры', content: 'Стена у окна — 3,2 м', ...ai, createdAt: created, updatedAt: created },
    ],
    categories: [],
    inbox: [
      { id: 'inb_call', userId: SEED_USER.id, text: 'Позвонить в сервис', captureKey: null, ...ai, createdAt: created, updatedAt: created },
    ],
    events: [],
  };
}

export function createTaskRadarApi({ now = () => new Date() } = {}) {
  let db = seed(now());
  const unexpected = [];
  const tokens = new Set();
  let counter = 0;
  const newId = (prefix) => `${prefix}_qa_${++counter}`;
  const stamp = () => iso(now());

  const ok = (body, status = 200) => ({ status, body });
  const notFound = (what) => ({ status: 404, body: { error: 'Not Found', message: `${what} not found` } });
  const invalid = (message) => ({ status: 400, body: { error: 'Bad Request', message } });

  const annotate = (tasks) => {
    let assigned = false;
    return tasks.map((t) => {
      if (!assigned && t.status === 'pending') { assigned = true; return { ...t, isCurrent: true }; }
      return { ...t, isCurrent: false };
    });
  };
  const byPosition = (a, b) => a.position - b.position;
  const tasksOf = (projectId) => db.tasks.filter((t) => t.projectId === projectId).sort(byPosition);
  const appendPosition = (rows) => (rows.length ? Math.max(...rows.map((r) => r.position)) + 1000 : 1000);
  const project = (id) => db.projects.find((p) => p.id === id);
  const event = (taskId, kind, fromStatus = null, toStatus = null) =>
    db.events.push({ id: newId('evt'), taskId, kind, fromStatus, toStatus, at: stamp() });

  const routes = [
    ['POST', '/auth/login', ({ body }) => {
      if (body?.email?.trim() !== SEED_USER.email || body?.password !== SEED_USER.password) {
        return { status: 401, body: { error: 'Unauthorized', message: 'Invalid email or password' } };
      }
      const token = tokenFor(SEED_USER.id);
      tokens.add(token);
      return ok({ ok: true, token, expiresIn: 2592000 });
    }, { public: true }],
    ['GET', '/auth/me', () => ok({ ok: true })],
    ['POST', '/auth/logout', () => ok({ ok: true }), { public: true }],

    ['GET', '/board', ({ query }) => {
      const archived = query.archived === 'true';
      return ok(db.projects
        .filter((p) => (archived ? p.archivedAt !== null : p.archivedAt === null))
        .filter((p) => !query.scopeId || p.scopeId === query.scopeId)
        .sort((a, b) => a.createdAt.localeCompare(b.createdAt))
        .map((p) => ({ ...p, noteCount: db.notes.filter((n) => n.projectId === p.id).length, tasks: annotate(tasksOf(p.id)) })));
    }],

    ['GET', '/scopes', () => ok([...db.scopes].sort(byPosition))],
    ['POST', '/scopes', ({ body }) => {
      const scope = { id: newId('scope'), userId: SEED_USER.id, name: body.name, position: appendPosition(db.scopes), createdAt: stamp(), updatedAt: stamp() };
      db.scopes.push(scope);
      return ok(scope, 201);
    }],
    ['PATCH', '/scopes/:id', ({ params, body }) => {
      const scope = db.scopes.find((s) => s.id === params.id);
      if (!scope) return notFound('Scope');
      Object.assign(scope, { name: body.name ?? scope.name, updatedAt: stamp() });
      return ok(scope);
    }],

    ['GET', '/projects', ({ query }) => ok(db.projects.filter((p) => (query.archived === 'true') === (p.archivedAt !== null)))],
    ['POST', '/projects', ({ body }) => {
      if (!body?.name?.trim()) return invalid('name is required');
      const p = { id: newId('prj'), name: body.name.trim(), scopeId: body.scopeId ?? db.scopes[0].id, archivedAt: null, createdAt: stamp(), updatedAt: stamp() };
      db.projects.push(p);
      return ok(p, 201);
    }],
    ['GET', '/projects/:id', ({ params }) => (project(params.id) ? ok(project(params.id)) : notFound('Project'))],
    ['PATCH', '/projects/:id', ({ params, body }) => {
      const p = project(params.id);
      if (!p) return notFound('Project');
      Object.assign(p, body.name !== undefined ? { name: body.name } : {}, body.scopeId !== undefined ? { scopeId: body.scopeId } : {}, { updatedAt: stamp() });
      return ok(p);
    }],
    ['POST', '/projects/:id/archive', ({ params }) => {
      const p = project(params.id);
      if (!p) return notFound('Project');
      Object.assign(p, { archivedAt: stamp(), updatedAt: stamp() });
      return ok(p);
    }],
    ['POST', '/projects/:id/unarchive', ({ params }) => {
      const p = project(params.id);
      if (!p) return notFound('Project');
      Object.assign(p, { archivedAt: null, updatedAt: stamp() });
      return ok(p);
    }],

    ['GET', '/projects/:id/tasks', ({ params }) => (project(params.id) ? ok(annotate(tasksOf(params.id))) : notFound('Project'))],
    ['POST', '/projects/:id/tasks', ({ params, body }) => {
      if (!project(params.id)) return notFound('Project');
      if (!body?.title?.trim()) return invalid('title is required');
      const t = {
        id: newId('tsk'), projectId: params.id, title: body.title.trim(), description: body.description ?? null,
        status: body.status ?? 'pending', position: appendPosition(tasksOf(params.id)),
        remindAt: body.remindAt ?? null, remindTime: body.remindTime ?? null, categoryId: body.categoryId ?? null,
        focusedAt: null, aiSource: null, aiKind: null, aiResult: null, createdAt: stamp(), updatedAt: stamp(),
      };
      db.tasks.push(t);
      event(t.id, 'created', null, t.status);
      return ok(t, 201);
    }],
    ['PATCH', '/tasks/:id', ({ params, body }) => {
      const t = db.tasks.find((x) => x.id === params.id);
      if (!t) return notFound('Task');
      const before = t.status;
      for (const key of ['title', 'description', 'status', 'remindAt', 'remindTime', 'categoryId']) {
        if (body[key] !== undefined) t[key] = key === 'title' ? body[key].trim() : body[key];
      }
      if (body.aiClear) Object.assign(t, { aiSource: null, aiKind: null, aiResult: null });
      if (body.status && body.status !== before) event(t.id, 'status', before, body.status);
      t.updatedAt = stamp();
      return ok(t);
    }],
    ['PATCH', '/tasks/:id/position', ({ params, body }) => {
      const t = db.tasks.find((x) => x.id === params.id);
      if (!t) return notFound('Task');
      const pos = (id) => db.tasks.find((x) => x.id === id)?.position ?? null;
      const before = body.beforeTaskId ? pos(body.beforeTaskId) : null;
      const after = body.afterTaskId ? pos(body.afterTaskId) : null;
      t.position = before !== null && after !== null ? (before + after) / 2 : before !== null ? before + 1000 : after !== null ? after - 1000 : t.position;
      t.updatedAt = stamp();
      return ok(t);
    }],
    ['DELETE', '/tasks/:id', ({ params }) => {
      const before = db.tasks.length;
      db.tasks = db.tasks.filter((x) => x.id !== params.id);
      return db.tasks.length === before ? notFound('Task') : { status: 204 };
    }],
    ['GET', '/tasks/:id/events', ({ params }) => ok(db.events.filter((e) => e.taskId === params.id))],
    ['POST', '/tasks/:id/focus', ({ params }) => {
      const t = db.tasks.find((x) => x.id === params.id);
      if (!t) return notFound('Task');
      if (!t.focusedAt) { t.focusedAt = stamp(); event(t.id, 'focused'); }
      return ok(t);
    }],
    ['DELETE', '/tasks/:id/focus', ({ params }) => {
      const t = db.tasks.find((x) => x.id === params.id);
      if (!t) return notFound('Task');
      if (t.focusedAt) { t.focusedAt = null; event(t.id, 'unfocused'); }
      return ok(t);
    }],
    ['GET', '/focus', () => ok(db.tasks
      .filter((t) => t.focusedAt && project(t.projectId))
      .sort((a, b) => a.focusedAt.localeCompare(b.focusedAt))
      .map((t) => ({ ...t, project: { id: t.projectId, name: project(t.projectId).name } })))],

    ['GET', '/projects/:id/notes', ({ params }) => ok(db.notes.filter((n) => n.projectId === params.id))],
    ['POST', '/projects/:id/notes', ({ params, body }) => {
      if (!body?.title?.trim()) return invalid('title is required');
      const n = { id: newId('note'), projectId: params.id, title: body.title.trim(), content: body.content ?? '', aiSource: null, aiKind: null, aiResult: null, createdAt: stamp(), updatedAt: stamp() };
      db.notes.push(n);
      return ok(n, 201);
    }],
    ['PATCH', '/notes/:id', ({ params, body }) => {
      const n = db.notes.find((x) => x.id === params.id);
      if (!n) return notFound('Note');
      if (body.title !== undefined) n.title = body.title.trim();
      if (body.content !== undefined) n.content = body.content;
      n.updatedAt = stamp();
      return ok(n);
    }],
    ['DELETE', '/notes/:id', ({ params }) => {
      db.notes = db.notes.filter((x) => x.id !== params.id);
      return { status: 204 };
    }],

    ['GET', '/projects/:id/categories', ({ params }) => ok(db.categories.filter((c) => c.projectId === params.id))],

    ['GET', '/inbox', () => ok([...db.inbox].sort((a, b) => a.createdAt.localeCompare(b.createdAt)))],
    ['POST', '/inbox', ({ body }) => {
      if (!body?.text?.trim()) return invalid('text is required');
      if (body.captureKey) {
        const known = db.inbox.find((i) => i.captureKey === body.captureKey);
        if (known) return ok(known, 200);
      }
      const item = { id: newId('inb'), userId: SEED_USER.id, text: body.text, captureKey: body.captureKey ?? null, aiSource: null, aiKind: null, aiResult: null, createdAt: stamp(), updatedAt: stamp() };
      db.inbox.push(item);
      return ok(item, 201);
    }],
    ['PATCH', '/inbox/:id', ({ params, body }) => {
      const item = db.inbox.find((i) => i.id === params.id);
      if (!item) return notFound('Inbox item');
      Object.assign(item, { text: body.text ?? item.text, updatedAt: stamp() });
      return ok(item);
    }],
    ['DELETE', '/inbox/:id', ({ params }) => {
      db.inbox = db.inbox.filter((i) => i.id !== params.id);
      return { status: 204 };
    }],
    ['POST', '/inbox/:id/file', ({ params, body }) => {
      const item = db.inbox.find((i) => i.id === params.id);
      if (!item) return notFound('Inbox item');
      if (!project(body.projectId)) return notFound('Project');
      const [first, ...rest] = item.text.split('\n');
      const t = {
        id: newId('tsk'), projectId: body.projectId, title: body.title ?? first.trim(),
        description: body.description !== undefined ? body.description : (rest.join('\n').trim() || null),
        status: 'pending', position: appendPosition(tasksOf(body.projectId)), remindAt: null, remindTime: null,
        categoryId: null, focusedAt: null, aiSource: null, aiKind: null, aiResult: null, createdAt: stamp(), updatedAt: stamp(),
      };
      db.tasks.push(t);
      db.inbox = db.inbox.filter((i) => i.id !== params.id);
      event(t.id, 'created', null, 'pending');
      return ok(t, 201);
    }],

    ['GET', '/history', ({ query }) => {
      const to = now();
      const closings = db.events.filter((e) => e.kind === 'status' && e.toStatus === 'done');
      const stale = db.tasks
        .filter((t) => t.status !== 'done' && project(t.projectId)?.archivedAt === null)
        .map((t) => {
          const ageMs = Math.max(0, to - new Date(t.createdAt));
          return {
            id: t.id, title: t.title, status: t.status, projectId: t.projectId, projectName: project(t.projectId).name,
            createdAt: t.createdAt, focusedAt: t.focusedAt, ageMs, currentSince: t.createdAt, currentForMs: ageMs,
            byStatus: { pending: t.status === 'pending' ? ageMs : 0, done: 0, blocked: t.status === 'blocked' ? ageMs : 0 },
          };
        })
        .sort((a, b) => b.ageMs - a.ageMs)
        .slice(0, Number(query.staleLimit ?? 5));
      return ok({ range: query.range ?? '30d', from: null, to: iso(to), closedByDay: [], closedTotal: closings.length, projects: [], stale });
    }],
  ];

  const compiled = routes.map(([method, pattern, handler, options = {}]) => {
    const names = [];
    const source = pattern.split('/').map((segment) => {
      if (!segment.startsWith(':')) return segment.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      names.push(segment.slice(1));
      return '([^/]+)';
    }).join('/');
    return { method, regex: new RegExp(`^${source}$`), names, handler, public: options.public };
  });

  return {
    unexpected,
    handle({ method, path, query, body, authorization }) {
      for (const route of compiled) {
        if (route.method !== method) continue;
        const match = route.regex.exec(path);
        if (!match) continue;
        if (!route.public) {
          const token = authorization?.replace(/^Bearer /, '');
          if (!token || !tokens.has(token)) {
            return { status: 401, body: { error: 'Unauthorized', message: 'Unauthorized' } };
          }
        }
        const params = Object.fromEntries(route.names.map((name, i) => [name, decodeURIComponent(match[i + 1])]));
        return route.handler({ params, query, body: body ?? {} });
      }
      unexpected.push(`${method} ${path}`);
      return notFound('Route');
    },
    // Only what assertions need; never tokens.
    inspect: () => ({
      inbox: db.inbox.map(({ id, text, captureKey }) => ({ id, text, captureKey })),
      tasks: db.tasks.map(({ id, projectId, title, status }) => ({ id, projectId, title, status })),
    }),
    reseed() { db = seed(now()); unexpected.length = 0; },
    // Server-side changes made "on another device", to prove a refresh arrived.
    mutate(change) {
      if (change.renameTask) {
        const t = db.tasks.find((x) => x.id === change.renameTask.id);
        if (t) Object.assign(t, { title: change.renameTask.title, updatedAt: stamp() });
      }
    },
  };
}
