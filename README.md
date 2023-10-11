
# Multi-Message Aggregation (MMA) Design

> **For latest GitBook, you can find it here:** https://multi-message-aggregation.gitbook.io/multi-message-aggregation/

![A World with MMA](https://i.imgur.com/MBnJdid.png)


## Introduction

**Multi-Message Aggregation (MMA) is an additive security module for cross-chain communication.** It utilizes multiple [Arbitrary Messaging Bridges](https://blog.li.fi/navigating-arbitrary-messaging-bridges-a-comparison-framework-8720f302e2aa) (AMB) to send messages from one EVM chain to another EVM chain.

Instead of relying on a single AMB, MMA allows the message sender to relay the message through multiple AMBs. This way, even if one AMB is exploited, no malicious actions can be executed on the destination chain.

## Features
### Core MMA architecture
- **Minimized feature sets**: barebone implementation, low level of complexity.
- **Configurable**: during deployment, individual project can configure their own parameters to fit their specific use case and risk tolerance.
### Adapter
- **Standardization**: Implements EIP-5164 for all APIs on the sending and receiving end.
- **Industry buyin**: currently more than **SIX** bridge providers have their adapters for MMA.

## Workflow for crosschain governance

Assume, we use 3 bridges to relay governance message from Ethereum mainnet to a destination chain. (This number can be changed during actual deployment or via a later governance vote.)


On the destination chain, if 2 of the 3 AMB agree with each other, we would consider the message.

The flow of the message and how it is transformed and relayed is detailed below:

1. Uniswap Ethereum governance structure, `src`, approves to execute a message `msg` on destination chain `dst`.
2. Uniswap governance sends `msg` to `MultiBridgeMessageSender`.
3. `MultiBridgeMessageSender` relays `msg` to different adapters `adapter`.
4. `adapter` encodes `msg` into the corresponding formatted message, `formatted_msg`, and sends it to the hardcoded AMB contracts `AMB`.
5. Each `AMB` independently carries `formatted_msg` to `dst`.
6. On the destination chain, another set of `adapters` decodes `formatted_msgs` into the original `msg`.
7. `msg` is collected inside the `MultiBridgeMessageReceiver` contract.
8. If 2 out of 3 `msg` is the same, the `msg` will be executed on `dst`.

![Illustration of ](https://files.gitbook.com/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FyWOfgotvwuIBhzylK0ud%2Fuploads%2Fco073eKSrR7xUmhObi7v%2FMMA_Highlevel.png?alt=media&token=bff8ec55-c04f-4ab9-b362-caae601154db)

## Local Development

**Step 1:** Clone the repository

```sh
$   git clone https://github.com/MultiMessageAggregation/multibridge
```

**note:** Please make sure [foundry](https://github.com/foundry-rs/foundry) is installed to proceed further.

**Step 2:** Install required forge submodules

```sh
$  forge install
```

**Step 3:** Compile

```sh
$  forge build
```

**Step 4:** Run Tests

To run the tests, you will need a local fork of Ethereum, Polygon, and BSC mainnet states. To accomplish this, you must specify RPC endpoints for each of these networks. You can obtain RPC endpoints to use for Ethereum and Polygon, from Alchemy, Infura, or other infrastructure providers. For BSC, you can choose from a list of public RPC endpoints available [here](https://docs.bscscan.com/misc-tools-and-utilities/public-rpc-nodes).

To set the RPC endpoints, make a copy of the `.env.sample` file and name it `.env`. The file contains a list of parameter names (e.g. `ETH_FORK_URL`) that correspond to each network. Set the respective values of each of these parameters to the RPC endpoints you wish to use.

Once you have set these values, you can run both the unit and integration tests using the following command:

```sh 

```sh
$  forge test
```

**note:** We use [pigeon](https://github.com/exp-table/pigeon/tree/docs) to simulate the cross-chain behavior on forked mainnets.

## Contribution guidelines
Thank you for your interest in contributing to MMA! We welcome all contributions to make our project better!

### Before you start
Before you start contributing to the project, please make sure you have read and understood the project's [Gitbook documentation](https://multi-message-aggregation.gitbook.io/multi-message-aggregation/). If you have any questions, drop Kydo a DM on [Twitter](https://twitter.com/0xkydo).

### How to contribute
#### Reporting bugs and issues
If you find any bugs or issues with the project, please create a GitHub issue and include as much detail as possible.

#### Code contribution
If you want to contribute code to the project, please follow these guidelines:

1. Fork the project repository and clone it to your local machine.
1. Create a new branch for your changes.
1. Make your changes and test them thoroughly.
1. Ensure that your changes are well-documented.
1. Create a pull request and explain your changes in detail.
1. Code review
1. All code changes will be reviewed by the project maintainers. The maintainers may ask for additional changes, and once the changes have been approved, they will be merged into the main branch.

#### Testing
All code changes must be thoroughly tested. Please ensure that your tests cover all new functionality and edge cases.

## Contracts
```
contracts
├── MultiBridgeMessageReceiver.sol
├── MultiBridgeMessageSender.sol
├── adapters
│   ├── BaseSenderAdapter.sol
│   ├── axelar
│   │   ├── AxelarReceiverAdapter.sol
│   │   ├── AxelarSenderAdapter.sol
│   │   ├── interfaces
│   │   │   ├── IAxelarExecutable.sol
│   │   │   ├── IAxelarGasService.sol
│   │   │   └── IAxelarGateway.sol
│   │   └── libraries
│   │       └── StringAddressConversion.sol
│   └── wormhole
│       ├── WormholeReceiverAdapter.sol
│       └── WormholeSenderAdapter.sol
├── controllers
│   ├── GAC.sol
│   └── GovernanceTimelock.sol
├── interfaces
│   ├── EIP5164
│   │   ├── ExecutorAware.sol
│   │   ├── MessageDispatcher.sol
│   │   ├── MessageExecutor.sol
│   │   └── SingleMessageDispatcher.sol
│   ├── IGAC.sol
│   ├── IGovernanceTimelock.sol
│   ├── IMessageReceiverAdapter.sol
│   ├── IMessageSenderAdapter.sol
│   └── IMultiBridgeMessageReceiver.sol
└── libraries
    ├── Error.sol
    ├── Message.sol
    ├── TypeCasts.sol
    └── Types.sol
```

## License
By contributing to the project, you agree that your contributions will be licensed under the project's [LICENSE](https://github.com/MultiMessageAggregation/multibridge/blob/main/LICENSE).