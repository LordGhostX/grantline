import { createConfig, cookieStorage, createStorage } from "wagmi";
import { http, fallback } from "viem";
import { injected } from "wagmi/connectors";

export const xLayerTestnet = {
  id: 1952,
  name: "X Layer Testnet",
  nativeCurrency: { name: "OKB", symbol: "OKB", decimals: 18 },
  rpcUrls: {
    default: { http: ["https://testrpc.xlayer.tech/terigon"] },
  },
  blockExplorers: {
    default: {
      name: "OKX Explorer",
      url: "https://web3.okx.com/explorer/x-layer-testnet",
    },
  },
} as const;

function getTransports() {
  const rpcs = process.env.NEXT_PUBLIC_X_LAYER_RPCS?.split(",")
    .map((url) => url.trim())
    .filter(Boolean);

  if (!rpcs || rpcs.length === 0) return { [xLayerTestnet.id]: http() };
  if (rpcs.length === 1) return { [xLayerTestnet.id]: http(rpcs[0]) };
  return {
    [xLayerTestnet.id]: fallback(rpcs.map((url) => http(url))),
  };
}

export function getConfig() {
  return createConfig({
    chains: [xLayerTestnet],
    connectors: [injected()],
    ssr: true,
    storage: createStorage({ storage: cookieStorage }),
    transports: getTransports(),
  });
}
