import { formatError } from "@/lib/app-utils";

type Props = {
  error?: unknown;
  isPending: boolean;
  message?: string;
};

export function TransactionStatus({ error, isPending, message }: Props) {
  if (error) {
    return (
      <p
        className="app-alert app-alert-error app-transaction-status"
        role="alert"
      >
        {formatError(error)}
      </p>
    );
  }

  if (!isPending) return null;

  return (
    <p
      className="app-alert app-alert-info app-transaction-status"
      role="status"
      aria-live="polite"
    >
      {message ?? "Confirm the transaction in your wallet…"}
    </p>
  );
}
