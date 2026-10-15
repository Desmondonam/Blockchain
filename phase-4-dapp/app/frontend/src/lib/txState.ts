import type { Hash } from "viem";

/**
 * The life of a transaction, from the UI's point of view, as an explicit state machine.
 * Each state tells the user exactly what is happening and what they can do next.
 *
 *   idle → simulating → awaitingSignature → pending → confirmed
 *              ↓               ↓               ↓
 *            failed          failed     failed (reverted) / replaced
 */
export type TxState =
  | { kind: "idle" }
  | { kind: "simulating" }
  | { kind: "awaitingSignature" }
  | { kind: "pending"; hash: Hash; confirmations: number; required: number }
  | { kind: "confirmed"; hash: Hash; blockNumber: bigint }
  | { kind: "replaced"; hash: Hash; replacedBy: Hash; reason: string }
  | { kind: "failed"; message: string; hash?: Hash };

export type TxEvent =
  | { type: "START" }
  | { type: "SIMULATED" }
  | { type: "SUBMITTED"; hash: Hash; required: number }
  | { type: "CONFIRMATION"; confirmations: number }
  | { type: "CONFIRMED"; blockNumber: bigint }
  | { type: "REPLACED"; replacedBy: Hash; reason: string }
  | { type: "FAILED"; message: string }
  | { type: "RESET" };

export const initialTxState: TxState = { kind: "idle" };

/** Pure reducer. Illegal transitions are ignored, so the UI can never show nonsense states. */
export function txReducer(state: TxState, event: TxEvent): TxState {
  switch (event.type) {
    case "RESET":
      return initialTxState;
    case "START":
      return state.kind === "idle" || isTerminal(state) ? { kind: "simulating" } : state;
    case "SIMULATED":
      return state.kind === "simulating" ? { kind: "awaitingSignature" } : state;
    case "SUBMITTED":
      return state.kind === "awaitingSignature"
        ? { kind: "pending", hash: event.hash, confirmations: 0, required: event.required }
        : state;
    case "CONFIRMATION":
      return state.kind === "pending" ? { ...state, confirmations: event.confirmations } : state;
    case "CONFIRMED":
      return state.kind === "pending"
        ? { kind: "confirmed", hash: state.hash, blockNumber: event.blockNumber }
        : state;
    case "REPLACED":
      if (state.kind !== "pending") return state;
      // "repriced" = the user sped up the SAME tx (same nonce, same call, higher fee):
      // keep waiting, now on the new hash. "cancelled"/"replaced" = our tx will never land.
      return event.reason === "repriced"
        ? { ...state, hash: event.replacedBy }
        : { kind: "replaced", hash: state.hash, replacedBy: event.replacedBy, reason: event.reason };
    case "FAILED":
      if (isTerminal(state) || state.kind === "idle") return state;
      return { kind: "failed", message: event.message, hash: state.kind === "pending" ? state.hash : undefined };
  }
}

export function isTerminal(state: TxState): boolean {
  return state.kind === "confirmed" || state.kind === "failed" || state.kind === "replaced";
}

export function isBusy(state: TxState): boolean {
  return state.kind === "simulating" || state.kind === "awaitingSignature" || state.kind === "pending";
}
