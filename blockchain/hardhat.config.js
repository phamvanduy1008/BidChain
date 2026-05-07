require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      viaIR: true, // 🔥 QUAN TRỌNG nhất
    },
  },
  networks: {
    ganache: {
      url: process.env.GANACHE_RPC || "http://127.0.0.1:7545",
      accounts: [process.env.DEPLOYER_PRIVATE_KEY],
    },
  },
};