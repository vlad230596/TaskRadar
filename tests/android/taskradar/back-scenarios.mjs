// TaskRadar's Back table: every text field the synthetic API can reach, plus
// Back without typing and through the screen hierarchy. The protocol each row
// runs is lib/back-contract.mjs; this file only says where things are.
//
// Selectors are the accessibility tree as uiautomator sees a Flutter app:
// button tooltips and labels are `content-desc`, a field's hint is `hint`, its
// value is `text`. Text is ASCII on purpose (adb cannot type Cyrillic).
import { find } from '../lib/device.mjs';
import { QA, freshSignIn } from './app.mjs';

const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// Screen identities: something only that screen draws.
export const SCREENS = {
  login: { exact: 'Войти' },
  board: { text: 'Планирование' },
  project: { text: 'Действия с проектом' },
  task: { text: 'Вернуть в песочницу' },
  draft: { text: 'Новая задача' },
  noteEditor: { exact: 'Просмотр' },
  inbox: { text: 'Выбросить строку' },
  archive: { text: 'Удалить навсегда' },
  scopes: { text: 'Порядок здесь' },
  anyDialog: { exact: 'Отмена' },
};

const CONFIRM = { title: 'Выйти без сохранения?', stay: 'Остаться', discard: 'Выйти' };

async function tapWhen(device, selector, what = JSON.stringify(selector)) {
  device.tap(await device.waitFor((n) => find(n, selector), { what }));
  await pause(400);
}

/** A cold start of the signed-in app: lands on the board (the last mode). */
async function board({ device }) {
  device.forceStop(QA.pkg);
  device.launch(QA.pkg);
  await device.waitFor((n) => find(n, SCREENS.board), { what: 'board', timeoutMs: 20000 });
}

async function project(ctx) {
  await board(ctx);
  await tapWhen(ctx.device, { text: 'Ремонт кухни' });
  await ctx.device.waitFor((n) => find(n, SCREENS.project), { what: 'project screen' });
}

async function task(ctx) {
  await project(ctx);
  await tapWhen(ctx.device, { text: 'Купить плитку' });
}

async function draft(ctx) {
  await project(ctx);
  await tapWhen(ctx.device, { exact: 'Задача' });
}

async function notes(ctx) {
  await project(ctx);
  await tapWhen(ctx.device, { text: 'Заметки' });
}

async function noteEditor(ctx) {
  await notes(ctx);
  await tapWhen(ctx.device, { text: 'Размеры' });
}

async function menu(ctx, item) {
  await board(ctx);
  await tapWhen(ctx.device, { exact: 'Ещё' });
  await tapWhen(ctx.device, { exact: item });
}

async function signedOut({ device }) {
  device.forceStop(QA.pkg);
  device.clearApp(QA.pkg);
  device.launch(QA.pkg);
  await device.waitFor((n) => find(n, { text: 'Email', editable: true }), { what: 'login form', timeoutMs: 20000 });
}

/** The server must not have received what was typed and then discarded. */
const nothingSaved = (title) => async (ctx, rec) => {
  const { state } = await ctx.status();
  if (state.tasks.some((t) => t.title.includes(title))) rec.fail('nothing saved', `"${title}" reached the server`, []);
  rec.ok('nothing saved on the server');
};

// Runs before sign-in: the login form is the root screen of a signed-out app.
export const SIGNED_OUT = [
  { kind: 'field', name: 'login / email', open: signedOut, screen: SCREENS.login,
    field: { text: 'Email' }, text: 'qa.typed', back: 'exit' },
  { kind: 'field', name: 'login / password', open: signedOut, screen: SCREENS.login,
    field: { text: 'Пароль' }, text: 'qa-typed', secret: true, back: 'exit' },
];

