import type { Metadata } from "next";
import type { ReactNode } from "react";

export const metadata: Metadata = {
  title: "Grantline | Financial authorisation for AI agents",
  description:
    "Grantline sits between an AI agent's signed intent and execution, checking current authority before controlled capital can move.",
  robots: {
    index: false,
    follow: true,
  },
};

export default function V2Layout({ children }: { children: ReactNode }) {
  return children;
}
