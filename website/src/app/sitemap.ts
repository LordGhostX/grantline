import type { MetadataRoute } from "next";
import { source } from "@/lib/source";
import { siteUrl } from "@/lib/site";

export default function sitemap(): MetadataRoute.Sitemap {
  const lastModified = new Date();
  const docs = source.getPages().map((page) => ({
    url: new URL(page.url, siteUrl).toString(),
    lastModified,
  }));

  return [
    {
      url: siteUrl.toString(),
      lastModified,
    },
    ...docs,
  ];
}
