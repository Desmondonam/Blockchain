import { useEffect, useState } from "react";
import type { Address, PublicClient } from "viem";
import { isDeployed, readStats, type RegistryStats as Stats } from "../lib/registry";

export function RegistryStats({
  publicClient,
  address,
  refreshKey,
}: {
  publicClient: PublicClient;
  address: Address;
  refreshKey?: number;
}) {
  const [stats, setStats] = useState<Stats | null>(null);
  const [blockNumber, setBlockNumber] = useState<bigint | null>(null);
  const [problem, setProblem] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        if (!(await isDeployed(publicClient, address))) {
          setProblem(`No contract at ${address} on this RPC. Did you deploy it, and is the chain running?`);
          return;
        }
        const s = await readStats(publicClient, address);
        if (!cancelled) {
          setStats(s);
          setProblem(null);
        }
      } catch (e) {
        if (!cancelled) setProblem(`RPC error: ${(e as Error).message}`);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [publicClient, address, refreshKey, blockNumber]);

  useEffect(
    () => publicClient.watchBlockNumber({ onBlockNumber: setBlockNumber, pollingInterval: 2_000 }),
    [publicClient],
  );

  return (
    <section className="card">
      <h2>Registry</h2>
      {problem ? (
        <p className="error">{problem}</p>
      ) : (
        <dl>
          <dt>Contract</dt>
          <dd className="mono">{address}</dd>
          <dt>Records</dt>
          <dd>{stats ? stats.recordCount.toString() : "…"}</dd>
          <dt>Latest block</dt>
          <dd>{blockNumber?.toString() ?? "…"}</dd>
        </dl>
      )}
    </section>
  );
}
