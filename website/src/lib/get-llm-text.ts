import { source } from "@/lib/source";

export async function getLLMText(page: (typeof source)["$inferPage"]) {
  const processed = await page.data.getText("processed");
  const description = page.data.description
    ? `${page.data.description.trim()}\n\n`
    : "";
  return `# ${page.data.title} (${page.url})\n\n${description}${processed.trim()}`;
}
