# Multi-bridge Message Aggregation (MMA)

> Additional Technical documentation can be found on [Gitbook here.](https://multi-message-aggregation.gitbook.io/multi-message-aggregation/)

## Introduction
Multi-bridge Message Aggregation (MMA) is an additive security module for cross-chain communication across different EVM chains. It uses multiple [Arbitrary Messaging Bridges](https://blog.li.fi/navigating-arbitrary-messaging-bridges-a-comparison-framework-8720f302e2aa) to send messages, rather than relying on a single AMB.
The protocol can be configured to withstand the failure of a subset of AMBs. This significantly improves the security and resilience of cross-chain communication. 

Specifically, if a subset of AMBs, below the configured failure threshold, is compromised or fails, invalid messages will not be executed on the target chain, and the protocol will continue to operate without disruptions. This improves the [safety and liveness properties](https://crosschainriskframework.github.io/framework/20categories/20architecture/architecture/#messaging-protocol) of the protocol. The protocol offers the following benefits:

1. **Increased Safety Guarantees** by verifying cross-chain messages across multiple bridges.
2. **Improve Liveness and Censorship Resistance** guarantees by providing redundancy through multiple bridges.
3. **Increase Flexibility** by allowing dApps a more seamless integration with new cross-chain protocols and a less disruptive phasing-out of defunct protocols over time.

## Design
The design of MMA is guided by the following goals:
- **Simplicity**: MMA provides a thin layer of abstraction over existing cross-chain protocols, adding minimal complexity and significantly reducing implementation risk.
- **Extensibility**: The design of MMA allows for the seamless integration of new AMBs, and accommodates changes to the design and implementation of AMBs without requiring modifications to the core protocol.
- **Flexibility**: The protocol offers flexibility, enabling dApps to choose the set of bridges and validation parameters to use for different chains and for specific messages.

The protocol comprises core contracts and adapters. The core contracts implement the protocol's central logic, which includes sending and receiving messages across chains using multiple bridges for enhanced security and resilience. Adapters facilitate interaction between the core components and specific AMBs. They follow a [standard interface, EIP-5164](https://eips.ethereum.org/EIPS/eip-5164), for easy integration with the core protocol. The core contracts are designed for simplicity, while the adapters are designed for flexibility. This design approach allows for easy integration of new AMBs. It also accommodates changes in the design and implementation details of AMBs without necessitating modifications to the core protocol.

## Features
**The current version of MMA is specifically tailored to address the cross-chain governance use case of the Uniswap protocol.** 
As a result, the capabilities are intentionally in the following two ways:
1. Uni-directional communication: Only a single sender chain is supported, allowing communication solely from the designated sender chain to other recipient chains.
2. Only EVM Chains are supported.
3. Timelock on destination chain. Messages are executed on the destination chain only after a specified timelock period has elapsed.

The core features of the protocol are:
1. Sending and receive messages across EVM chains using multiple bridges.
1. Adding and removing bridges.
1. Configuring message validation parameters.
1. Administering adapter-specific parameters.

An [independent fork](https://github.com/lifinance/MMAxERC20) of this repository, created by [Li.Fi](https://li.fi/), is expanding the current capabilities of MMA to support a broader range of cross-chain interaction patterns, additional use-cases, and non-EVM chains.

## Life-cycle of a Message
The diagram below illustrates a typical scenario for the MMA protocol in the context of Uniswap's cross-chain governance workflow. 

The Uniswap DAO wants to send a governance action message to a remote chain for execution. An example of such a message could be changing fee parameters on the Uniswap deployment on the destination chain. The life cycle of a cross-chain governance transaction proceeds as follows, once it has passed the standard process of on-chain voting and time-lock queue on the governance chain (Ethereum):
1. The governance message is sent from the Uniswap V2 Timelock contract to the [`MultiBridgeMessageSender`](src/MultiBridgeMessageSender.sol) contract
1. The [`MultiBridgeMessageSender`](src/MultiBridgeMessageSender.sol) sends the message to all available AMB sender adapters (a caller could choose to exclude one or more AMBs in this process)
1. The AMB sender adapters send the message to AMB-specific components to relay the message to the intended destination. The adapters implement a common interface, [`IMessageSenderAdapter`](src/interfaces/adapters/IMessageSenderAdapter.sol), which allows the [`MultiBridgeMessageSender`](src/MultiBridgeMessageSender.sol) to interact with them in a uniform manner.
1. AMB receiver adapters receive the message from off-chain components (e.g. bridge validators or relayers) and forward them to the [`MultiBridgeMessageReceiver`](src/MultiBridgeMessageReceiver.sol) contract.
1. Once enough AMBs have relayed a specific message (i.e. a quorum has been achieved), anyone can call `scheduleMessageExecution()` on the [`MultiBridgeMessageReceiver`](src/MultiBridgeMessageReceiver.sol) contract which then queues the message for execution on the governance timelock.
1. Once a configured delay period has elapsed on the governance timelock, anyone can execute a time-locked message, which performs the intended execution on the target contract on the destination chain.

![Illustration of ](https://314948482-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FyWOfgotvwuIBhzylK0ud%2Fuploads%2FYrd16Z8BdyejNqvCF5eO%2FScreenshot%202023-09-25%20at%207.57.32%20pm.png?alt=media&token=eb3ef911-1f44-4657-b234-8acbd55ddf1c)

## Contracts
```
src
├── MultiBridgeMessageReceiver.sol
├── MultiBridgeMessageSender.sol
├── adapters
│   ├── BaseReceiverAdapter.sol
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
│   ├── GovernanceTimelock.sol
│   ├── MessageReceiverGAC.sol
│   └── MessageSenderGAC.sol
├── interfaces
│   ├── EIP5164
│   │   ├── MessageDispatcher.sol
│   │   ├── MessageExecutor.sol
│   │   └── SingleMessageDispatcher.sol
│   ├── IMultiBridgeMessageReceiver.sol
│   ├── adapters
│   │   ├── IMessageReceiverAdapter.sol
│   │   └── IMessageSenderAdapter.sol
│   └── controllers
│       ├── IGAC.sol
│       └── IGovernanceTimelock.sol
└── libraries
    ├── EIP5164
    │   └── ExecutorAware.sol
    ├── Error.sol
    ├── Message.sol
    ├── TypeCasts.sol
    └── Types.sol
```


## Development
Refer to the [Development Guide](./DEVELOP.md) for instructions on how to set up a development environment and run tests.

## Contributing
Thank you for your interest in contributing to MMA! Please refer to our [Contributing Guidelines](./CONTRIBUTING.md) for more information. By contributing to the project, you agree that your contributions will be licensed under the project's [LICENSE](./LICENSE).