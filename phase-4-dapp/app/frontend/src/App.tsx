import { useMemo } from "react";
import type { AppConfig } from "./config";
import { makeChain, makePublicClient } from "./lib/chain";
import { useWallet } from "./lib/useWallet";
import { WalletPanel } from "./components/WalletPanel";
import { NetworkGuard } from "./components/NetworkGuard";
import { RegistryStats } from "./components/RegistryStats";

export function App({ config }: { config: AppConfig }) {
  const chain = useMemo(() => makeChain(config), [config]);
  const publicClient = useMemo(() => makePublicClient(chain, config.rpcUrl), [chain, config.rpcUrl]);
  const wallet = useWallet(chain, config.rpcUrl, config.devPrivateKey);

  return (
    <main>
      <header>
        <h1>Document Registry</h1>
        <span className="pill">{chain.name}</span>
      </header>

      {wallet.wrongNetwork && wallet.connection && (
        <NetworkGuard chain={chain} walletChainId={wallet.connection.walletChainId} onSwitch={wallet.switchNetwork} />
      )}

      <div className="grid">
        <WalletPanel wallet={wallet} publicClient={publicClient} />
        <RegistryStats publicClient={publicClient} address={config.registryAddress} />
      </div>
    </main>
  );
}
