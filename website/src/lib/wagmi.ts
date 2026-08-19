import { createConfig, http, cookieStorage, createStorage } from "wagmi";
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

export function getConfig() {
  return createConfig({
    chains: [xLayerTestnet],
    connectors: [injected()],
    ssr: true,
    storage: createStorage({ storage: cookieStorage }),
    transports: {
      [xLayerTestnet.id]: http(),
    },
  });
}
