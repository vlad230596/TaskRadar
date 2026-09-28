import { randomInt } from "node:crypto";
import bcrypt from "bcrypt";
import { normaliseEmail } from "../lib/credentials";

/** bcrypt cost, the same as the hash `AUTH_PASSWORD_HASH` is documented with. */
export const BCRYPT_COST = 12;

/** The scope every new user starts with, so their first project has somewhere to go. */
export const DEFAULT_SCOPE_NAME = "Основной";

// No 0/O, 1/l/I: the password is read off a screen and typed on a phone.
const PASSWORD_ALPHABET = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const PASSWORD_LENGTH = 16;

/** A random password of about 93 bits, from a CSPRNG. */
export function generatePassword(): string {
  let out = "";
  for (let i = 0; i < PASSWORD_LENGTH; i += 1) {
    out += PASSWORD_ALPHABET[randomInt(PASSWORD_ALPHABET.length)];
  }
  return out;
}

export function hashPassword(plaintext: string): Promise<string> {
  return bcrypt.hash(plaintext, BCRYPT_COST);
}

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/** Trimmed lowercase email, or throws a message meant for the operator. */
export function parseEmail(raw: string | undefined): string {
  const email = normaliseEmail(raw ?? "");
  if (!EMAIL_PATTERN.test(email)) throw new Error(`"${raw ?? ""}" is not an email address`);
  return email;
}
