import { type ReactNode } from "react";
import type { Viewport } from "next";
import { headers } from "next/headers";
import { cookieToInitialState } from "wagmi";
import { getConfig } from "@/lib/wagmi";
import { Providers } from "@/components/app/providers";
import { Sidebar } from "@/components/app/sidebar";
import "./app.css";

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
};

export default async function AppLayout({ children }: { children: ReactNode }) {
  const initialState = cookieToInitialState(
    getConfig(),
    (await headers()).get("cookie"),
  );

  return (
    <Providers initialState={initialState}>
      <Sidebar>{children}</Sidebar>
    </Providers>
  );
}
