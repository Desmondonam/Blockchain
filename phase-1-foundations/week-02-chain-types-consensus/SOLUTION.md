# Week 2 — Worked Solution: Certificate Verification Platform Choice

## 1. Requirements summary

| Actor | Goal | Trust |
|-------|------|-------|
| Institution (issuer) | Issue and revoke certificates | Trusted for **its own** certificates only |
| Graduate (holder) | Share proof with employers; keep data private | Untrusted to issue |
| Employer (verifier) | Check authenticity + current status quickly | Untrusted, read-only |
| Consortium admin | Onboard or remove institutions | Highly privileged → multisig |

| NFR | Requirement |
|-----|-------------|
| Privacy | **No personal data on-chain.** Store only a salted commitment. |
| Availability | Verification must still work if an institution's website is down. |
| Auditability | Every issuance and revocation gets a permanent, timestamped record. |
| Cost | < $0.05 per issuance at ~50k certificates/year. |
| Longevity | Verifiable for 40+ years, even if the consortium dissolves. |

## 2. Comparison

| Criterion | Ethereum L1 | Ethereum L2 (e.g. Base/Arbitrum) | Bitcoin | Permissioned (Fabric) | Signed PDF + central DB |
|---|---|---|---|---|---|
| Public verifiability without the issuer | ✅ | ✅ (inherits L1 security) | ✅ (OP_RETURN / timestamping) | ❌ needs consortium access | ⚠️ signatures yes, revocation no |
| Programmable roles & revocation | ✅ | ✅ | ❌ very limited | ✅ | ✅ but centralized |
| Cost per issuance | ❌ $0.50–$5+ | ✅ < $0.01 | ⚠️ $0.50–$3 | ✅ ~0 (infra cost) | ✅ ~0 |
| Survives the consortium dissolving | ✅ | ✅ (probably) | ✅ | ❌ | ❌ |
| Tooling / hiring pool | ✅ huge | ✅ same EVM tools | ⚠️ | ⚠️ niche | ✅ |
| Privacy | ⚠️ public: must minimize | ⚠️ same | ⚠️ same | ✅ private channels | ✅ |

## 3. ADR

# ADR-0001: Use an EVM chain (L2 in production) for certificate commitments

- **Status:** Accepted · **Date:** 2026-10-15

**Context.** Employers need to verify certificates issued by many
institutions that don't trust each other or a single operator. Verification
should survive any single organization disappearing. Certificates contain
personal data that must never become public.

**Decision.** Store only `keccak256(salt ‖ canonical certificate bytes)`
commitments, issuer identity, timestamps and revocation status in a Solidity
contract on an **Ethereum L2**. Develop and test on Anvil and a public
testnet. Keep certificate documents off-chain, encrypted, and controlled by
the holder.

**Consequences.**
- ✅ Public, issuer-independent verification and an auditable revocation log.
- ✅ Low fees, and the standard EVM toolchain (Foundry, OpenZeppelin, viem).
- ⚠️ L2 adds a sequencer trust assumption (liveness and censorship), so we
  document it and rely on forced inclusion via L1.
- ⚠️ The salt must be shared with verifiers out-of-band (QR code/link), or
  the hash can't be checked. Without a salt, a hash of guessable data can be
  brute-forced.
- ❌ We rejected Fabric because verification would depend on consortium
  membership. We rejected central DB + PDFs because revocation status depends
  on one operator staying online and honest.
