import { formatUnits, isAddress, parseEther, type Address } from "viem";

export function formatError(error: unknown): string {
  if (!error) return "";

  if (typeof error === "object" && error !== null && "shortMessage" in error) {
    return String((error as { shortMessage: unknown }).shortMessage);
  }

  if (error instanceof Error) return error.message;
  return String(error);
}

export function truncateAddress(address: string): string {
  return `${address.slice(0, 10)}…${address.slice(-4)}`;
}

export function formatNative(wei: bigint, maximumFractionDigits = 4): string {
  const formatted = formatUnits(wei, 18);
  const numeric = Number(formatted);

  if (numeric === 0) return "0";
  if (numeric < 0.001) return "<0.001";

  return numeric.toLocaleString("en-US", {
    minimumFractionDigits: 0,
    maximumFractionDigits,
  });
}

export function formatNativeBalance(wei: bigint): string {
  return `${formatNative(wei)} OKB`;
}

export function formatDate(timestamp: bigint): string {
  if (timestamp === 0n) return "Any time";
  return new Date(Number(timestamp) * 1000).toLocaleString("en-GB", {
    dateStyle: "medium",
    timeStyle: "short",
  });
}

export function parseNativeAmount(input: string, label: string): bigint {
  const trimmed = input.trim();
  if (!trimmed) throw new Error(`${label} is required.`);

  let amount: bigint;
  try {
    amount = parseEther(trimmed);
  } catch {
    throw new Error(`${label} must be a valid OKB amount.`);
  }

  if (amount <= 0n) throw new Error(`${label} must be greater than zero.`);
  return amount;
}

export function parseOptionalNativeAmount(input: string): bigint {
  const trimmed = input.trim();
  if (!trimmed) return 0n;

  try {
    const amount = parseEther(trimmed);
    if (amount < 0n) throw new Error();
    return amount;
  } catch {
    throw new Error("Native amount fields must contain valid OKB values.");
  }
}

export function parseAddress(input: string, label: string): Address {
  const trimmed = input.trim();
  if (!isAddress(trimmed)) throw new Error(`${label} must be a valid address.`);
  if (/^0x0{40}$/i.test(trimmed))
    throw new Error(`${label} cannot be the zero address.`);
  return trimmed as Address;
}

export function parseDateInput(input: string, label: string): bigint {
  if (!input) return 0n;
  const milliseconds = new Date(input).getTime();
  if (!Number.isFinite(milliseconds))
    throw new Error(`${label} must be a valid date.`);
  return BigInt(Math.floor(milliseconds / 1000));
}

export function assertFutureTimestamp(timestamp: bigint, label: string): void {
  if (timestamp <= BigInt(Math.floor(Date.now() / 1000))) {
    throw new Error(`${label} must be in the future.`);
  }
}
