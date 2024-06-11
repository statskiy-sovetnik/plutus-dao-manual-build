import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.9",
        settings: {
          optimizer: {
          enabled: true,
          runs: 1000
        },
        outputSelection: {
          "*": {
            "*": [
              "evm.bytecode",
              "evm.deployedBytecode",
              "devdoc",
              "userdoc",
              "metadata",
              "abi"
            ]
          }
        },
        "libraries": {}
        }
      },
      {
        version: "0.8.16",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1000
          },
          outputSelection: {
            "*": {
              "*": [
                "evm.bytecode",
                "evm.deployedBytecode",
                "devdoc",
                "userdoc",
                "metadata",
                "abi"
              ]
            }
          },
          "libraries": {}
        }
      },
      {
        version: "0.8.17",
        settings: {
          optimizer: {
            enabled: true,
            runs: 9999
          },
          outputSelection: {
            "*": {
              "*": [
                "evm.bytecode",
                "evm.deployedBytecode",
                "devdoc",
                "userdoc",
                "metadata",
                "abi"
              ]
            }
          },
          "libraries": {}
        }
      },
      {
        version: "0.8.20",
        settings: {
          optimizer: {
            enabled: true,
            runs: 99999
          },
          outputSelection: {
            "*": {
              "*": [
                "evm.bytecode",
                "evm.deployedBytecode",
                "devdoc",
                "userdoc",
                "metadata",
                "abi"
              ]
            }
          },
          "libraries": {}
        }
      }
    ]
  },
};

export default config;
