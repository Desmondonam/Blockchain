import type { Chain } from "viem";

/** Block writes when the wallet is on the wrong network. Sending to the wrong chain is a classic bug. */
export function NetworkGuard({
  chain,
  walletChainId,
  onSwitch,
}: {
  chain: Chain;
  walletChainId: number;
  onSwitch: () => void;
}) {
  return (
    <div className="banner warning" role="alert">
      Your wallet is on chain <b>{walletChainId}</b>, but this app runs on <b>{chain.name}</b> ({chain.id}).
      <button onClick={onSwitch}>Switch network</button>
    </div>
  );
}
