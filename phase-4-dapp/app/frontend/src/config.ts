import { isAddress, isHex, type Address, type Hex } from "viem";

/** Typed, validated app configuration. Built once at startup so bad config fails fast. */
export interface AppConfig {
  chainId: number;
  rpcUrl: string;
  registryAddress: Address;
  indexerUrl: string;
  devPrivateKey?: Hex;
}

export class ConfigError extends Error {}

type Env = Record<string, string | undefined>;

/** Pure function: easy to unit-test, independent of Vite. */
export function parseConfig(env: Env): AppConfig {
  const chainId = Number(env.VITE_CHAIN_ID);
  if (!Number.isInteger(chainId) || chainId <= 0) {
    throw new ConfigError(`VITE_CHAIN_ID must be a positive integer, got "${env.VITE_CHAIN_ID}"`);
  }
  const rpcUrl = env.VITE_RPC_URL ?? "";
  if (!/^https?:\/\//.test(rpcUrl)) {
    throw new ConfigError(`VITE_RPC_URL must be an http(s) URL, got "${rpcUrl}"`);
  }
  const registryAddress = env.VITE_REGISTRY_ADDRESS ?? "";
  if (!isAddress(registryAddress)) {
    throw new ConfigError(`VITE_REGISTRY_ADDRESS is not a valid address: "${registryAddress}"`);
  }
  const devKey = env.VITE_DEV_PRIVATE_KEY;
  let devPrivateKey: Hex | undefined;
  if (devKey) {
    // Guardrail: a dev key in the bundle is acceptable ONLY for the local test chain.
    if (chainId !== 31337) {
      throw new ConfigError("VITE_DEV_PRIVATE_KEY is only allowed when VITE_CHAIN_ID=31337 (Anvil)");
    }
    if (!isHex(devKey) || devKey.length !== 66) {
      throw new ConfigError("VITE_DEV_PRIVATE_KEY must be a 32-byte hex string");
    }
    devPrivateKey = devKey;
  }
  return {
    chainId,
    rpcUrl,
    registryAddress,
    indexerUrl: env.VITE_INDEXER_URL ?? "http://127.0.0.1:8000",
    devPrivateKey,
  };
}
