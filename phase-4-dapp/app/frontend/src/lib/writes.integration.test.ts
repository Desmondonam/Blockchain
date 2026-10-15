/**
 * Real transactions against Anvil, through the SAME functions the UI calls.
 * Requires INTEGRATION_RPC_URL and INTEGRATION_REGISTRY (see registry.integration.test.ts).
 */
import { describe, expect, it } from "vitest";
import { getAddress, parseEventLogs, type Hex } from "viem";
import { documentRegistryAbi } from "../abi/DocumentRegistry";
import { fingerprint, generateSalt } from "./hashing";
import { verifyFingerprint } from "./reads";
import { initialTxState, txReducer, type TxEvent, type TxState } from "./txState";
import { connectDev } from "./wallet";
import { registerDocument, registeredIdFromReceipt, retireRecord, transferRecord, type TxContext } from "./writes";
import { integrationEnabled, integrationSetup } from "../test/integration";
import { describeRegistryLog, logKey, parseRegistryLogs } from "./events";

// Anvil's public test keys #1 and #2.
const ALICE_KEY: Hex = "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d";
const BOB_KEY: Hex = "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a";

function harness(key: Hex) {
  const { config, chain, publicClient } = integrationSetup();
  const conn = connectDev(key, chain, config.rpcUrl);
  const events: TxEvent[] = [];
  const ctx: TxContext = {
    publicClient,
    walletClient: conn.walletClient,
    registry: config.registryAddress,
    confirmations: 1,
    pollingMs: 100,
    onEvent: (e) => events.push(e),
  };
  const finalState = (): TxState => events.reduce(txReducer, initialTxState);
  return { ctx, events, finalState, publicClient, address: conn.address, config };
}

describe.skipIf(!integrationEnabled)("write flow (integration)", () => {
  it("registers a salted fingerprint and verifies it", async () => {
    const alice = harness(ALICE_KEY);
    const hash = fingerprint(new TextEncoder().encode(`doc ${Date.now()}`), generateSalt());

    const receipt = await registerDocument(alice.ctx, hash, "Lease agreement", "docstore://abc");
    expect(receipt?.status).toBe("success");
    expect(alice.events.map((e) => e.type)).toEqual(["START", "SIMULATED", "SUBMITTED", "CONFIRMATION", "CONFIRMED"]);
    expect(alice.finalState().kind).toBe("confirmed");

    const id = registeredIdFromReceipt(receipt!);
    expect(id).toBeGreaterThan(0n);
    const v = await verifyFingerprint(alice.publicClient, alice.config.registryAddress, hash);
    expect(v).toMatchObject({ found: true, active: true });
    if (v.found) expect(v.record.owner).toBe(alice.address);
  });

  it("a duplicate is caught in SIMULATION, so no tx is sent and no gas spent", async () => {
    const alice = harness(ALICE_KEY);
    const hash = fingerprint(new TextEncoder().encode(`dup ${Date.now()}`), generateSalt());
    await registerDocument(alice.ctx, hash, "first", "");

    const second = harness(ALICE_KEY);
    const nonceBefore = await second.publicClient.getTransactionCount({ address: second.address });
    const receipt = await registerDocument(second.ctx, hash, "second", "");
    expect(receipt).toBeNull();
    expect(second.events.map((e) => e.type)).toEqual(["START", "FAILED"]);
    const state = second.finalState();
    expect(state.kind === "failed" && state.message).toMatch(/already registered \(record #\d+\)/);
    expect(await second.publicClient.getTransactionCount({ address: second.address })).toBe(nonceBefore);
  });

  it("only the owner can retire; transfer then retire by the new owner works", async () => {
    const alice = harness(ALICE_KEY);
    const bob = harness(BOB_KEY);
    const hash = fingerprint(new TextEncoder().encode(`own ${Date.now()}`), generateSalt());
    const id = registeredIdFromReceipt((await registerDocument(alice.ctx, hash, "Deed", ""))!)!;

    expect(await retireRecord(bob.ctx, id)).toBeNull();
    const bobState = bob.finalState();
    expect(bobState.kind === "failed" && bobState.message).toMatch(new RegExp(`owner of record #${id}`));

    const transfer = await transferRecord(alice.ctx, id, getAddress(bob.address));
    const [moved] = parseEventLogs({ abi: documentRegistryAbi, logs: transfer!.logs, eventName: "RecordTransferred" });
    expect(moved?.args.to).toBe(bob.address);

    const bob2 = harness(BOB_KEY);
    expect((await retireRecord(bob2.ctx, id))?.status).toBe("success");
    const v = await verifyFingerprint(alice.publicClient, alice.config.registryAddress, hash);
    expect(v).toMatchObject({ found: true, active: false });
  });
});

describe.skipIf(!integrationEnabled)("event decoding (integration)", () => {
  it("decodes and describes the logs of a real receipt", async () => {
    const alice = harness(ALICE_KEY);
    const hash = fingerprint(new TextEncoder().encode(`evt ${Date.now()}`), generateSalt());
    const receipt = (await registerDocument(alice.ctx, hash, "Event test", ""))!;
    const [log] = parseRegistryLogs(receipt.logs);
    expect(log?.eventName).toBe("RecordRegistered");
    expect(describeRegistryLog(log!)).toMatch(/registered by 0x7099…79C8: "Event test"/);
    expect(logKey(log!)).toBe(`${receipt.transactionHash}:${log!.logIndex}`);
  });
});
