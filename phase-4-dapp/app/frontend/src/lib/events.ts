import { parseEventLogs, type Log } from "viem";
import { documentRegistryAbi } from "../abi/DocumentRegistry";

export type RegistryLog = ReturnType<typeof parseRegistryLogs>[number];

/** Decode raw logs against the ABI. The result is a union discriminated by `eventName`. */
export function parseRegistryLogs(logs: Log[]) {
  return parseEventLogs({ abi: documentRegistryAbi, logs, strict: true });
}

const short = (a: string) => `${a.slice(0, 6)}…${a.slice(-4)}`;

/** Human-readable one-liner for a feed or history view. Pure, so it's unit-tested. */
export function describeRegistryLog(log: RegistryLog): string {
  switch (log.eventName) {
    case "RecordRegistered":
      return `#${log.args.id} registered by ${short(log.args.owner)}: "${log.args.label}"`;
    case "RecordRetired":
      return `#${log.args.id} retired by ${short(log.args.owner)}`;
    case "RecordTransferred":
      return `#${log.args.id} transferred ${short(log.args.from)} → ${short(log.args.to)}`;
  }
}

/** (txHash, logIndex) uniquely identifies a log: the idempotency key for feeds and indexers. */
export function logKey(log: { transactionHash: string | null; logIndex: number | null }): string {
  return `${log.transactionHash}:${log.logIndex}`;
}
