import {
  createWalletClient,
  custom,
  http,
  type Account,
  type Address,
  type Chain,
  type EIP1193Provider,
  type Hex,
  type Transport,
  type WalletClient,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";

/** EIP-6963: wallets announce themselves, so several can coexist (no window.ethereum fights). */
export interface WalletInfo {
  uuid: string;
  name: string;
  icon: string;
  rdns: string;
}
export interface DiscoveredWallet {
  info: WalletInfo;
  provider: EIP1193Provider;
}

export function discoverWallets(onFound: (w: DiscoveredWallet) => void): () => void {
  const handler = (event: Event) => onFound((event as CustomEvent<DiscoveredWallet>).detail);
  window.addEventListener("eip6963:announceProvider", handler);
  window.dispatchEvent(new Event("eip6963:requestProvider"));
  return () => window.removeEventListener("eip6963:announceProvider", handler);
}

/** Legacy fallback (EIP-1193 injected provider) for wallets that don't support EIP-6963 yet. */
export function legacyInjectedProvider(): EIP1193Provider | undefined {
  return (window as unknown as { ethereum?: EIP1193Provider }).ethereum;
}

export type AppWalletClient = WalletClient<Transport, Chain, Account>;

export interface Connection {
  kind: "injected" | "dev";
  name: string;
  address: Address;
  walletChainId: number;
  walletClient: AppWalletClient;
  provider?: EIP1193Provider;
}

/** Ask an injected wallet for account access (this opens the wallet's approval popup). */
export async function connectInjected(
  provider: EIP1193Provider,
  name: string,
  chain: Chain,
): Promise<Connection> {
  const probe = createWalletClient({ chain, transport: custom(provider) });
  const [address] = await probe.requestAddresses();
  if (!address) throw new Error("Wallet returned no accounts");
  const walletChainId = await probe.getChainId();
  const walletClient = createWalletClient({ account: address, chain, transport: custom(provider) });
  return { kind: "injected", name, address, walletChainId, walletClient, provider };
}

/** LOCAL ONLY: sign with an Anvil test key inside the page. Never do this with a real key. */
export function connectDev(privateKey: Hex, chain: Chain, rpcUrl: string): Connection {
  if (chain.id !== 31337) throw new Error("Dev wallet is restricted to the local Anvil chain");
  const account = privateKeyToAccount(privateKey);
  const walletClient = createWalletClient({ account, chain, transport: http(rpcUrl) });
  return {
    kind: "dev",
    name: "Anvil dev account",
    address: account.address,
    walletChainId: chain.id,
    walletClient,
  };
}

/** Ask the wallet to switch to our chain, adding it first if the wallet doesn't know it. */
export async function ensureChain(connection: Connection, chain: Chain): Promise<void> {
  try {
    await connection.walletClient.switchChain({ id: chain.id });
  } catch (error) {
    // 4902 = "Unrecognized chain ID" (EIP-3326). Viem wraps it; check both shapes.
    const code = (error as { code?: number; cause?: { code?: number } }).code ??
      (error as { cause?: { code?: number } }).cause?.code;
    if (code !== 4902) throw error;
    await connection.walletClient.addChain({ chain });
  }
}
