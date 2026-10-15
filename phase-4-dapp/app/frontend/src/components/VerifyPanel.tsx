import { useState, type FormEvent } from "react";
import { isAddress, isHex, type Address, type Hex, type PublicClient } from "viem";
import { describeError } from "../lib/errors";
import { fingerprint, readFileBytes } from "../lib/hashing";
import { verifyFingerprint, type Verification } from "../lib/reads";
import type { useTx } from "../lib/useTx";
import { retireRecord, transferRecord } from "../lib/writes";
import { TxStatus } from "./TxStatus";
import { shortAddress } from "./WalletPanel";

type Tx = ReturnType<typeof useTx>;

/** Verification needs NO wallet: it's a free read anyone can do. */
export function VerifyPanel({
  publicClient,
  registry,
  account,
  tx,
}: {
  publicClient: PublicClient;
  registry: Address;
  account: Address | null;
  tx: Tx;
}) {
  const [file, setFile] = useState<File | null>(null);
  const [salt, setSalt] = useState("");
  const [result, setResult] = useState<Verification | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [recipient, setRecipient] = useState("");

  async function onVerify(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setResult(null);
    if (!file || !isHex(salt.trim())) return setError("Choose the file and paste its 0x… verification code.");
    try {
      const hash = fingerprint(await readFileBytes(file), salt.trim() as Hex);
      setResult(await verifyFingerprint(publicClient, registry, hash));
    } catch (err) {
      setError(describeError(err));
    }
  }

  async function refresh() {
    if (result?.found) setResult(await verifyFingerprint(publicClient, registry, result.record.documentHash));
  }

  const record = result?.found ? result.record : null;
  const isOwner = record !== null && account !== null && record.owner.toLowerCase() === account.toLowerCase();

  return (
    <section className="card">
      <h2>Verify a document</h2>
      <form onSubmit={onVerify}>
        <label htmlFor="vfile">Document</label>
        <input id="vfile" type="file" onChange={(e) => setFile(e.target.files?.[0] ?? null)} />
        <label htmlFor="salt">Verification code</label>
        <input id="salt" className="mono" value={salt} onChange={(e) => setSalt(e.target.value)} placeholder="0x…" />
        <button type="submit">Verify</button>
      </form>
      {error && <p className="error">{error}</p>}
      {result && !result.found && <p className="error">✘ Not registered. This document (with this code) was never recorded.</p>}
      {record && (
        <>
          <p className={record.status === "Active" ? "ok" : "error"}>
            {record.status === "Active" ? "✔ Authentic and active" : "⚠ Authentic but RETIRED. No longer valid."}
          </p>
          <dl>
            <dt>Record</dt>
            <dd>#{record.id.toString()}</dd>
            <dt>Label</dt>
            <dd>{record.label}</dd>
            <dt>Owner</dt>
            <dd title={record.owner}>{shortAddress(record.owner)}</dd>
            <dt>Registered</dt>
            <dd>{record.registeredAt.toLocaleString()}</dd>
            {record.uri && (
              <>
                <dt>Stored at</dt>
                <dd className="mono">{record.uri}</dd>
              </>
            )}
          </dl>
          {isOwner && record.status === "Active" && (
            <div className="row">
              <button
                className="secondary"
                disabled={tx.busy}
                onClick={async () => {
                  const ctx = tx.context();
                  if (ctx && (await retireRecord(ctx, record.id))) await refresh();
                }}
              >
                Retire
              </button>
              <input value={recipient} onChange={(e) => setRecipient(e.target.value)} placeholder="0x recipient" style={{ flex: 1 }} />
              <button
                disabled={tx.busy || !isAddress(recipient)}
                onClick={async () => {
                  const ctx = tx.context();
                  if (ctx && (await transferRecord(ctx, record.id, recipient as Address))) await refresh();
                }}
              >
                Transfer
              </button>
            </div>
          )}
          <TxStatus state={tx.state} />
        </>
      )}
    </section>
  );
}
