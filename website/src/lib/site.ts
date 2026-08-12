const configuredSiteUrl = process.env.NEXT_PUBLIC_SITE_URL;

if (!configuredSiteUrl) {
  throw new Error(
    "NEXT_PUBLIC_SITE_URL must be set before building or running the website.",
  );
}

export const siteUrl = new URL(configuredSiteUrl);

export const repositoryUrl = "https://github.com/LordGhostX/grantline";
export const xUrl = "https://x.com/usegrantline";
