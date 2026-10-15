import { formatEther, type PublicClient } from "viem";
import { useEffect, useState } from "react";
import type { useWallet } from "../lib/useWallet";

type WalletState = ReturnType<typeof useWallet>;

export function shortAddress(address: string): string {
  return `${address.slice(0, 6)}…${address.slice(-4)}`;
}

export function WalletPanel({ wallet, publicClient }: { wallet: WalletState; publicClient: PublicClient }) {
  const { connection } = wallet;
  const [balance, setBalance] = useState<bigint | null>(null);

  // Balance is read through OUR RPC (public client) and refreshed on every new block.
  useEffect(() => {
    if (!connection) return;
    const refresh = () =>
      publicClient.getBalance({ address: connection.address }).then(setBalance).catch(() => setBalance(null));
    refresh();
    return publicClient.watchBlockNumber({ onBlockNumber: refresh, pollingInterval: 2_000 });
  }, [connection, publicClient]);

  if (!connection) {
    return (
      <section className="card">
        <h2>Connect a wallet</h2>
        <div className="row">
          {wallet.wallets.map((w) => (
            <button key={w.info.uuid} onClick={() => wallet.connect(w.provider, w.info.name)}>
              <img src={w.info.icon} alt="" width={18} height={18} /> {w.info.name}
            </button>
          ))}
          {wallet.wallets.length === 0 && <button onClick={wallet.connectLegacy}>Browser wallet</button>}
          {wallet.hasDevAccount && (
            <button className="secondary" onClick={wallet.connectDevAccount}>
              Anvil dev account (local only)
            </button>
          )}
        </div>
        {wallet.error && <p className="error">{wallet.error}</p>}
      </section>
    );
  }

  return (
    <section className="card">
      <h2>Wallet</h2>
      <dl>
        <dt>Account</dt>
        <dd title={connection.address}>{shortAddress(connection.address)}</dd>
        <dt>Via</dt>
        <dd>{connection.name}</dd>
        <dt>Balance</dt>
        <dd>{balance === null ? "…" : `${Number(formatEther(balance)).toFixed(4)} ETH`}</dd>
      </dl>
      <button className="secondary" onClick={wallet.disconnect}>
        Disconnect
      </button>
      {wallet.error && <p className="error">{wallet.error}</p>}
    </section>
  );
}
