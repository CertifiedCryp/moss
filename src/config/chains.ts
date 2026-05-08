export const networks = ["mainnet", "testnet"] as const;

export type Network = (typeof networks)[number];

export const defaultNetwork = "mainnet" satisfies Network;
export const supportedNetworks = ["mainnet"] as const;

export type SupportedNetwork = (typeof supportedNetworks)[number];

export type ChainConfig = {
  network: Network;
  chainId: number;
  walletUrl: string;
  relayUrl: string;
};

export const chainConfigs: Record<Network, ChainConfig> = {
  mainnet: {
    network: "mainnet",
    chainId: 4326,
    walletUrl: "https://account.megaeth.com",
    relayUrl: "https://wallet-relay.megaeth.com",
  },
  testnet: {
    network: "testnet",
    chainId: 6343,
    walletUrl: "https://testnet-wallet.megaeth.com",
    relayUrl: "https://testnet-relay.megaeth.com",
  },
};

export function isNetwork(value: string): value is Network {
  return networks.includes(value as Network);
}

export function isSupportedNetwork(value: Network): value is SupportedNetwork {
  return supportedNetworks.includes(value as SupportedNetwork);
}

export function unsupportedNetworkMessage(network: Network): string {
  return `${network} is not supported yet. Omit --network to use ${defaultNetwork} until the wallet path is available.`;
}

export function getChainConfig(network: Network): ChainConfig {
  return chainConfigs[network];
}
