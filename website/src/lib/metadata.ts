import type { Metadata } from "next";
import { siteUrl } from "@/lib/site";

export const siteName = "Grantline";
export const siteTitle = "Grantline | Financial authorisation for AI agents";
export const siteDescription =
  "Grantline sits between an AI agent's signed intent and execution, checking current authority before controlled capital can move.";

export function createSocialMetadata({
  title,
  description,
  path,
}: {
  title: string;
  description?: string;
  path: string;
}): Pick<Metadata, "openGraph" | "twitter"> {
  const descriptionFields = description ? { description } : {};

  return {
    openGraph: {
      title,
      url: new URL(path, siteUrl).toString(),
      siteName,
      type: "website",
      ...descriptionFields,
    },
    twitter: {
      card: "summary",
      title,
      ...descriptionFields,
    },
  };
}
