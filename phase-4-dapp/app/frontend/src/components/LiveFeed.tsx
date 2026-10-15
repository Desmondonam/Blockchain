import { useEffect, useState } from "react";
import type { Address, PublicClient } from "viem";
import { documentRegistryAbi } from "../abi/DocumentRegistry";
import { describeRegistryLog, logKey, parseRegistryLogs } from "../lib/events";

interface FeedItem {
  key: string;
  block: bigint;
  text: string;
}

/**
 * Live view of contract events via eth_getLogs polling (viem's watchContractEvent).
 * Fine for a live feed. For history and search, use the indexer (Week 12): browsers
 * shouldn't scan the whole chain on every page load.
 */
export function LiveFeed({ publicClient, registry }: { publicClient: PublicClient; registry: Address }) {
  const [items, setItems] = useState<FeedItem[]>([]);

  useEffect(
    () =>
      publicClient.watchContractEvent({
        address: registry,
        abi: documentRegistryAbi,
        pollingInterval: 2_000,
        onLogs: (logs) =>
          setItems((prev) => {
            const next = [...prev];
            for (const log of parseRegistryLogs(logs)) {
              const key = logKey(log);
              if (next.some((i) => i.key === key)) continue; // polling can deliver a log twice
              next.unshift({ key, block: log.blockNumber ?? 0n, text: describeRegistryLog(log) });
            }
            return next.slice(0, 20);
          }),
      }),
    [publicClient, registry],
  );

  return (
    <section className="card">
      <h2>Live events</h2>
      {items.length === 0 ? (
        <p className="muted">Waiting for new events…</p>
      ) : (
        <ul>
          {items.map((i) => (
            <li key={i.key}>
              <span className="muted">block {i.block.toString()}:</span> {i.text}
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
