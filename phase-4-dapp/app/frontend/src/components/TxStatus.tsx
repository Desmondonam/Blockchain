import type { TxState } from "../lib/txState";

/** One component that renders every state of the tx machine, so users always know what's going on. */
export function TxStatus({ state }: { state: TxState }) {
  switch (state.kind) {
    case "idle":
      return null;
    case "simulating":
      return <p className="muted">① Checking the transaction would succeed (simulation)…</p>;
    case "awaitingSignature":
      return <p className="muted">② Confirm the transaction in your wallet…</p>;
    case "pending":
      return (
        <p className="muted">
          ③ Submitted <code>{state.hash.slice(0, 10)}…</code>. Waiting for confirmations:{" "}
          {state.confirmations}/{state.required}
        </p>
      );
    case "confirmed":
      return (
        <p className="ok">
          ✔ Confirmed in block {state.blockNumber.toString()} (<code>{state.hash.slice(0, 10)}…</code>)
        </p>
      );
    case "replaced":
      return (
        <p className="error">
          Your transaction was {state.reason} in the wallet by <code>{state.replacedBy.slice(0, 10)}…</code>.
        </p>
      );
    case "failed":
      return <p className="error">✘ {state.message}</p>;
  }
}
