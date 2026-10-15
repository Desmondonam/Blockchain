import { useCallback, useEffect, useState } from "react";
import type { Chain, EIP1193Provider, Hex } from "viem";
import {
  connectDev,
  connectInjected,
  discoverWallets,
  ensureChain,
  legacyInjectedProvider,
  type Connection,
  type DiscoveredWallet,
} from "./wallet";

/** React state for wallet discovery, connection, and wallet events. */
export function useWallet(chain: Chain, rpcUrl: string, devPrivateKey?: Hex) {
  const [wallets, setWallets] = useState<DiscoveredWallet[]>([]);
  const [connection, setConnection] = useState<Connection | null>(null);
  const [error, setError] = useState<string | null>(null);

  // Discover EIP-6963 wallets once.
  useEffect(
    () =>
      discoverWallets((w) =>
        setWallets((prev) => (prev.some((p) => p.info.uuid === w.info.uuid) ? prev : [...prev, w])),
      ),
    [],
  );

  const connect = useCallback(
    async (provider: EIP1193Provider, name: string) => {
      setError(null);
      try {
        setConnection(await connectInjected(provider, name, chain));
      } catch (e) {
        // 4001 = user rejected the request. That's a choice, not an error to shout about.
        const code = (e as { code?: number }).code;
        setError(code === 4001 ? "Connection request was rejected in the wallet." : String(e));
      }
    },
    [chain],
  );

  const connectLegacy = useCallback(async () => {
    const provider = legacyInjectedProvider();
    if (!provider) {
      setError("No browser wallet found. Install one, or use the Anvil dev account locally.");
      return;
    }
    await connect(provider, "Injected wallet");
  }, [connect]);

  const connectDevAccount = useCallback(() => {
    if (!devPrivateKey) return;
    setError(null);
    setConnection(connectDev(devPrivateKey, chain, rpcUrl));
  }, [chain, rpcUrl, devPrivateKey]);

  const disconnect = useCallback(() => setConnection(null), []);

  const switchNetwork = useCallback(async () => {
    if (!connection) return;
    try {
      await ensureChain(connection, chain);
    } catch (e) {
      setError(`Could not switch network: ${String(e)}`);
    }
  }, [connection, chain]);

  // React to the user changing account or network INSIDE the wallet.
  useEffect(() => {
    const provider = connection?.provider;
    if (!provider) return;
    const onAccounts = (accounts: unknown) => {
      const list = accounts as string[];
      if (list.length === 0) setConnection(null); // user disconnected the site
      else void connect(provider, connection.name);
    };
    const onChain = (chainIdHex: unknown) =>
      setConnection((c) => (c ? { ...c, walletChainId: Number(chainIdHex as string) } : c));
    provider.on("accountsChanged", onAccounts);
    provider.on("chainChanged", onChain);
    return () => {
      provider.removeListener("accountsChanged", onAccounts);
      provider.removeListener("chainChanged", onChain);
    };
  }, [connection?.provider, connection?.name, connect]);

  return {
    wallets,
    connection,
    error,
    wrongNetwork: connection !== null && connection.walletChainId !== chain.id,
    connect,
    connectLegacy,
    connectDevAccount,
    disconnect,
    switchNetwork,
    hasDevAccount: Boolean(devPrivateKey),
  };
}
