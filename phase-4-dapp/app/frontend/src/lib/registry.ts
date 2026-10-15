import type { Address, PublicClient } from "viem";
import { documentRegistryAbi } from "../abi/DocumentRegistry";

export interface RegistryStats {
  recordCount: bigint;
  maxLabelLength: bigint;
  maxUriLength: bigint;
}

/** Read-only contract calls: free `eth_call`s through our public RPC. No wallet needed. */
export async function readStats(client: PublicClient, address: Address): Promise<RegistryStats> {
  const base = { address, abi: documentRegistryAbi } as const;
  const [recordCount, maxLabelLength, maxUriLength] = await Promise.all([
    client.readContract({ ...base, functionName: "recordCount" }),
    client.readContract({ ...base, functionName: "MAX_LABEL_LENGTH" }),
    client.readContract({ ...base, functionName: "MAX_URI_LENGTH" }),
  ]);
  return { recordCount, maxLabelLength, maxUriLength };
}

/** True if bytecode exists at `address`. Catches "wrong network" and "not deployed" early. */
export async function isDeployed(client: PublicClient, address: Address): Promise<boolean> {
  const code = await client.getCode({ address });
  return code !== undefined && code !== "0x";
}
