// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import {Test, Vm} from "forge-std/Test.sol";

import "openzeppelin-contracts/contracts/access/Ownable.sol";

/// @dev imports from Pigeon Helper (Facilitate State Transfer Mocks)
import {WormholeHelper} from "pigeon/wormhole/WormholeHelper.sol";
import {AxelarHelper} from "pigeon/axelar/AxelarHelper.sol";

/// local imports
import {WormholeSenderAdapter} from "src/adapters/wormhole/WormholeSenderAdapter.sol";
import {WormholeReceiverAdapter} from "src/adapters/wormhole/WormholeReceiverAdapter.sol";

import {AxelarSenderAdapter} from "src/adapters/axelar/AxelarSenderAdapter.sol";
import {AxelarReceiverAdapter} from "src/adapters/axelar/AxelarReceiverAdapter.sol";

import {GAC} from "src/controllers/GAC.sol";
import {MessageSenderGAC} from "src/controllers/MessageSenderGAC.sol";
import {MessageReceiverGAC} from "src/controllers/MessageReceiverGAC.sol";
import {GovernanceTimelock} from "src/controllers/GovernanceTimelock.sol";

import {MultiBridgeMessageSender} from "src/MultiBridgeMessageSender.sol";
import {MultiBridgeMessageReceiver} from "src/MultiBridgeMessageReceiver.sol";

