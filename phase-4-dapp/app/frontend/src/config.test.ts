import { describe, expect, it } from "vitest";
import { ConfigError, parseConfig } from "./config";

const valid = {
  VITE_CHAIN_ID: "31337",
  VITE_RPC_URL: "http://127.0.0.1:8545",
  VITE_REGISTRY_ADDRESS: "0x5FbDB2315678afecb367f032d93F642f64180aa3",
};
const ANVIL_KEY_1 = "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d";

describe("parseConfig", () => {
  it("accepts a valid local config", () => {
    const c = parseConfig(valid);
    expect(c.chainId).toBe(31337);
    expect(c.indexerUrl).toBe("http://127.0.0.1:8000");
  });

  it.each([
    [{ VITE_CHAIN_ID: "abc" }, /CHAIN_ID/],
    [{ VITE_CHAIN_ID: "-1" }, /CHAIN_ID/],
    [{ VITE_RPC_URL: "127.0.0.1:8545" }, /RPC_URL/],
    [{ VITE_REGISTRY_ADDRESS: "0x1234" }, /REGISTRY_ADDRESS/],
  ])("rejects bad value %o", (override, message) => {
    expect(() => parseConfig({ ...valid, ...override })).toThrowError(message);
  });

  it("allows the dev key only on Anvil", () => {
    expect(parseConfig({ ...valid, VITE_DEV_PRIVATE_KEY: ANVIL_KEY_1 }).devPrivateKey).toBe(ANVIL_KEY_1);
    expect(() =>
      parseConfig({ ...valid, VITE_CHAIN_ID: "11155111", VITE_DEV_PRIVATE_KEY: ANVIL_KEY_1 }),
    ).toThrowError(ConfigError);
  });

  it("rejects a malformed dev key", () => {
    expect(() => parseConfig({ ...valid, VITE_DEV_PRIVATE_KEY: "0x1234" })).toThrowError(/32-byte/);
  });
});
