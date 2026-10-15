import type { Address, Hex, PublicClient } from "viem";
import { documentRegistryAbi } from "../abi/DocumentRegistry";

export const STATUS_LABEL = ["None", "Active", "Retired"] as const;

export interface RecordView {
  id: bigint;
  owner: Address;
  status: (typeof STATUS_LABEL)[number];
  registeredAt: Date;
  documentHash: Hex;
  label: string;
  uri: string;
}

export async function getRecord(client: PublicClient, registry: Address, id: bigint): Promise<RecordView> {
  const r = await client.readContract({ address: registry, abi: documentRegistryAbi, functionName: "getRecord", args: [id] });
  return {
    id,
    owner: r.owner,
    status: STATUS_LABEL[r.status] ?? "None",
    registeredAt: new Date(Number(r.registeredAt) * 1000),
    documentHash: r.documentHash,
    label: r.label,
    uri: r.uri,
  };
}

export type Verification =
  | { found: false }
  | { found: true; active: boolean; record: RecordView };

/** The verifier's question: is this fingerprint registered, and is it still active? */
export async function verifyFingerprint(client: PublicClient, registry: Address, hash: Hex): Promise<Verification> {
  const [exists, active, id] = await client.readContract({
    address: registry,
    abi: documentRegistryAbi,
    functionName: "verify",
    args: [hash],
  });
  if (!exists) return { found: false };
  return { found: true, active, record: await getRecord(client, registry, id) };
}
