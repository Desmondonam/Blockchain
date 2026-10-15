/** Shared setup for integration tests that run against a live Anvil node. */
import { getAddress, type Address } from "viem";
import { makeChain, makePublicClient } from "../lib/chain";
import type { AppConfig } from "../config";

export const rpcUrl = process.env.INTEGRATION_RPC_URL;
export const registry = process.env.INTEGRATION_REGISTRY as Address | undefined;
export const integrationEnabled = Boolean(rpcUrl && registry);

export function integrationSetup() {
  const config: AppConfig = {
    chainId: 31337,
    rpcUrl: rpcUrl!,
    registryAddress: getAddress(registry!),
    indexerUrl: "",
  };
  const chain = makeChain(config);
  return { config, chain, publicClient: makePublicClient(chain, rpcUrl!) };
}
