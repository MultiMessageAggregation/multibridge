// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import "forge-std/Test.sol";

/// @dev imports from Pigeon Helper (Facilitate State Transfer Mocks)
import {CelerHelper} from "pigeon/celer/CelerHelper.sol";
import {HyperlaneHelper} from "pigeon/hyperlane/HyperlaneHelper.sol";

/// local imports
import {HyperlaneSenderAdapter} from "../src/adapters/hyperlane/HyperlaneSenderAdapter.sol";
import {HyperlaneReceiverAdapter} from "../src/adapters/hyperlane/HyperlaneReceiverAdapter.sol";

import {CelerSenderAdapter} from "../src/adapters/celer/CelerSenderAdapter.sol";
import {CelerReceiverAdapter} from "../src/adapters/celer/CelerReceiverAdapter.sol";

import {MultiMessageSender} from "../src/MultiMessageSender.sol";
import {MultiMessageReceiver} from "../src/MultiMessageReceiver.sol";

/// @dev can inherit the setup in tests
abstract contract Setup is Test {
    /*///////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/
    /// @dev simulated caller
    address constant caller = address(10);

    /// @dev constants for hyperlane
    address constant HYPERLANE_MAILBOX = 0x35231d4c2D8B8ADcB5617A638A0c4548684c7C70;
    address constant HYPERLANE_IGP = 0xdE86327fBFD04C4eA11dC0F270DA6083534c2582;

    /// @dev constants for celer
    address constant ETH_CELER_MSG_BUS = 0x4066D196A423b2b3B8B054f4F40efB47a74E200C;
    address constant BSC_CELER_MSG_BUS = 0x95714818fdd7a5454F73Da9c777B3ee6EbAEEa6B;
    address constant POLYGON_CELER_MSG_BUS = 0xaFDb9C40C7144022811F034EE07Ce2E110093fe6;
    address constant ARB_CELER_MSG_BUS = 0x3Ad9d0648CDAA2426331e894e980D0a5Ed16257f;

    /*///////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    /// @notice configure any new dst chains here
    uint256[] public DST_CHAINS = [56, 137, 42161];

    /// @dev maps the local chain id to a fork id
    mapping(uint256 => uint256) public fork;

    /// @dev maps the contract chain and name to an address
    mapping(uint256 => mapping(bytes => address)) public contractAddress;

    /*///////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/
    function setUp() public virtual {
        /// @dev create forks of src chain & 3 diff dst chains
        /// @notice chain id: 1 (always source chain)
        /// @notice chain id: 137
        /// @notice chain id: 56
        /// @notice chain id: 42161
        fork[1] = vm.createSelectFork(vm.envString("ETH_FORK_URL"));
        vm.deal(caller, 100 ether);

        fork[56] = vm.createSelectFork(vm.envString("BSC_FORK_URL"));
        vm.deal(caller, 100 ether);

        fork[137] = vm.createSelectFork(vm.envString("POLYGON_FORK_URL"));
        vm.deal(caller, 100 ether);

        fork[42161] = vm.createSelectFork(vm.envString("ARB_FORK_URL"));
        vm.deal(caller, 100 ether);

        /// @dev deploys amb adapters
        /// note: now added only hyperlane & celer
        _deployHyperlaneAdapters();
        _deployCelerAdapters();

        /// @dev deploy amb helpers
        /// note: deploys only hyperlane & celer helpers
        _deployHelpers();

        /// @dev deploys mma sender and receiver adapters
        _deployCoreContracts();

        /// @dev setup core contracts
        _setupCoreContracts();
    }

    /*///////////////////////////////////////////////////////////////
                            INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/
    /// @dev deployes the hyperlane adapters to all configured chains
    function _deployHyperlaneAdapters() internal {
        /// @notice deploy receiver adapters to BSC, POLYGON & ARB
        for (uint256 i; i < DST_CHAINS.length; i++) {
            vm.selectFork(fork[DST_CHAINS[i]]);

            contractAddress[DST_CHAINS[i]][bytes("HYPERLANE_RECEIVER_ADAPTER")] =
                address(new HyperlaneReceiverAdapter(HYPERLANE_MAILBOX));
        }

        /// @notice deploy source adapter to Ethereum
        vm.selectFork(fork[1]);

        contractAddress[1][bytes("HYPERLANE_SENDER_ADAPTER")] =
            address(new HyperlaneSenderAdapter(HYPERLANE_MAILBOX, HYPERLANE_IGP));

        address[] memory _receiverAdapters = new address[](3);
        _receiverAdapters[0] = contractAddress[56][bytes("HYPERLANE_RECEIVER_ADAPTER")];
        _receiverAdapters[1] = contractAddress[137][bytes("HYPERLANE_RECEIVER_ADAPTER")];
        _receiverAdapters[2] = contractAddress[42161][bytes("HYPERLANE_RECEIVER_ADAPTER")];

        HyperlaneSenderAdapter(contractAddress[1][bytes("HYPERLANE_SENDER_ADAPTER")]).updateReceiverAdapter(DST_CHAINS, _receiverAdapters);
        
        uint32[] memory _receiverDomains = new uint32[](3);
        _receiverDomains[0] = uint32(56);
        _receiverDomains[1] = uint32(137);
        _receiverDomains[2] = uint32(42161);

        HyperlaneSenderAdapter(contractAddress[1][bytes("HYPERLANE_SENDER_ADAPTER")]).updateDestinationDomainIds(DST_CHAINS, _receiverDomains);
    }   

    /// @dev deploys the celer adapters to all configured chains
    function _deployCelerAdapters() internal {
        /// @notice deploy receiver adapters to BSC, POLYGON & ARB
        vm.selectFork(fork[56]);
        contractAddress[56][bytes("CELER_RECEIVER_ADAPTER")] = address(new CelerReceiverAdapter(BSC_CELER_MSG_BUS));

        vm.selectFork(fork[137]);
        contractAddress[137][bytes("CELER_RECEIVER_ADAPTER")] = address(new CelerReceiverAdapter(POLYGON_CELER_MSG_BUS));

        vm.selectFork(fork[42161]);
        contractAddress[42161][bytes("CELER_RECEIVER_ADAPTER")] = address(new CelerReceiverAdapter(ARB_CELER_MSG_BUS));

        /// @notice deploy source adapter to Ethereum
        vm.selectFork(fork[1]);
        contractAddress[1][bytes("CELER_SENDER_ADAPTER")] = address(new CelerSenderAdapter(ETH_CELER_MSG_BUS));
        
        address[] memory _receiverAdapters = new address[](3);
        _receiverAdapters[0] = contractAddress[137][bytes("CELER_RECEIVER_ADAPTER")];
        _receiverAdapters[1] = contractAddress[56][bytes("CELER_RECEIVER_ADAPTER")];
        _receiverAdapters[2] = contractAddress[42161][bytes("CELER_RECEIVER_ADAPTER")];

        CelerSenderAdapter(contractAddress[1][bytes("CELER_SENDER_ADAPTER")]).updateReceiverAdapter(DST_CHAINS, _receiverAdapters);
    }

    /// @dev deploys the amb helpers to all configured chains
    function _deployHelpers() internal {
        /// @notice deploy amb helpers to Ethereum
        vm.selectFork(fork[1]);
        contractAddress[1][bytes("CELER_HELPER")] = address(new CelerHelper());
        contractAddress[1][bytes("HYPERLANE_HELPER")] = address(new HyperlaneHelper());

        /// @notice deploy amb helpers to BSC, POLYGON & ARB
        for (uint256 i; i < DST_CHAINS.length; i++) {
            vm.selectFork(fork[DST_CHAINS[i]]);
            contractAddress[DST_CHAINS[i]][bytes("CELER_HELPER")] = address(new CelerHelper());
            contractAddress[DST_CHAINS[i]][bytes("HYPERLANE_HELPER")] = address(new HyperlaneHelper());
        }
    }

    /// @dev deploys the mma sender and receiver adapters to all configured chains
    function _deployCoreContracts() internal {
        /// @notice deploy mma sender to Ethereum
        vm.selectFork(fork[1]);
        contractAddress[1][bytes("MMA_SENDER")] = address(new MultiMessageSender(caller));

        /// @notice deploy amb helpers to BSC, POLYGON & ARB
        for (uint256 i; i < DST_CHAINS.length; i++) {
            vm.selectFork(fork[DST_CHAINS[i]]);
            contractAddress[DST_CHAINS[i]][bytes("MMA_RECEIVER")] = address(new MultiMessageReceiver());
        }
    }

    /// @dev setup core contracts
    function _setupCoreContracts() internal {
        /// setup mma sender adapters
        vm.selectFork(fork[1]);
        vm.startPrank(caller);

        address[] memory _senderAdapters = new address[](2);
        _senderAdapters[0] = contractAddress[1][bytes("CELER_SENDER_ADAPTER")];
        _senderAdapters[1] = contractAddress[1][bytes("HYPERLANE_SENDER_ADAPTER")];

        MultiMessageSender(contractAddress[1][bytes("MMA_SENDER")]).addSenderAdapters(56, _senderAdapters);
        MultiMessageSender(contractAddress[1][bytes("MMA_SENDER")]).addSenderAdapters(137, _senderAdapters);
        MultiMessageSender(contractAddress[1][bytes("MMA_SENDER")]).addSenderAdapters(42161, _senderAdapters);

        /// setup mma receiver adapters
        for (uint256 i; i < DST_CHAINS.length; i++) {
            /// setup receiver adapters
            vm.selectFork(fork[DST_CHAINS[i]]);
            
            address[] memory _recieverAdapters = new address[](2);
            _recieverAdapters[0] = contractAddress[DST_CHAINS[i]][bytes("CELER_RECEIVER_ADAPTER")];
            _recieverAdapters[1] = contractAddress[DST_CHAINS[i]][bytes("HYPERLANE_RECEIVER_ADAPTER")];

            MultiMessageReceiver(contractAddress[DST_CHAINS[i]][bytes("MMA_RECEIVER")]).initialize(
                1, contractAddress[1][bytes("MMA_SENDER")], _recieverAdapters, 2
            );
        }
    }
}
