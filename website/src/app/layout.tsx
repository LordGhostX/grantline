import { RootProvider } from "fumadocs-ui/provider/next";
import { Geist, Geist_Mono } from "next/font/google";
import type { Metadata } from "next";
import type { ReactNode } from "react";
import { siteUrl } from "@/lib/site";
import "./global.css";

export const metadata: Metadata = {
  metadataBase: siteUrl,
  title: "Grantline | Programmable financial authority for AI agents",
  description:
    "Grantline gives AI agents bounded authority over capital, with enforceable limits, delegation, owner approval, and traceable execution.",
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
      </body>
    </html>
  );
}