/// @dev can inherit the setup in tests
abstract contract Setup is Test {
    bytes32 _salt = keccak256(abi.encode("UNISWAP_MMA"));

    /*///////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/
    /// @dev chain IDs
    uint256 constant ETHEREUM_CHAIN_ID = 1;
    uint256 constant BSC_CHAIN_ID = 56;
    uint256 constant POLYGON_CHAIN_ID = 137;

    /// @dev common src and dst chain IDs
    uint256 constant SRC_CHAIN_ID = ETHEREUM_CHAIN_ID;
    uint256 constant DST_CHAIN_ID = POLYGON_CHAIN_ID;

    /// @dev simulated caller
    address constant caller = address(10);
    address constant owner = address(420);
    address constant refundAddress = address(420420);
    uint256 constant EXPIRATION_CONSTANT = 5 days;
    uint256 constant DEFAULT_SUCCESS_THRESHOLD = 2;

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
    uint256[] public ALL_CHAINS = [ETHEREUM_CHAIN_ID, BSC_CHAIN_ID, POLYGON_CHAIN_ID];

    /// @notice configure any new dst chains here
    uint256[] public DST_CHAINS = [BSC_CHAIN_ID, POLYGON_CHAIN_ID];

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
        fork[ETHEREUM_CHAIN_ID] = vm.createSelectFork(vm.envString("ETH_FORK_URL"));
        vm.deal(caller, 100 ether);

        fork[BSC_CHAIN_ID] = vm.createSelectFork(vm.envString("BSC_FORK_URL"));
        vm.deal(caller, 100 ether);

        fork[POLYGON_CHAIN_ID] = vm.createSelectFork(vm.envString("POLYGON_FORK_URL"));
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

        /// @dev gives up owner to timelock
        _setupTimelockAsOwner();
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

            address gac;
            if (chainId == SRC_CHAIN_ID) {
                MessageSenderGAC senderGAC = new MessageSenderGAC{salt: _salt}();
                senderGAC.setAuthorisedCaller(caller);
                gac = address(senderGAC);
            } else {
                MessageReceiverGAC receiverGAC = new MessageReceiverGAC{salt: _salt}();
                gac = address(receiverGAC);
            }
            contractAddress[chainId][bytes("GAC")] = address(gac);

            unchecked {
                ++i;
            }
        }
    }

    /// @dev deploys the wormhole adapters to all configured chains
    function _deployWormholeAdapters() internal {
        /// @notice deploy source adapter to SRC_CHAIN (ETH)
        vm.selectFork(fork[SRC_CHAIN_ID]);

        contractAddress[SRC_CHAIN_ID][bytes("WORMHOLE_SENDER_ADAPTER")] =
            address(new WormholeSenderAdapter{salt: _salt}(ETH_RELAYER, contractAddress[SRC_CHAIN_ID][bytes("GAC")]));

        uint256 len = DST_CHAINS.length;

        /// @notice deploy receiver adapters to all DST_CHAINS
        address[] memory _receiverAdapters = new address[](len);

        uint16 srcChainId = _wormholeChainId(SRC_CHAIN_ID);
        for (uint256 i; i < len;) {
            uint256 chainId = DST_CHAINS[i];
            vm.selectFork(fork[chainId]);

            address receiverAdapter = address(
                new WormholeReceiverAdapter{salt: _salt}(
                    WORMHOLE_RELAYERS[i], srcChainId, contractAddress[chainId][bytes("GAC")]
                )
            );
            contractAddress[chainId][bytes("WORMHOLE_RECEIVER_ADAPTER")] = receiverAdapter;
            _receiverAdapters[i] = receiverAdapter;

            unchecked {
                ++i;
            }
        }

        /// @dev sets some configs to sender adapter (ETH_CHAIN_ADAPTER)
        vm.selectFork(fork[SRC_CHAIN_ID]);

        WormholeSenderAdapter(contractAddress[SRC_CHAIN_ID][bytes("WORMHOLE_SENDER_ADAPTER")]).updateReceiverAdapter(
            DST_CHAINS, _receiverAdapters
        );

        WormholeSenderAdapter(contractAddress[SRC_CHAIN_ID][bytes("WORMHOLE_SENDER_ADAPTER")]).setChainIdMap(
            DST_CHAINS, WORMHOLE_CHAIN_IDS
        );
    }

    /// @dev deploys the axelar adapters to all configured chains
    function _deployAxelarAdapters() internal {
        /// @notice deploy source adapter to Ethereum
        vm.selectFork(fork[SRC_CHAIN_ID]);
        contractAddress[SRC_CHAIN_ID][bytes("AXELAR_SENDER_ADAPTER")] = address(
            new AxelarSenderAdapter{salt: _salt}(
                ETH_GAS_SERVICE, ETH_GATEWAY, contractAddress[SRC_CHAIN_ID][bytes("GAC")]
            )
        );

        uint256 len = DST_CHAINS.length;

        /// @notice deploy receiver adapters to all DST_CHAINS
        address[] memory _receiverAdapters = new address[](len);

        for (uint256 i; i < len;) {
            uint256 chainId = DST_CHAINS[i];
            vm.selectFork(fork[chainId]);

            address receiverAdapter = address(
                new AxelarReceiverAdapter{salt: _salt}(
                    AXELAR_GATEWAYS[i], "ethereum", contractAddress[chainId][bytes("GAC")]
                )
            );
            contractAddress[chainId][bytes("AXELAR_RECEIVER_ADAPTER")] = receiverAdapter;
            _receiverAdapters[i] = receiverAdapter;

            unchecked {
                ++i;
            }
        }

        vm.selectFork(fork[SRC_CHAIN_ID]);

        AxelarSenderAdapter(contractAddress[SRC_CHAIN_ID][bytes("AXELAR_SENDER_ADAPTER")]).updateReceiverAdapter(
            DST_CHAINS, _receiverAdapters
        );

        AxelarSenderAdapter(contractAddress[SRC_CHAIN_ID][bytes("AXELAR_SENDER_ADAPTER")]).setChainIdMap(
            DST_CHAINS, AXELAR_CHAIN_IDS
        );
    }

    /// @dev deploys the amb helpers to all configured chains
    function _deployHelpers() internal {
        /// @notice deploy amb helpers to Ethereum
        vm.selectFork(fork[SRC_CHAIN_ID]);
        contractAddress[SRC_CHAIN_ID][bytes("WORMHOLE_HELPER")] = address(new WormholeHelper());
        contractAddress[SRC_CHAIN_ID][bytes("AXELAR_HELPER")] = address(new AxelarHelper());

        vm.allowCheatcodes(contractAddress[SRC_CHAIN_ID][bytes("WORMHOLE_HELPER")]);
        vm.allowCheatcodes(contractAddress[SRC_CHAIN_ID][bytes("AXELAR_HELPER")]);

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
        vm.selectFork(fork[SRC_CHAIN_ID]);
        contractAddress[SRC_CHAIN_ID][bytes("MMA_SENDER")] =
            address(new MultiBridgeMessageSender{salt: _salt}(contractAddress[SRC_CHAIN_ID][bytes("GAC")]));

        /// @notice deploy amb helpers to BSC & POLYGON
        for (uint256 i; i < DST_CHAINS.length; i++) {
            uint256 chainId = DST_CHAINS[i];

            vm.selectFork(fork[chainId]);

            address[] memory _receiverAdapters = new address[](2);
            _receiverAdapters[0] = contractAddress[chainId][bytes("WORMHOLE_RECEIVER_ADAPTER")];
            _receiverAdapters[1] = contractAddress[chainId][bytes("AXELAR_RECEIVER_ADAPTER")];

            address mmaReceiver = address(
                new MultiBridgeMessageReceiver{salt: _salt}(
                    SRC_CHAIN_ID, contractAddress[chainId][bytes("GAC")], _receiverAdapters, 2
                )
            );
            contractAddress[chainId][bytes("MMA_RECEIVER")] = mmaReceiver;
            contractAddress[chainId][bytes("TIMELOCK")] =
                address(address(new GovernanceTimelock{salt: _salt}(mmaReceiver, 3 days)));
        }
    }

    /// @dev setup core contracts
    function _setupCoreContracts() internal {
        /// setup mma sender adapters
        vm.selectFork(fork[SRC_CHAIN_ID]);
        vm.startPrank(owner);

        address[] memory _senderAdapters = _sortTwoAdapters(
            contractAddress[SRC_CHAIN_ID][bytes("AXELAR_SENDER_ADAPTER")],
            contractAddress[SRC_CHAIN_ID][bytes("WORMHOLE_SENDER_ADAPTER")]
        );

        MultiBridgeMessageSender(contractAddress[SRC_CHAIN_ID][bytes("MMA_SENDER")]).addSenderAdapters(_senderAdapters);

        MessageSenderGAC senderGAC = MessageSenderGAC(contractAddress[SRC_CHAIN_ID][bytes("GAC")]);
        senderGAC.setMultiBridgeMessageSender(contractAddress[SRC_CHAIN_ID][bytes("MMA_SENDER")]);

        /// setup mma receiver adapters
        for (uint256 i; i < DST_CHAINS.length;) {
            uint256 chainId = DST_CHAINS[i];

            vm.selectFork(fork[chainId]);

            MultiBridgeMessageReceiver dstMMReceiver =
                MultiBridgeMessageReceiver(contractAddress[chainId][bytes("MMA_RECEIVER")]);
            dstMMReceiver.updateGovernanceTimelock(contractAddress[chainId]["TIMELOCK"]);

            MessageReceiverGAC receiverGAC = MessageReceiverGAC(contractAddress[chainId][bytes("GAC")]);
            receiverGAC.setMultiBridgeMessageReceiver(address(dstMMReceiver));

            vm.selectFork(fork[SRC_CHAIN_ID]);
            senderGAC.setRemoteMultiBridgeMessageReceiver(chainId, address(dstMMReceiver));

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
                contractAddress[SRC_CHAIN_ID]["WORMHOLE_SENDER_ADAPTER"]
            );

            AxelarReceiverAdapter(contractAddress[chainId]["AXELAR_RECEIVER_ADAPTER"]).updateSenderAdapter(
                contractAddress[SRC_CHAIN_ID]["AXELAR_SENDER_ADAPTER"]
            );

            unchecked {
                ++i;
            }
        }
    }

    /// @dev admin gives up ownership to
    function _setupTimelockAsOwner() internal {
        /// transfer ownership to timelock finally
        for (uint256 i; i < ALL_CHAINS.length;) {
            uint256 chainId = ALL_CHAINS[i];

            vm.selectFork(fork[chainId]);

            if (chainId != SRC_CHAIN_ID) {
                GAC(contractAddress[chainId][bytes("GAC")]).transferOwnership(
                    contractAddress[chainId][bytes("TIMELOCK")]
                );
            }

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
        if (_chainId == ETHEREUM_CHAIN_ID) {
            return uint16(2);
        }

        if (_chainId == BSC_CHAIN_ID) {
            return uint16(4);
        }

        if (_chainId == POLYGON_CHAIN_ID) {
            return uint16(5);
        }

        return 0;
    }

    /// @dev returns the chain id of axelar for local chain id
    function _axelarChainId(uint256 _chainId) internal pure returns (string memory) {
        if (_chainId == ETHEREUM_CHAIN_ID) {
            return "ethereum";
        }

        if (_chainId == BSC_CHAIN_ID) {
            return "binance";
        }

        if (_chainId == POLYGON_CHAIN_ID) {
            return "polygon";
        }

        return "";
    }

    /// @dev returns the relayer of wormhole for chain id
    function _wormholeRelayer(uint256 _chainId) internal pure returns (address) {
        if (_chainId == ETHEREUM_CHAIN_ID) {
            return ETH_RELAYER;
        }

        if (_chainId == BSC_CHAIN_ID) {
            return BSC_RELAYER;
        }

        if (_chainId == POLYGON_CHAIN_ID) {
            return POLYGON_RELAYER;
        }

        return address(0);
    }

    /// @dev returns the gateway of axelar for chain id
    function _axelarGateway(uint256 _chainId) internal pure returns (address) {
        if (_chainId == ETHEREUM_CHAIN_ID) {
            return ETH_GATEWAY;
        }

        if (_chainId == BSC_CHAIN_ID) {
            return BSC_GATEWAY;
        }

        if (_chainId == POLYGON_CHAIN_ID) {
            return POLYGON_GATEWAY;
        }

        return address(0);
    }

    /// @dev gets the message id from msg logs
    function _getMsgId(Vm.Log[] memory logs) internal pure returns (bytes32 msgId) {
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("BridgeMessageReceived(bytes32,string,uint256,address)")) {
                msgId = logs[i].topics[1];
            }
        }
    }

    /// @dev get execute tx info from logs
    function _getExecParams(Vm.Log[] memory logs)
        internal
        pure
        returns (uint256 txId, address finalTarget, uint256 value, bytes memory data, uint256 eta)
    {
        bytes memory encodedArgs;

        for (uint256 j; j < logs.length; j++) {
            if (logs[j].topics[0] == keccak256("TransactionScheduled(uint256,address,uint256,bytes,uint256)")) {
                txId = uint256(logs[j].topics[1]);
                finalTarget = abi.decode(bytes.concat(logs[j].topics[2]), (address));
                encodedArgs = logs[j].data;
                (value, data, eta) = abi.decode(encodedArgs, (uint256, bytes, uint256));
            }
        }
    }

    // @dev sorts two adapters
    function _sortTwoAdapters(address adapterA, address adapterB) internal pure returns (address[] memory adapters) {
        adapters = new address[](2);
        if (adapterA < adapterB) {
            adapters[0] = adapterA;
            adapters[1] = adapterB;
        } else {
            adapters[0] = adapterB;
            adapters[1] = adapterA;
        }
    }

    // @dev sorts two adapters with fees
    function _sortTwoAdaptersWithFees(address adapterA, address adapterB, uint256 feeA, uint256 feeB)
        internal
        pure
        returns (address[] memory adapters, uint256[] memory fees)
    {
        adapters = new address[](2);
        fees = new uint256[](2);
        if (adapterA < adapterB) {
            adapters[0] = adapterA;
            adapters[1] = adapterB;
            fees[0] = feeA;
            fees[1] = feeB;
        } else {
            adapters[0] = adapterB;
            adapters[1] = adapterA;
            fees[0] = feeB;
            fees[1] = feeA;
        }
    }

    // @dev sorts two adapters with fees and ops
    function _sortTwoAdaptersWithFeesAndOps(
        address adapterA,
        address adapterB,
        uint256 feeA,
        uint256 feeB,
        bool opA,
        bool opB
    ) internal pure returns (address[] memory adapters, uint256[] memory fees, bool[] memory ops) {
        adapters = new address[](2);
        fees = new uint256[](2);
        ops = new bool[](2);
        if (adapterA < adapterB) {
            adapters[0] = adapterA;
            adapters[1] = adapterB;
            fees[0] = feeA;
            fees[1] = feeB;
            ops[0] = opA;
            ops[1] = opB;
        } else {
            adapters[0] = adapterB;
            adapters[1] = adapterA;
            fees[0] = feeB;
            fees[1] = feeA;
            ops[0] = opB;
            ops[1] = opA;
        }
    }

    function _sortThreeAdaptersWithFeesAndOps(address[] memory _adapters, uint256[] memory _fees, bool[] memory _ops)
        internal
        pure
        returns (address[] memory sortedAdapters, uint256[] memory sortedFees, bool[] memory sortedOps)
    {
        require(_adapters.length == 3 && _fees.length == 3 && _ops.length == 3, "invalid params");

        sortedAdapters = new address[](3);
        sortedFees = new uint256[](3);
        sortedOps = new bool[](3);
        (address[] memory s1Ads, uint256[] memory s1Fees, bool[] memory s1Ops) =
            _sortTwoAdaptersWithFeesAndOps(_adapters[0], _adapters[1], _fees[0], _fees[1], _ops[0], _ops[1]);
        if (_adapters[2] > s1Ads[1]) {
            (sortedAdapters[0], sortedAdapters[1], sortedAdapters[2]) = (s1Ads[0], s1Ads[1], _adapters[2]);
            (sortedFees[0], sortedFees[1], sortedFees[2]) = (s1Fees[0], s1Fees[1], _fees[2]);
            (sortedOps[0], sortedOps[1], sortedOps[2]) = (s1Ops[0], s1Ops[1], _ops[2]);
        } else {
            (address[] memory s2Ads, uint256[] memory s2Fees, bool[] memory s2Ops) =
                _sortTwoAdaptersWithFeesAndOps(_adapters[2], s1Ads[0], _fees[2], s1Fees[0], _ops[2], s1Ops[0]);
            (sortedAdapters[0], sortedAdapters[1], sortedAdapters[2]) = (s2Ads[0], s2Ads[1], s1Ads[1]);
            (sortedFees[0], sortedFees[1], sortedFees[2]) = (s2Fees[0], s2Fees[1], s1Fees[1]);
            (sortedOps[0], sortedOps[1], sortedOps[2]) = (s2Ops[0], s2Ops[1], s1Ops[1]);
        }
    }
}
