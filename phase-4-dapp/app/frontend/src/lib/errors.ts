import {
  BaseError,
  ContractFunctionRevertedError,
  InsufficientFundsError,
  UserRejectedRequestError,
} from "viem";

/** Map the contract's custom errors to messages a non-developer understands. */
export function friendlyContractError(name: string, args: readonly unknown[] = []): string {
  switch (name) {
    case "EmptyHash":
      return "The document fingerprint is empty.";
    case "AlreadyRegistered":
      return `This exact document is already registered (record #${String(args[1])}).`;
    case "UnknownRecord":
      return `Record #${String(args[0])} does not exist.`;
    case "NotRecordOwner":
      return `Only the owner of record #${String(args[0])} can do that.`;
    case "RecordNotActive":
      return `Record #${String(args[0])} is retired and can no longer change.`;
    case "InvalidRecipient":
      return "That recipient address isn't allowed (zero address or yourself).";
    case "InvalidLabel":
      return "The label must be between 1 and 64 characters.";
    case "InvalidUri":
      return "The storage reference is too long (max 128 characters).";
    default:
      return `The contract rejected the transaction (${name}).`;
  }
}

/**
 * Turn ANY error from viem/the wallet into one user-facing sentence.
 * viem errors are nested: walk the chain to find the most specific cause.
 */
export function describeError(error: unknown): string {
  if (error instanceof BaseError) {
    const reverted = error.walk((e) => e instanceof ContractFunctionRevertedError);
    if (reverted instanceof ContractFunctionRevertedError) {
      const name = reverted.data?.errorName;
      if (name) return friendlyContractError(name, reverted.data?.args ?? []);
      if (reverted.reason) return `The contract rejected the transaction: ${reverted.reason}`;
    }
    if (error.walk((e) => e instanceof UserRejectedRequestError)) {
      return "You rejected the request in your wallet. Nothing was sent.";
    }
    if (error.walk((e) => e instanceof InsufficientFundsError)) {
      return "Your account doesn't have enough ETH to pay for gas.";
    }
    return error.shortMessage;
  }
  return error instanceof Error ? error.message : String(error);
}
