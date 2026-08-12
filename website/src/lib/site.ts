const configuredSiteUrl =
  process.env.NEXT_PUBLIC_SITE_URL?.trim() ||
  (process.env.VERCEL_URL ? `https://${process.env.VERCEL_URL}` : undefined);

if (!configuredSiteUrl) {
  throw new Error(
    "NEXT_PUBLIC_SITE_URL or VERCEL_URL must be set before building or running the website.",
  );
}

export const siteUrl = new URL(configuredSiteUrl);
