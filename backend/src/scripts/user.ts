/*
 * Manages the people who can log in. There is no registration in the app: this
 * is the only way a user comes to exist.
 *
 * USAGE (inside the production container, where the database is)
 *
 *   docker exec taskradar-backend-1 node dist/scripts/user.js create <email> <name>
 *   docker exec taskradar-backend-1 node dist/scripts/user.js passwd <email>
 *   docker exec taskradar-backend-1 node dist/scripts/user.js disable <email>
 *   docker exec taskradar-backend-1 node dist/scripts/user.js enable <email>
 *   docker exec taskradar-backend-1 node dist/scripts/user.js list
 *
 * Locally: `npm run user:create -- <email> <name>` (and `user:passwd`, ...),
 * with DATABASE_URL in the environment.
 *
 * `create` and `passwd` generate a random password and print it ONCE; it is
 * stored only as a bcrypt hash, so it cannot be shown again -- run `passwd` for
 * a new one. Nothing here deletes a user or their data: `disable` locks the
 * account (login refused, live sessions stop at the next request) and leaves
 * every row where it is. The first user's email and password are owned by
 * AUTH_EMAIL / AUTH_PASSWORD_HASH in .env and are put back on every server
 * start, so change those there, not here.
 */
import { prisma } from "../lib/prisma";
import { OWNER_SUBJECT } from "../lib/authConfig";
import {
  DEFAULT_SCOPE_NAME,
  generatePassword,
  hashPassword,
  parseEmail,
} from "../domain/userAdmin";

async function create(emailArg: string | undefined, nameArg: string | undefined): Promise<void> {
  const email = parseEmail(emailArg);
  const name = (nameArg ?? "").trim();
  if (name === "") throw new Error("usage: user create <email> <name>");

  if ((await prisma.user.findUnique({ where: { email } })) !== null) {
    throw new Error(`a user with ${email} already exists`);
  }

  const password = generatePassword();
  const passwordHash = await hashPassword(password);
  const user = await prisma.user.create({
    data: {
      email,
      name,
      passwordHash,
      scopes: { create: { name: DEFAULT_SCOPE_NAME, position: 1000 } },
    },
    select: { id: true },
  });

  console.log(`created ${name} <${email}> (id ${user.id})`);
  console.log(`password: ${password}`);
  console.log("This is the only time it is shown.");
}

async function passwd(emailArg: string | undefined): Promise<void> {
  const email = parseEmail(emailArg);
  const user = await prisma.user.findUnique({ where: { email }, select: { id: true } });
  if (user === null) throw new Error(`no user with ${email}`);
  if (user.id === OWNER_SUBJECT) {
    throw new Error("the first user's password comes from AUTH_PASSWORD_HASH in .env");
  }

  const password = generatePassword();
  await prisma.user.update({ where: { id: user.id }, data: { passwordHash: await hashPassword(password) } });
  console.log(`new password for ${email}: ${password}`);
  console.log("This is the only time it is shown.");
}

async function setDisabled(emailArg: string | undefined, disabled: boolean): Promise<void> {
  const email = parseEmail(emailArg);
  const user = await prisma.user.findUnique({ where: { email }, select: { id: true } });
  if (user === null) throw new Error(`no user with ${email}`);
  if (disabled && user.id === OWNER_SUBJECT) {
    throw new Error("the first user cannot be disabled: their login is restored from .env on every start");
  }
  await prisma.user.update({
    where: { id: user.id },
    data: { disabledAt: disabled ? new Date() : null },
  });
  console.log(`${email} ${disabled ? "disabled" : "enabled"}`);
}

async function list(): Promise<void> {
  const users = await prisma.user.findMany({ orderBy: { createdAt: "asc" } });
  for (const user of users) {
    const state = user.disabledAt === null ? "active" : "disabled";
    console.log(`${user.email}\t${user.name}\t${state}\t${user.createdAt.toISOString().slice(0, 10)}`);
  }
}

async function main(): Promise<void> {
  const [command, ...rest] = process.argv.slice(2);
  switch (command) {
    case "create":
      return create(rest[0], rest.slice(1).join(" "));
    case "passwd":
      return passwd(rest[0]);
    case "disable":
      return setDisabled(rest[0], true);
    case "enable":
      return setDisabled(rest[0], false);
    case "list":
      return list();
    default:
      throw new Error("usage: user <create <email> <name> | passwd <email> | disable <email> | enable <email> | list>");
  }
}

main()
  .catch((error: unknown) => {
    console.error(error instanceof Error ? error.message : error);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
