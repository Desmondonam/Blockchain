/**
 * Integration tests against a REAL local chain. Run with:
 *   anvil &   (then deploy: see README)
 *   INTEGRATION_RPC_URL=http://127.0.0.1:8545 INTEGRATION_REGISTRY=0x5FbD... npm test
 * Without those variables these tests are skipped, so `npm test` stays fast and offline.
 */
import { describe, expect, it } from "vitest";
import { getAddress, type Address } from "viem";
import { makeChain, makePublicClient } from "./chain";
import { isDeployed, readStats } from "./registry";
import type { AppConfig } from "../config";

const rpcUrl = process.env.INTEGRATION_RPC_URL;
const registry = process.env.INTEGRATION_REGISTRY as Address | undefined;

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

describe.skipIf(!rpcUrl || !registry)("registry reads (integration)", () => {
  it("finds the deployed contract and reads its constants", async () => {
    const { config, publicClient } = integrationSetup();
    expect(await isDeployed(publicClient, config.registryAddress)).toBe(true);
    const stats = await readStats(publicClient, config.registryAddress);
    expect(stats.maxLabelLength).toBe(64n);
    expect(stats.maxUriLength).toBe(128n);
  });

  it("reports an empty address as not deployed", async () => {
    const { publicClient } = integrationSetup();
    expect(await isDeployed(publicClient, "0x000000000000000000000000000000000000dEaD")).toBe(false);
  });
});
