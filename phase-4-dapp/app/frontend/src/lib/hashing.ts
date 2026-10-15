import { bytesToHex, concat, hexToBytes, isHex, keccak256, type Hex } from "viem";

/**
 * Document fingerprints are SALTED: fingerprint = keccak256(salt ‖ documentBytes).
 *
 * Without a salt, anyone holding a guessable document (a certificate template with a
 * student number, for example) could hash candidates and match them against the chain.
 * The salt is random and stays with the document owner, who shares it only with verifiers.
 */
export const SALT_BYTES = 32;

export function generateSalt(): Hex {
  const salt = new Uint8Array(SALT_BYTES);
  crypto.getRandomValues(salt); // CSPRNG; never Math.random() for anything security-related
  return bytesToHex(salt);
}

export function fingerprint(documentBytes: Uint8Array, salt: Hex): Hex {
  if (!isHex(salt) || hexToBytes(salt).length !== SALT_BYTES) {
    throw new Error(`salt must be ${SALT_BYTES} bytes of hex`);
  }
  return keccak256(concat([hexToBytes(salt), documentBytes]));
}

/** Read a browser File into bytes. Hashing happens locally: the file never leaves the device. */
export async function readFileBytes(file: File): Promise<Uint8Array> {
  return new Uint8Array(await file.arrayBuffer());
}
