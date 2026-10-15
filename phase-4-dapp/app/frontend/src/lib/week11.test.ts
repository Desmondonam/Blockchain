import { describe, expect, it } from "vitest";
import { keccak256, concat, hexToBytes, type Hex } from "viem";
import { fingerprint, generateSalt, SALT_BYTES } from "./hashing";
import { initialTxState, isBusy, txReducer, type TxEvent, type TxState } from "./txState";
import { friendlyContractError } from "./errors";

const doc = new TextEncoder().encode("BSc Computer Science, 2026");
const HASH_A = `0x${"aa".repeat(32)}` as Hex;
const HASH_B = `0x${"bb".repeat(32)}` as Hex;

describe("hashing", () => {
  it("salts are 32 random bytes and differ every time", () => {
    const a = generateSalt();
    const b = generateSalt();
    expect(hexToBytes(a)).toHaveLength(SALT_BYTES);
    expect(a).not.toBe(b);
  });

  it("fingerprint = keccak256(salt ‖ bytes), deterministic for the same inputs", () => {
    const salt = generateSalt();
    expect(fingerprint(doc, salt)).toBe(keccak256(concat([hexToBytes(salt), doc])));
    expect(fingerprint(doc, salt)).toBe(fingerprint(doc, salt));
  });

  it("the same document with a different salt gives an unlinkable fingerprint", () => {
    expect(fingerprint(doc, generateSalt())).not.toBe(fingerprint(doc, generateSalt()));
  });

  it("a one-byte change gives a different fingerprint", () => {
    const salt = generateSalt();
    const altered = new TextEncoder().encode("BSc Computer Science, 2027");
    expect(fingerprint(altered, salt)).not.toBe(fingerprint(doc, salt));
  });

  it("rejects a malformed salt", () => {
    expect(() => fingerprint(doc, "0x1234")).toThrow(/32 bytes/);
  });
});

describe("txReducer", () => {
  const run = (events: TxEvent[]): TxState => events.reduce(txReducer, initialTxState);

  it("walks the happy path", () => {
    const s = run([
      { type: "START" },
      { type: "SIMULATED" },
      { type: "SUBMITTED", hash: HASH_A, required: 3 },
      { type: "CONFIRMATION", confirmations: 2 },
    ]);
    expect(s).toEqual({ kind: "pending", hash: HASH_A, confirmations: 2, required: 3 });
    expect(isBusy(s)).toBe(true);
    expect(txReducer(s, { type: "CONFIRMED", blockNumber: 7n })).toEqual({ kind: "confirmed", hash: HASH_A, blockNumber: 7n });
  });

  it("a speed-up (repriced) keeps the tx pending under its new hash", () => {
    const s = run([
      { type: "START" },
      { type: "SIMULATED" },
      { type: "SUBMITTED", hash: HASH_A, required: 1 },
      { type: "REPLACED", replacedBy: HASH_B, reason: "repriced" },
    ]);
    expect(s).toMatchObject({ kind: "pending", hash: HASH_B });
  });

  it("a cancellation is terminal", () => {
    const s = run([
      { type: "START" },
      { type: "SIMULATED" },
      { type: "SUBMITTED", hash: HASH_A, required: 1 },
      { type: "REPLACED", replacedBy: HASH_B, reason: "cancelled" },
    ]);
    expect(s.kind).toBe("replaced");
    expect(txReducer(s, { type: "CONFIRMED", blockNumber: 1n }).kind).toBe("replaced");
  });

  it("failure during simulation keeps no hash; failure while pending keeps it", () => {
    expect(run([{ type: "START" }, { type: "FAILED", message: "x" }])).toEqual({ kind: "failed", message: "x", hash: undefined });
    const pendingFail = run([
      { type: "START" },
      { type: "SIMULATED" },
      { type: "SUBMITTED", hash: HASH_A, required: 1 },
      { type: "FAILED", message: "reverted" },
    ]);
    expect(pendingFail).toMatchObject({ kind: "failed", hash: HASH_A });
  });

  it("ignores illegal transitions", () => {
    expect(txReducer(initialTxState, { type: "CONFIRMED", blockNumber: 1n })).toBe(initialTxState);
    expect(txReducer(initialTxState, { type: "SUBMITTED", hash: HASH_A, required: 1 })).toBe(initialTxState);
  });

  it("can start again after a terminal state, and RESET always returns to idle", () => {
    const failed = run([{ type: "START" }, { type: "FAILED", message: "x" }]);
    expect(txReducer(failed, { type: "START" }).kind).toBe("simulating");
    expect(txReducer(failed, { type: "RESET" })).toEqual(initialTxState);
  });
});

describe("friendlyContractError", () => {
  it.each([
    ["AlreadyRegistered", [HASH_A, 4n], /already registered \(record #4\)/],
    ["NotRecordOwner", [9n, "0xabc"], /owner of record #9/],
    ["RecordNotActive", [2n], /retired/],
    ["SomethingNew", [], /SomethingNew/],
  ])("%s", (name, args, expected) => {
    expect(friendlyContractError(name, args)).toMatch(expected);
  });
});
