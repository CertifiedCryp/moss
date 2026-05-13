import { createHash, randomBytes } from "node:crypto";

import { CliError } from "../errors.js";

export type PkcePair = {
  codeVerifier: string;
  codeChallenge: string;
  codeChallengeMethod: "S256";
};

const verifierBytes = 32;
const stateBytes = 32;
const userCodeBytes = 5;
const pkceVerifierPattern = /^[A-Za-z0-9._~-]{43,128}$/;
const userCodeAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

export function createPkcePair(): PkcePair {
  const codeVerifier = createCodeVerifier();
  return {
    codeVerifier,
    codeChallenge: createCodeChallenge(codeVerifier),
    codeChallengeMethod: "S256",
  };
}

export function createCodeVerifier(): string {
  return randomBytes(verifierBytes).toString("base64url");
}

export function createCodeChallenge(codeVerifier: string): string {
  assertCodeVerifier(codeVerifier);
  return createHash("sha256").update(codeVerifier).digest("base64url");
}

export function createState(): string {
  return randomBytes(stateBytes).toString("base64url");
}

export function createUserCode(): string {
  const bytes = randomBytes(userCodeBytes);
  let value = 0n;
  for (const byte of bytes) {
    value = (value << 8n) | BigInt(byte);
  }

  let code = "";
  for (let index = 0; index < 8; index += 1) {
    const alphabetIndex = Number(value % BigInt(userCodeAlphabet.length));
    code = `${userCodeAlphabet[alphabetIndex]}${code}`;
    value /= BigInt(userCodeAlphabet.length);
  }

  return formatUserCode(code);
}

export function normalizeUserCode(value: string): string {
  const normalized = value
    .trim()
    .toUpperCase()
    .replaceAll(/\s+/g, "")
    .replaceAll("-", "");
  if (!/^[A-Z0-9]{8}$/.test(normalized)) {
    throw new CliError("userCode must use the XXXX-XXXX format");
  }

  return formatUserCode(normalized);
}

export function formatUserCode(value: string): string {
  const normalized = value.toUpperCase().replaceAll("-", "");
  if (!/^[A-Z0-9]{8}$/.test(normalized)) {
    throw new CliError("userCode must be 8 alphanumeric characters");
  }

  return `${normalized.slice(0, 4)}-${normalized.slice(4)}`;
}

export function assertCodeVerifier(value: unknown): asserts value is string {
  if (typeof value !== "string" || !pkceVerifierPattern.test(value)) {
    throw new CliError("codeVerifier must be 43-128 PKCE characters for S256");
  }
}
