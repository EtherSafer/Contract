const HDWalletProvider = require("truffle-hdwallet-provider");

let secrets
try {
  /**
   * NOTE: Sample secrets file
   * ./secrets.js
   * module.exports = {
   *   testWalletMnemonic: 'apple banana cat dog ...',
   * }
   */
  secrets = require('./secrets')
} catch (error) {
  secrets = { testWalletMnemonic: '' }
}

const { testWalletMnemonic } = secrets

// See <http://truffleframework.com/docs/advanced/configuration>
module.exports = {
  networks: {
    /** dev ganach network */
    development: {
      host: "localhost",
      port: 8545,
      network_id: "*"
    },
    /** online test ganach network */
    test: {
      provider: function () {
        return new HDWalletProvider(testWalletMnemonic, `https://beta.ethersafer.io/rpc`, 0, 25)
      },
      network_id: "*"
    },
    /** live contract is being deployed via https://remix.ethereum.org/ now */
    // live: {
    //   provider: function () {
    //     return new HDWalletProvider(walletMnemonic, `https://mainnet.infura.io/v3/${infuraKey}`)
    //   },
    //   network_id: '1',
    //   gas: 6000000,
    //   gasPrice: 2000000000,
    // }
  },
  solc: {
    optimizer: {
      enabled: true,
      runs: 200
    }
  },
};
