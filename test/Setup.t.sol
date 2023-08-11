// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import {Test, Vm} from "forge-std/Test.sol";
import "forge-std/Console.sol";

/// @dev imports from Pigeon Helper (Facilitate State Transfer Mocks)
import {WormholeHelper} from "pigeon/wormhole/WormholeHelper.sol";
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
    bytes32 _salt = keccak256(abi.encode("UNISWAP_MMA"));

    /*///////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/
    /// @dev simulated caller
    address constant caller = address(10);
    address constant owner = address(420);

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
    uint16[] public WORMHOLE_CHAIN_IDS = [4, 5];

    /// @notice configure all axelar parameters in order of DST_CHAINS
    address[] public AXELAR_GATEWAYS = [BSC_GATEWAY, POLYGON_GATEWAY];
    address[] public AXELAR_GAS_SERVICES = [BSC_GAS_SERVICE, POLYGON_GAS_SERVICE];
    string[] public AXELAR_CHAIN_IDS = ["binance", "polygon"];

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

        /// @dev setup adapter contracts
        _setupAdapters();
    }

    /*///////////////////////////////////////////////////////////////
                            INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/
    /// @dev deploys controller to all chains
    function _deployGac() internal {
        vm.startPrank(owner);

        for (uint256 i; i < ALL_CHAINS.length;) {
            uint256 chainId = ALL_CHAINS[i];
            vm.selectFork(fork[chainId]);

            GAC gac = new GAC{salt: _salt}();
            gac.setMsgExpiryTime(2 days);
            gac.setMultiMessageCaller(caller);
            contractAddress[chainId][bytes("GAC")] = address(gac);


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
            address(new WormholeSenderAdapter{salt: _salt}(ETH_RELAYER, contractAddress[1][bytes("GAC")]));

        uint256 len = DST_CHAINS.length;

        /// @notice deploy receiver adapters to all DST_CHAINS
        address[] memory _receiverAdapters = new address[](len);

        for (uint256 i; i < len;) {
            uint256 chainId = DST_CHAINS[i];
            vm.selectFork(fork[chainId]);

            address receiverAdapter = address(
                new WormholeReceiverAdapter{salt: _salt}(WORMHOLE_RELAYERS[i], contractAddress[chainId][bytes("GAC")])
            );
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

        WormholeSenderAdapter(contractAddress[1][bytes("WORMHOLE_SENDER_ADAPTER")]).setChainIdMap(
            DST_CHAINS, WORMHOLE_CHAIN_IDS
        );
    }

    /// @dev deploys the axelar adapters to all configured chains
    function _deployAxelarAdapters() internal {
        /// @notice deploy source adapter to Ethereum
        vm.selectFork(fork[1]);
        contractAddress[1][bytes("AXELAR_SENDER_ADAPTER")] = address(
            new AxelarSenderAdapter{salt: _salt}(ETH_GAS_SERVICE, ETH_GATEWAY, contractAddress[1][bytes("GAC")])
        );

        uint256 len = DST_CHAINS.length;

        /// @notice deploy receiver adapters to all DST_CHAINS
        address[] memory _receiverAdapters = new address[](len);

        for (uint256 i; i < len;) {
            uint256 chainId = DST_CHAINS[i];
            vm.selectFork(fork[chainId]);

            address receiverAdapter = address(
                new AxelarReceiverAdapter{salt: _salt}(AXELAR_GATEWAYS[i], contractAddress[chainId][bytes("GAC")])
            );
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

        AxelarSenderAdapter(contractAddress[1][bytes("AXELAR_SENDER_ADAPTER")]).setChainIdMap(
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
            contractAddress[chainId][bytes("WORMHOLE_HELPER")] = address(new WormholeHelper{salt: _salt}());
            contractAddress[chainId][bytes("AXELAR_HELPER")] = address(new AxelarHelper{salt: _salt}());

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
        contractAddress[1][bytes("MMA_SENDER")] =
            address(new MultiMessageSender{salt: _salt}(contractAddress[1][bytes("GAC")]));

        /// @notice deploy amb helpers to BSC & POLYGON
        for (uint256 i; i < DST_CHAINS.length; i++) {
            uint256 chainId = DST_CHAINS[i];

            vm.selectFork(fork[chainId]);
            contractAddress[chainId][bytes("MMA_RECEIVER")] = address(new MultiMessageReceiver{salt: _salt}());
        }
    }

    /// @dev setup core contracts
    function _setupCoreContracts() internal {
        /// setup mma sender adapters
        vm.selectFork(fork[1]);
        vm.startPrank(owner);

        address[] memory _senderAdapters = new address[](2);
        _senderAdapters[0] = contractAddress[1][bytes("WORMHOLE_SENDER_ADAPTER")];
        _senderAdapters[1] = contractAddress[1][bytes("AXELAR_SENDER_ADAPTER")];

        MultiMessageSender(contractAddress[1][bytes("MMA_SENDER")]).addSenderAdapters(_senderAdapters);

        /// setup mma receiver adapters
        for (uint256 i; i < DST_CHAINS.length;) {
            uint256 chainId = DST_CHAINS[i];
            /// setup receiver adapters
            vm.selectFork(fork[chainId]);

            address[] memory _recieverAdapters = new address[](2);
            _recieverAdapters[0] = contractAddress[chainId][bytes("WORMHOLE_RECEIVER_ADAPTER")];
            _recieverAdapters[1] = contractAddress[chainId][bytes("AXELAR_RECEIVER_ADAPTER")];

            MultiMessageReceiver(contractAddress[DST_CHAINS[i]][bytes("MMA_RECEIVER")]).initialize(_recieverAdapters, 2);

            unchecked {
                ++i;
            }
        }

        /// setup the core contracts to GAC
        for (uint256 i; i < ALL_CHAINS.length;) {
            uint256 chainId = ALL_CHAINS[i];

            vm.selectFork(fork[chainId]);
            vm.startPrank(owner);

            /// @dev mma sender is only available on chain id 1
            if (chainId == 1) {
                GAC(contractAddress[chainId][bytes("GAC")]).setMultiMessageSender(
                    contractAddress[chainId][bytes("MMA_SENDER")]
                );
            }
            for (uint256 j; j < ALL_CHAINS.length;) {
                /// @dev mma receiver is not available on chain id 1
                if (ALL_CHAINS[j] != 1) {
                    GAC(contractAddress[chainId][bytes("GAC")]).setMultiMessageReceiver(
                        ALL_CHAINS[j], contractAddress[ALL_CHAINS[j]][bytes("MMA_RECEIVER")]
                    );
                }

                unchecked {
                    ++j;
                }
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @dev setup adapter contracts
    function _setupAdapters() internal {
        vm.startPrank(owner);

        for (uint256 i; i < DST_CHAINS.length;) {
            uint256 chainId = DST_CHAINS[i];
            vm.selectFork(fork[chainId]);

            WormholeReceiverAdapter(contractAddress[chainId]["WORMHOLE_RECEIVER_ADAPTER"]).updateSenderAdapter(
                abi.encode(_wormholeChainId(1)), contractAddress[1]["WORMHOLE_SENDER_ADAPTER"]
            );

            AxelarReceiverAdapter(contractAddress[chainId]["AXELAR_RECEIVER_ADAPTER"]).updateSenderAdapter(
                abi.encode(_axelarChainId(1)), contractAddress[1]["AXELAR_SENDER_ADAPTER"]
            );

            unchecked {
                ++i;
            }
        }
    }

    /// @dev helps payload delivery using logs
    function _simulatePayloadDelivery(uint256 _srcChainId, uint256 _dstChainId, Vm.Log[] memory _logs) internal {
        /// simulate wormhole off-chain infra
        WormholeHelper(contractAddress[_srcChainId][bytes("WORMHOLE_HELPER")]).help(
            _wormholeChainId(_srcChainId), fork[_dstChainId], _wormholeRelayer(_dstChainId), _logs
        );

        /// simulate axelar off-chain infra
        AxelarHelper(contractAddress[_srcChainId][bytes("AXELAR_HELPER")]).help(
            _axelarChainId(_srcChainId),
            _axelarGateway(_dstChainId),
            _axelarChainId(_dstChainId),
            fork[_dstChainId],
            _logs
        );
    }

    /// @dev returns the chain id of wormhole for local chain id
    function _wormholeChainId(uint256 _chainId) internal pure returns (uint16) {
        if (_chainId == 1) {
            return uint16(2);
        }

        if (_chainId == 56) {
            return uint16(4);
        }

        if (_chainId == 137) {
            return uint16(5);
        }

        return 0;
    }

    /// @dev returns the chain id of axelar for local chain id
    function _axelarChainId(uint256 _chainId) internal pure returns (string memory) {
        if (_chainId == 1) {
            return "ethereum";
        }

        if (_chainId == 56) {
            return "binance";
        }

        if (_chainId == 137) {
            return "polygon";
        }

        return "";
    }

    /// @dev returns the relayer of wormhole for chain id
    function _wormholeRelayer(uint256 _chainId) internal pure returns (address) {
        if (_chainId == 1) {
            return ETH_RELAYER;
        }

        if (_chainId == 56) {
            return BSC_RELAYER;
        }

        if (_chainId == 137) {
            return POLYGON_RELAYER;
        }

        return address(0);
    }

    /// @dev returns the gateway of axelar for chain id
    function _axelarGateway(uint256 _chainId) internal pure returns (address) {
        if (_chainId == 1) {
            return ETH_GATEWAY;
        }

        if (_chainId == 56) {
            return BSC_GATEWAY;
        }

        if (_chainId == 137) {
            return POLYGON_GATEWAY;
        }

        return address(0);
    }
}
