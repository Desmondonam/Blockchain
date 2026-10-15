import { useCallback, useReducer } from "react";
import type { Address, PublicClient } from "viem";
import { initialTxState, isBusy, txReducer } from "./txState";
import type { TxContext } from "./writes";
import type { Connection } from "./wallet";

/** Wires the pure tx state machine to React and builds a TxContext for the write helpers. */
export function useTx(publicClient: PublicClient, registry: Address, connection: Connection | null, confirmations: number) {
  const [state, dispatch] = useReducer(txReducer, initialTxState);

  const context = useCallback((): TxContext | null => {
    if (!connection) return null;
    return { publicClient, walletClient: connection.walletClient, registry, confirmations, onEvent: dispatch };
  }, [publicClient, registry, connection, confirmations]);

  return { state, busy: isBusy(state), context, reset: () => dispatch({ type: "RESET" }) };
}
