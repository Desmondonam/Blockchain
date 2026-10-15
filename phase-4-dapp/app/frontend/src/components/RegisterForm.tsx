import { useState, type FormEvent } from "react";
import type { Hex } from "viem";
import { fingerprint, generateSalt, readFileBytes } from "../lib/hashing";
import type { useTx } from "../lib/useTx";
import { registerDocument, registeredIdFromReceipt } from "../lib/writes";
import { TxStatus } from "./TxStatus";

type Tx = ReturnType<typeof useTx>;

export interface Prepared {
  hash: Hex;
  salt: Hex;
  fileName: string;
}

export function RegisterForm({
  tx,
  disabled,
  uploadDocument,
  onRegistered,
}: {
  tx: Tx;
  disabled: boolean;
  /** Week 12: optional off-chain upload. Returns the uri to store on-chain. */
  uploadDocument?: (file: File, prepared: Prepared) => Promise<string>;
  onRegistered?: (id: bigint) => void;
}) {
  const [file, setFile] = useState<File | null>(null);
  const [label, setLabel] = useState("");
  const [prepared, setPrepared] = useState<Prepared | null>(null);
  const [registeredId, setRegisteredId] = useState<bigint | null>(null);
  const [uploadError, setUploadError] = useState<string | null>(null);

  async function onFile(f: File | null) {
    setFile(f);
    setRegisteredId(null);
    tx.reset();
    if (!f) return setPrepared(null);
    const salt = generateSalt();
    setPrepared({ hash: fingerprint(await readFileBytes(f), salt), salt, fileName: f.name });
  }

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    const ctx = tx.context();
    if (!ctx || !prepared || !file) return;
    setUploadError(null);
    let uri = "";
    if (uploadDocument) {
      try {
        uri = await uploadDocument(file, prepared);
      } catch (err) {
        setUploadError(`Off-chain upload failed, nothing was registered: ${(err as Error).message}`);
        return;
      }
    }
    const receipt = await registerDocument(ctx, prepared.hash, label.trim(), uri);
    const id = receipt ? registeredIdFromReceipt(receipt) : undefined;
    if (id !== undefined) {
      setRegisteredId(id);
      onRegistered?.(id);
    }
  }

  return (
    <section className="card">
      <h2>Register a document</h2>
      <form onSubmit={onSubmit}>
        <label htmlFor="file">Document (hashed locally; only the fingerprint goes on-chain)</label>
        <input id="file" type="file" onChange={(e) => onFile(e.target.files?.[0] ?? null)} />

        <label htmlFor="label">Public label (no personal data)</label>
        <input id="label" maxLength={64} value={label} onChange={(e) => setLabel(e.target.value)} placeholder="e.g. Lease 2026-Q3" />

        {prepared && (
          <dl>
            <dt>Fingerprint</dt>
            <dd className="mono">{prepared.hash}</dd>
          </dl>
        )}
        <button type="submit" disabled={disabled || tx.busy || !prepared || label.trim().length === 0}>
          Register
        </button>
      </form>
      <TxStatus state={tx.state} />
      {uploadError && <p className="error">{uploadError}</p>}
      {registeredId !== null && prepared && (
        <div className="banner warning">
          <div>
            <b>Save this verification code.</b> Anyone verifying this file needs it, and it can't be recovered:
            <div className="mono">{prepared.salt}</div>
            Record #{registeredId.toString()}
          </div>
        </div>
      )}
    </section>
  );
}
