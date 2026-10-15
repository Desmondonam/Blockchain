import {
  parseEventLogs,
  type Address,
  type Hash,
  type Hex,
  type PublicClient,
  type TransactionReceipt,
} from "viem";
import { documentRegistryAbi } from "../abi/DocumentRegistry";
import { describeError } from "./errors";
import type { TxEvent } from "./txState";
import type { AppWalletClient } from "./wallet";

export interface TxContext {
  publicClient: PublicClient;
  walletClient: AppWalletClient;
  registry: Address;
  /** Blocks to wait after inclusion. 1 on Anvil; more on public networks (reorgs, Week 5!). */
  confirmations: number;
  onEvent: (event: TxEvent) => void;
  pollingMs?: number;
}

type WriteRequest = Parameters<AppWalletClient["writeContract"]>[0];

// ------------------------------------------------------------ typed actions
// Each helper keeps full ABI type-checking: a wrong function name or argument type
// is a COMPILE error, not a runtime surprise.

export function registerDocument(ctx: TxContext, documentHash: Hex, label: string, uri: string) {
  return runTx(ctx, () =>
    ctx.publicClient.simulateContract({
      account: ctx.walletClient.account,
      address: ctx.registry,
      abi: documentRegistryAbi,
      functionName: "register",
      args: [documentHash, label, uri],
    }),
  );
}

export function retireRecord(ctx: TxContext, id: bigint) {
  return runTx(ctx, () =>
    ctx.publicClient.simulateContract({
      account: ctx.walletClient.account,
      address: ctx.registry,
      abi: documentRegistryAbi,
      functionName: "retire",
      args: [id],
    }),
  );
}

export function transferRecord(ctx: TxContext, id: bigint, to: Address) {
  return runTx(ctx, () =>
    ctx.publicClient.simulateContract({
      account: ctx.walletClient.account,
      address: ctx.registry,
      abi: documentRegistryAbi,
      functionName: "transferRecord",
      args: [id, to],
    }),
  );
}

// ----------------------------------------------------------------- the flow

/**
 * The full, safe write flow:
 *   1. SIMULATE with eth_call as the user: catches reverts BEFORE they sign and pay gas.
 *   2. SIGN + SEND via the wallet: returns a tx hash (that's *pending*, not done!).
 *   3. WAIT for inclusion; follow speed-ups (repriced) and detect cancellations.
 *   4. CHECK receipt.status: a mined tx can still have reverted.
 *   5. WAIT for N confirmations, re-checking the tx is still in the same block (reorgs).
 */
async function runTx(
  ctx: TxContext,
  simulate: () => Promise<{ request: unknown }>,
): Promise<TransactionReceipt | null> {
  const { publicClient, walletClient, confirmations, onEvent } = ctx;
  onEvent({ type: "START" });
  try {
    const { request } = await simulate();
    onEvent({ type: "SIMULATED" });

    const hash = await walletClient.writeContract(request as WriteRequest);
    onEvent({ type: "SUBMITTED", hash, required: confirmations });

    const receipt = await publicClient.waitForTransactionReceipt({
      hash,
      pollingInterval: ctx.pollingMs ?? 1_000,
      timeout: 120_000,
      onReplaced: (r) => onEvent({ type: "REPLACED", replacedBy: r.transaction.hash, reason: r.reason }),
    });
    if (receipt.status !== "success") {
      onEvent({ type: "FAILED", message: "The transaction was mined but reverted." });
      return receipt;
    }

    const final = await waitForConfirmations(publicClient, receipt, confirmations, ctx.pollingMs ?? 1_000, (n) =>
      onEvent({ type: "CONFIRMATION", confirmations: n }),
    );
    onEvent({ type: "CONFIRMED", blockNumber: final.blockNumber });
    return final;
  } catch (error) {
    onEvent({ type: "FAILED", message: describeError(error) });
    return null;
  }
}

/** Poll until the tx's block is `required` deep, then confirm it wasn't reorged out. */
export async function waitForConfirmations(
  client: PublicClient,
  receipt: TransactionReceipt,
  required: number,
  pollingMs: number,
  onProgress: (confirmations: number) => void,
): Promise<TransactionReceipt> {
  let current = receipt;
  for (;;) {
    const head = await client.getBlockNumber({ cacheTime: 0 });
    const depth = Number(head - current.blockNumber + 1n);
    onProgress(Math.min(Math.max(depth, 0), required));
    if (depth >= required) {
      const fresh = await client.getTransactionReceipt({ hash: current.transactionHash });
      if (fresh.blockHash === current.blockHash) return fresh;
      current = fresh; // re-included in a different block after a reorg: count again
      continue;
    }
    await new Promise((resolve) => setTimeout(resolve, pollingMs));
  }
}

/** Pull the new record id out of the receipt's logs: the event is the source of truth. */
export function registeredIdFromReceipt(receipt: TransactionReceipt): bigint | undefined {
  const [event] = parseEventLogs({ abi: documentRegistryAbi, logs: receipt.logs, eventName: "RecordRegistered" });
  return event?.args.id;
}

export type { Hash };
