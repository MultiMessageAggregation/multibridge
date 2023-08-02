// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import {Test, Vm} from "forge-std/Test.sol";
import "forge-std/Console.sol";

/// @dev imports from Pigeon Helper (Facilitate State Transfer Mocks)
import {WomrholeHelper} from "pigeon/wormhole/WormholeHelper.sol";
import {AxelarHelper} from "pigeon/axelar/AxelarHelper.sol";

/// local imports
import {WormholeSenderAdapter} from "../src/adapters/wormhole/WormholeSenderAdapter.sol";
import {WormholeReceiverAdapter} from "../src/adapters/wormhole/WormholeReceiverAdapter.sol";

import {AxelarSenderAdapter} from "../src/adapters/axelar/AxelarSenderAdapter.sol";
import {AxelarReceiverAdapter} from "../src/adapters/axelar/AxelarReceiverAdapter.sol";

import {GAC} from "../src/controllers/GAC.sol";
import {MultiMessageSender} from "../src/MultiMessageSender.sol";
import {MultiMessageReceiver} from "../src/MultiMessageReceiver.sol";

/// @dev can inherit the setup in tests
abstract contract Setup is Test {
    /*///////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/
    /// @dev simulated caller
    address constant caller = address(10);

    /// @dev constants for axelar
    address constant ETH_GATEWAY = 0x4F4495243837681061C4743b74B3eEdf548D56A5;
    address constant BSC_GATEWAY = 0x304acf330bbE08d1e512eefaa92F6a57871fD895;
    address constant POLYGON_GATEWAY = 0x6f015F16De9fC8791b234eF68D486d2bF203FBA8;

    address constant ETH_GAS_SERVICE = 0x2d5d7d31F671F86C782533cc367F14109a082712;
    address constant BSC_GAS_SERVICE = 0x2d5d7d31F671F86C782533cc367F14109a082712;
    address constant POLYGON_GAS_SERVICE = 0x2d5d7d31F671F86C782533cc367F14109a082712;

    /// @dev constants for wormhole
    address constant ETH_RELAYER = 0x27428DD2d3DD32A4D7f7C497eAaa23130d894911;
    address constant BSC_RELAYER = 0x27428DD2d3DD32A4D7f7C497eAaa23130d894911;
    address constant POLYGON_RELAYER = 0x27428DD2d3DD32A4D7f7C497eAaa23130d894911;

    /*///////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    /// @notice configure all the chain ids we use for the tests (including src chain)
    /// id 0 represents src chain
    uint256[] public ALL_CHAINS = [1, 56, 137];

    /// @notice configure any new dst chains here
    uint256[] public DST_CHAINS = [56, 137];
    
    /// @notice configure all wormhole parameters in order of DST_CHAINS
    address[] public WORMHOLE_RELAYERS = [BSC_RELAYER, POLYGON_RELAYER];
    uint256[] public WORMHOLE_CHAIN_IDS = [4, 5];

    /// @notice configure all axelar parameters in order of DST_CHAINS
    address[] public AXELAR_GATEWAYS = [BSC_GATEWAY, POLYGON_GATEWAY];
    address[] public AXELAR_GAS_SERVICES = [BSC_GAS_SERVICE, POLYGON_GAS_SERVICE];
    string[] public AXELAR_CHAIN_IDS = ["binance", "Polygon"];

    /// @dev maps the local chain id to a fork id
    mapping(uint256 => uint256) public fork;

    /// @dev maps the contract chain and name to an address
    mapping(uint256 => mapping(bytes => address)) public contractAddress;

    /*///////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/
    function setUp() public virtual {
        /// @dev create forks of src chain & 2 diff dst chains
        /// @notice chain id: 1 (always source chain)
        /// @notice chain id: 137
        /// @notice chain id: 56
        fork[1] = vm.createSelectFork(vm.envString("ETH_FORK_URL"));
        vm.deal(caller, 100 ether);

        fork[56] = vm.createSelectFork(vm.envString("BSC_FORK_URL"));
        vm.deal(caller, 100 ether);

        fork[137] = vm.createSelectFork(vm.envString("POLYGON_FORK_URL"));
        vm.deal(caller, 100 ether);

        /// @dev deploys controller contract to all chains
        _deployGac();

        /// @dev deploys amb adapters
        /// note: now added only wormhole & axelar
        _deployWormholeAdapters();
        _deployAxelarAdapters();

        /// @dev deploy amb helpers
        /// note: deploys only wormhole & axelar helpers
        _deployHelpers();

        /// @dev deploys mma sender and receiver adapters
        _deployCoreContracts();

        /// @dev setup core contracts
        _setupCoreContracts();
    }

    /*///////////////////////////////////////////////////////////////
                            INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/
    /// @dev deploys controller to all chains
    function _deployGac() internal {
        for(uint256 i; i < ALL_CHAINS.length; ) {
            uint256 chainId = ALL_CHAINS[i];
            vm.selectFork(fork[chainId]);

            contractAddress[chainId][bytes("GAC")] = address(new GAC());

            unchecked {
                ++i;
            }
        }
    }

    /// @dev deploys the wormhole adapters to all configured chains
    function _deployWormholeAdapters() internal {
        /// @notice deploy source adapter to SRC_CHAIN (ETH)
        vm.selectFork(fork[1]);

        contractAddress[1][bytes("WORMHOLE_SENDER_ADAPTER")] =
            address(new WormholeSenderAdapter(ETH_RELAYER, contractAddress[1][bytes("GAC")]));

        uint256 len = DST_CHAINS.length;

        /// @notice deploy receiver adapters to all DST_CHAINS
        address[] memory _receiverAdapters = new address[](len);

        for (uint256 i; i < len;) {
            uint256 chainId = DST_CHAINS[i];
            vm.selectFork(fork[chainId]);

            address receiverAdapter =
                address(new WormholeReceiverAdapter(WORMHOLE_RELAYERS[i], contractAddress[chainId][bytes("GAC")]));
            contractAddress[chainId][bytes("WORMHOLE_RECEIVER_ADAPTER")] = receiverAdapter;
            _receiverAdapters[i] = receiverAdapter;
           
            unchecked {
                ++i;
            }
        }

        /// @dev sets some configs to sender adapter (ETH_CHAIN_ADAPTER)
        vm.selectFork(fork[1]);

        WormholeSenderAdapter(contractAddress[1][bytes("WORMHOLE_SENDER_ADAPTER")]).updateReceiverAdapter(
            DST_CHAINS, _receiverAdapters
        );

        WormholeSenderAdapter(contractAddress[1][bytes("WORMHOLE_SENDER_ADAPTER")]).setChainchainIdMap(
            DST_CHAINS, WORMHOLE_CHAIN_IDS
        );
    }

    /// @dev deploys the axelar adapters to all configured chains
    function _deployAxelarAdapters() internal {
        /// @notice deploy source adapter to Ethereum
        vm.selectFork(fork[1]);
        contractAddress[1][bytes("AXELAR_SENDER_ADAPTER")] = address(new AxelarSenderAdapter(ETH_GAS_SERVICE, ETH_GATEWAY, contractAddress[1][bytes("GAC")]));

                uint256 len = DST_CHAINS.length;

        /// @notice deploy receiver adapters to all DST_CHAINS
        address[] memory _receiverAdapters = new address[](len);

        for (uint256 i; i < len;) {
            uint256 chainId = DST_CHAINS[i];
            vm.selectFork(fork[chainId]);

            address receiverAdapter =
                address(new AxelarReceiverAdapter(AXELAR_GATEWAYS[i], contractAddress[chainId][bytes("GAC")]));
            contractAddress[chainId][bytes("AXELAR_RECEIVER_ADAPTER")] = receiverAdapter;
            _receiverAdapters[i] = receiverAdapter;
           
            unchecked {
                ++i;
            }
        }

        vm.selectFork(fork[1]);

        AxelarSenderAdapter(contractAddress[1][bytes("AXELAR_SENDER_ADAPTER")]).updateReceiverAdapter(
            DST_CHAINS, _receiverAdapters
        );
            
        AxelarSenderAdapter(contractAddress[1][bytes("AXELAR_SENDER_ADAPTER")]).setChainchainIdMap(
            DST_CHAINS, AXELAR_CHAIN_IDS
        );
    }

    /// @dev deploys the amb helpers to all configured chains
    function _deployHelpers() internal {
        /// @notice deploy amb helpers to Ethereum
        vm.selectFork(fork[1]);
        contractAddress[1][bytes("WORMHOLE_HELPER")] = address(new WormholeHelper());
        contractAddress[1][bytes("AXELAR_HELPER")] = address(new AxelarHelper());

        vm.allowCheatcodes(contractAddress[1][bytes("WORMHOLE_HELPER")]);
        vm.allowCheatcodes(contractAddress[1][bytes("AXELAR_HELPER")]);

        /// @notice deploy amb helpers to BSC, POLYGON & ARB
        for (uint256 i; i < DST_CHAINS.length;) {
            uint256 chainId = DST_CHAINS[i];

            vm.selectFork(fork[chainId]);
            contractAddress[chainId][bytes("WORMHOLE_HELPER")] = address(new WormholeHelper());
            contractAddress[chainId][bytes("AXELAR_HELPER")] = address(new AxelarHelper());

            vm.allowCheatcodes(contractAddress[chainId][bytes("WORMHOLE_HELPER")]);
            vm.allowCheatcodes(contractAddress[chainId][bytes("AXELAR_HELPER")]);

            unchecked {
                ++i;
            }
        }
    }

    /// @dev deploys the mma sender and receiver adapters to all configured chains
    function _deployCoreContracts() internal {
        /// @notice deploy mma sender to ETHEREUM
        vm.selectFork(fork[1]);
        contractAddress[1][bytes("MMA_SENDER")] = address(new MultiMessageSender(caller, contractAddress[1][bytes("GAC")]));

        /// @notice deploy amb helpers to BSC & POLYGON
        for (uint256 i; i < DST_CHAINS.length; i++) {
            uint256 chainId = DST_CHAINS[i];

            vm.selectFork(fork[chainId]);
            contractAddress[chainId][bytes("MMA_RECEIVER")] = address(new MultiMessageReceiver());
        }
    }

    /// @dev setup core contracts
    function _setupCoreContracts() internal {
        /// setup mma sender adapters
        vm.selectFork(fork[1]);
        vm.startPrank(caller);

        address[] memory _senderAdapters = new address[](2);
        _senderAdapters[0] = contractAddress[1][bytes("WORMHOLE_SENDER_ADAPTER")];
        _senderAdapters[1] = contractAddress[1][bytes("AXELAR_SENDER_ADAPTER")];

        MultiMessageSender(contractAddress[1][bytes("MMA_SENDER")]).addSenderAdapters(56, _senderAdapters);
        MultiMessageSender(contractAddress[1][bytes("MMA_SENDER")]).addSenderAdapters(137, _senderAdapters);

        /// setup mma receiver adapters
        for (uint256 i; i < DST_CHAINS.length;) {
            uint256 chainId = DST_CHAINS[i];
            /// setup receiver adapters
            vm.selectFork(fork[chainId]);

            address[] memory _recieverAdapters = new address[](2);
            _recieverAdapters[0] = contractAddress[chainId][bytes("WORMHOLE_RECEIVER_ADAPTER")];
            _recieverAdapters[1] = contractAddress[chainId][bytes("AXELAR_RECEIVER_ADAPTER")];

            MultiMessageReceiver(contractAddress[DST_CHAINS[i]][bytes("MMA_RECEIVER")]).initialize(
                1, contractAddress[1][bytes("MMA_SENDER")], _recieverAdapters, 2
            );

            unchecked{
                ++i;
            }
        }
    }

    /// @dev helps payload delivery using logs
    function _simulatePayloadDelivery(uint256 _srcChainId, uint256 _dstChainId, Vm.Log[] memory _logs) internal {}
}
