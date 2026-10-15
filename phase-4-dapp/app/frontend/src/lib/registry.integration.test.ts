/**
 * Integration tests against a REAL local chain. Run with:
 *   anvil &   (then deploy: see README)
 *   INTEGRATION_RPC_URL=http://127.0.0.1:8545 INTEGRATION_REGISTRY=0x5FbD... npm test
 * Without those variables these tests are skipped, so `npm test` stays fast and offline.
 */
import { describe, expect, it } from "vitest";
import { isDeployed, readStats } from "./registry";
import { integrationEnabled, integrationSetup } from "../test/integration";

describe.skipIf(!integrationEnabled)("registry reads (integration)", () => {
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
