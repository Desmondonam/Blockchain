import { useMemo, useState } from "react";
import type { AppConfig } from "./config";
import { makeChain, makePublicClient } from "./lib/chain";
import { useWallet } from "./lib/useWallet";
import { useTx } from "./lib/useTx";
import { WalletPanel } from "./components/WalletPanel";
import { NetworkGuard } from "./components/NetworkGuard";
import { RegistryStats } from "./components/RegistryStats";
import { RegisterForm } from "./components/RegisterForm";
import { VerifyPanel } from "./components/VerifyPanel";
import { LiveFeed } from "./components/LiveFeed";

export function App({ config }: { config: AppConfig }) {
  const chain = useMemo(() => makeChain(config), [config]);
  const publicClient = useMemo(() => makePublicClient(chain, config.rpcUrl), [chain, config.rpcUrl]);
  const wallet = useWallet(chain, config.rpcUrl, config.devPrivateKey);
  // Local chain: 1 confirmation. Public testnets: wait longer (see Week 5 on reorgs).
  const confirmations = config.chainId === 31337 ? 1 : 3;
  const registerTx = useTx(publicClient, config.registryAddress, wallet.connection, confirmations);
  const manageTx = useTx(publicClient, config.registryAddress, wallet.connection, confirmations);
  const [refreshKey, setRefreshKey] = useState(0);

  const canWrite = wallet.connection !== null && !wallet.wrongNetwork;

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
        <RegistryStats publicClient={publicClient} address={config.registryAddress} refreshKey={refreshKey} />
        <RegisterForm tx={registerTx} disabled={!canWrite} onRegistered={() => setRefreshKey((k) => k + 1)} />
        <VerifyPanel
          publicClient={publicClient}
          registry={config.registryAddress}
          account={canWrite ? wallet.connection!.address : null}
          tx={manageTx}
        />
        <LiveFeed publicClient={publicClient} registry={config.registryAddress} />
      </div>
    </main>
  );
}
