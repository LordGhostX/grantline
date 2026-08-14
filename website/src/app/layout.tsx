import { RootProvider } from "fumadocs-ui/provider/next";
import { Analytics } from "@vercel/analytics/next";
import { Geist, Geist_Mono } from "next/font/google";
import type { Metadata, Viewport } from "next";
import type { ReactNode } from "react";
import { siteUrl } from "@/lib/site";
import "./global.css";

export const metadata: Metadata = {
  metadataBase: siteUrl,
  title: "Grantline | Financial authorisation for AI agents",
  description:
    "Grantline sits between an AI agent's signed intent and execution, checking current authority before controlled capital can move.",
};

export const viewport: Viewport = {
  colorScheme: "dark",
  themeColor: "#0c0f0d",
};

const geist = Geist({
  variable: "--font-geist",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export default function Layout({ children }: { children: ReactNode }) {
  return (
    <html
      lang="en"
      suppressHydrationWarning
      className={`dark ${geist.variable} ${geistMono.variable}`}
    >
      <body className="flex flex-col min-h-screen">
        <RootProvider theme={{ enabled: false }}>{children}</RootProvider>
        <Analytics />
      </body>
    </html>
  );
}
