import { source } from "@/lib/source";
import { siteUrl } from "@/lib/site";

export async function getLLMText(page: (typeof source)["$inferPage"]) {
  const url = new URL(page.url, siteUrl).toString();
  const description = page.data.description
    ? `${page.data.description.trim()}\n\n`
    : "";
  const processed = await page.data.getText("processed");
  return `# ${page.data.title} (${url})\n\n${description}${processed.trim()}`;
}
