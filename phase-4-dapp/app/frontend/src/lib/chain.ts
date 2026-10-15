import { createPublicClient, defineChain, http, type Chain, type PublicClient } from "viem";
import type { AppConfig } from "../config";

/** Describe the chain the app is built for. Wallets use this to add/switch networks. */
export function makeChain(config: AppConfig): Chain {
  return defineChain({
    id: config.chainId,
    name: config.chainId === 31337 ? "Anvil (local)" : `Chain ${config.chainId}`,
    nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
    rpcUrls: { default: { http: [config.rpcUrl] } },
  });
}

/**
 * The PUBLIC client reads chain state through OUR RPC endpoint, never through the wallet.
 * Reads then work before a wallet connects, and stay consistent whichever wallet the user has.
 */
export function makePublicClient(chain: Chain, rpcUrl: string): PublicClient {
  return createPublicClient({ chain, transport: http(rpcUrl, { retryCount: 3, timeout: 10_000 }) });
}
