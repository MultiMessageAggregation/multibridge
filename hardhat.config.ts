import '@nomiclabs/hardhat-ethers';
import '@nomiclabs/hardhat-etherscan';
import '@nomiclabs/hardhat-waffle';
import '@typechain/hardhat';
import 'hardhat-contract-sizer';
import 'hardhat-deploy';
import 'hardhat-gas-reporter';

import * as dotenv from 'dotenv';
import { HardhatUserConfig } from 'hardhat/types';

dotenv.config();

const DEFAULT_ENDPOINT = 'http://localhost:8545';
const DEFAULT_PRIVATE_KEY =
  process.env.DEFAULT_PRIVATE_KEY || 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';

const config: HardhatUserConfig = {
  defaultNetwork: 'hardhat',
  networks: {
    // Testnets
    hardhat: {},
    localhost: { timeout: 600000 },
  },
  namedAccounts: {
    deployer: {
      default: 0
    }
  },
  solidity: {
    version: '0.8.17',
    settings: {
      optimizer: {
        enabled: true,
        runs: 800
      }
    }
  },
  typechain: {
    outDir: 'typechain',
    target: 'ethers-v5'
  }
};

export default config;
