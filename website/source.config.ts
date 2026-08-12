import { defineDocs } from "fumadocs-mdx/config";

export const docs = defineDocs({
  docs: {
    lastModified: true,
    postprocess: {
      includeProcessedMarkdown: true,
    },
  },
});