export const SIGNED_IN = [
  // Fields on full screens with an unsaved-text guard: Back, Back -> dialog.
  { kind: 'field', name: 'task / title', open: task, screen: SCREENS.task,
    field: { text: 'Купить плитку' }, text: ' qa edit', back: 'confirm', dialog: CONFIRM,
    parent: SCREENS.project, after: nothingSaved('qa edit') },
  { kind: 'field', name: 'task / note', open: task, screen: SCREENS.task,
    field: { text: 'Белая' }, text: ' qa note', back: 'confirm', dialog: CONFIRM, parent: SCREENS.project },
  { kind: 'field', name: 'new task / title', open: draft, screen: SCREENS.draft,
    field: { text: 'Что надо сделать' }, text: 'qa draft', back: 'confirm', dialog: CONFIRM,
    parent: SCREENS.project, after: nothingSaved('qa draft') },
  { kind: 'field', name: 'new task / note', open: draft, screen: SCREENS.draft,
    field: { text: 'Кто, что' }, text: 'qa draft note', back: 'confirm', dialog: CONFIRM, parent: SCREENS.project },
  { kind: 'field', name: 'note editor / title', open: noteEditor, screen: SCREENS.noteEditor,
    field: { text: 'Заголовок' }, text: ' qa', back: 'confirm', dialog: CONFIRM, parent: SCREENS.project },
  { kind: 'field', name: 'note editor / content', open: noteEditor, screen: SCREENS.noteEditor,
    field: { text: 'Стена у окна' }, text: ' qa', back: 'confirm', dialog: CONFIRM, parent: SCREENS.project },
  // Inline fields: the guard belongs to the screen they sit on.
  { kind: 'field', name: 'project / new note (inline)', open: notes, screen: SCREENS.project,
    field: { text: 'Новая заметка' }, text: 'qa note', back: 'confirm', dialog: CONFIRM, parent: SCREENS.board },
  { kind: 'field', name: 'sandbox / open line (inline)', open: async (ctx) => { await board(ctx); await tapWhen(ctx.device, { text: 'Песочница' }); },
    screen: SCREENS.inbox, field: { text: 'Позвонить в сервис' }, text: ' qa', back: 'confirm', dialog: CONFIRM, parent: SCREENS.board },
  // Fields in dialogs: Back, Back -> the dialog closes, its screen stays.
  { kind: 'field', name: 'board / new project dialog', open: async (ctx) => { await board(ctx); await tapWhen(ctx.device, { exact: 'Проект' }); },
    screen: { text: 'Новый проект' }, field: { text: 'Название проекта' }, text: 'qa project', back: 'close', parent: SCREENS.board },
  { kind: 'field', name: 'project / rename dialog', open: async (ctx) => { await project(ctx); await tapWhen(ctx.device, { text: 'Действия с проектом' }); await tapWhen(ctx.device, { exact: 'Переименовать' }); },
    screen: SCREENS.anyDialog, field: {}, text: ' qa', back: 'close', parent: SCREENS.project },
  { kind: 'field', name: 'scopes / new scope dialog', open: async (ctx) => { await menu(ctx, 'Скоупы'); await tapWhen(ctx.device, { exact: 'Скоуп' }); },
    screen: SCREENS.anyDialog, field: {}, text: 'qa scope', back: 'close', parent: SCREENS.scopes },
  { kind: 'field', name: 'archive / delete confirmation (typed)', open: async (ctx) => { await menu(ctx, 'Архив'); await tapWhen(ctx.device, { text: 'Удалить навсегда' }); },
    screen: SCREENS.anyDialog, field: {}, text: 'qa', back: 'close', parent: SCREENS.archive },

  // Back with nothing typed: straight to the parent, never a dialog.
  { kind: 'clean', name: 'clean / task -> project', open: task, screen: SCREENS.task, parent: SCREENS.project, noDialog: CONFIRM.title },
  { kind: 'clean', name: 'clean / new task -> project', open: draft, screen: SCREENS.draft, parent: SCREENS.project, noDialog: CONFIRM.title },
  { kind: 'clean', name: 'clean / note editor -> project', open: noteEditor, screen: SCREENS.noteEditor, parent: SCREENS.project, noDialog: CONFIRM.title },
  { kind: 'clean', name: 'clean / project -> board', open: project, screen: SCREENS.project, parent: SCREENS.board },
  { kind: 'clean', name: 'clean / sandbox -> board', open: async (ctx) => { await board(ctx); await tapWhen(ctx.device, { text: 'Песочница' }); },
    screen: SCREENS.inbox, parent: SCREENS.board, noDialog: CONFIRM.title },
  { kind: 'clean', name: 'clean / archive -> board', open: (ctx) => menu(ctx, 'Архив'), screen: SCREENS.archive, parent: SCREENS.board },
  { kind: 'clean', name: 'clean / scopes -> board', open: (ctx) => menu(ctx, 'Скоупы'), screen: SCREENS.scopes, parent: SCREENS.board },
  { kind: 'clean', name: 'clean / project menu closes, project stays', open: async (ctx) => { await project(ctx); await tapWhen(ctx.device, { text: 'Действия с проектом' }); },
    screen: { exact: 'Переименовать' }, parent: SCREENS.project, gone: { exact: 'Переименовать' } },
  { kind: 'clean', name: 'clean / board is the root: Back leaves the app', open: board, screen: SCREENS.board, back: 'exit' },
];

export { freshSignIn };
