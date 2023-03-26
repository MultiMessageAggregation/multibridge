import {receiverFixture} from "./fixtures";
import {ethers} from "hardhat";
import {Wallet} from "ethers";
import {expect} from "chai";
import {MockAdapter, MultiMessageReceiver} from "../typechain";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";

describe("MultiMessageReceiver test", function() {
    let wallet: Wallet;
    let multiMessageReceiver: MultiMessageReceiver;
    let mockReceiverAdapter: MockAdapter;
    let chainId: number;

    before("preparation", async () => {
        [wallet] = await (ethers as any).getSigners();
        chainId = (await ethers.getDefaultProvider().getNetwork()).chainId;
    })

    beforeEach("deploy fixture", async () => {
        ({ multiMessageReceiver, mockReceiverAdapter } = await loadFixture(receiverFixture));
    })

    it('only initialize once', async function () {
        await expect(
            multiMessageReceiver.initialize(
                [chainId],
                [ethers.utils.getAddress("0x0000000000000000000000000000000000000002")],
                [mockReceiverAdapter.address],
                [100],
                [66],
            )
        ).to.be.revertedWith("Initializable: contract is already initialized")
    });

    it('not allowed sender adapter', async function () {
        await expect(
            mockReceiverAdapter.executeMessage(
                ethers.constants.AddressZero,
                chainId,
                ethers.constants.HashZero,
                ethers.utils.getAddress("0x0000000000000000000000000000000000000001"),
                multiMessageReceiver.address,
                ethers.utils.randomBytes(1),
            )
        ).to.be.revertedWith("not allowed message sender")
    });

    it('not directly callable', async function () {
        await expect(
            multiMessageReceiver.updateQuorumThreshold(100)
        ).to.be.revertedWith("not self")
    });

    it('should successfully update quorum threshold', async function () {
        const bridgeName = await mockReceiverAdapter.name();
        const newQuorumThreshold = 67;
        const dataForTarget = multiMessageReceiver.interface.encodeFunctionData("updateQuorumThreshold", [newQuorumThreshold]);
        const dataDispatched = multiMessageReceiver.interface.encodeFunctionData("receiveMessage",
            [ {
                dstChainId: chainId,
                nonce: 0,
                target: multiMessageReceiver.address,
                callData: dataForTarget,
                bridgeName: bridgeName,
            }])
        await expect(
            mockReceiverAdapter.executeMessage(
                mockReceiverAdapter.address,
                chainId,
                ethers.constants.HashZero,
                ethers.utils.getAddress("0x0000000000000000000000000000000000000001"),
                multiMessageReceiver.address,
                dataDispatched,
            )
        ).to.emit(multiMessageReceiver, "SingleBridgeMsgReceived")
            .withArgs(chainId, bridgeName, 0, mockReceiverAdapter.address)
            .to.emit(multiMessageReceiver, "MessageExecuted")
            .withArgs(chainId, 0, multiMessageReceiver.address, dataForTarget)
            .to.emit(multiMessageReceiver, "QuorumThresholdUpdated")
            .withArgs(newQuorumThreshold)

        await expect(
            mockReceiverAdapter.executeMessage(
                mockReceiverAdapter.address,
                chainId,
                ethers.constants.HashZero,
                ethers.utils.getAddress("0x0000000000000000000000000000000000000001"),
                multiMessageReceiver.address,
                dataDispatched,
            )
        ).to.be.revertedWithCustomError(mockReceiverAdapter, "MessageIdAlreadyExecuted")
            .withArgs(ethers.constants.HashZero)

        const errABI = ["function Error(string reason)"]
        const errInterface = new ethers.utils.Interface(errABI)
        const error = errInterface.encodeFunctionData("Error", ["this message is not from MultiMessageSender"])
        const anotherNonce = ethers.utils.hexZeroPad("0x01", 32)
        await expect(
            mockReceiverAdapter.executeMessage(
                mockReceiverAdapter.address,
                chainId,
                anotherNonce,
                ethers.utils.getAddress("0x0000000000000000000000000000000000000000"),
                multiMessageReceiver.address,
                dataDispatched,
            )
        ).to.be.revertedWithCustomError(mockReceiverAdapter, "MessageFailure")
            .withArgs(anotherNonce, error)
    });

    it('should successfully add another adapter', async function () {
        const mockReceiverAdapterFactory = await ethers.getContractFactory("MockAdapter");
        const mockReceiverAdapter2 = (await mockReceiverAdapterFactory.deploy()) as MockAdapter;
        await mockReceiverAdapter2.deployed();
        await mockReceiverAdapter2.updateSenderAdapter([chainId], [mockReceiverAdapter2.address]);

        const bridgeName = await mockReceiverAdapter.name();
        const power2 = 100;
        const dataForAdd = multiMessageReceiver.interface.encodeFunctionData("updateReceiverAdapter",
            [[mockReceiverAdapter2.address], [power2]]);
        let dataDispatched = multiMessageReceiver.interface.encodeFunctionData("receiveMessage",
            [ {
                dstChainId: chainId,
                nonce: 0,
                target: multiMessageReceiver.address,
                callData: dataForAdd,
                bridgeName: bridgeName,
            }]);
        await expect(
            mockReceiverAdapter.executeMessage(
                mockReceiverAdapter.address,
                chainId,
                ethers.constants.HashZero,
                ethers.utils.getAddress("0x0000000000000000000000000000000000000001"),
                multiMessageReceiver.address,
                dataDispatched,
            )
        ).to.emit(multiMessageReceiver, "SingleBridgeMsgReceived")
            .withArgs(chainId, bridgeName, 0, mockReceiverAdapter.address)
            .to.emit(multiMessageReceiver, "MessageExecuted")
            .withArgs(chainId, 0, multiMessageReceiver.address, dataForAdd)
            .to.emit(multiMessageReceiver, "ReceiverAdapterUpdated")
            .withArgs(mockReceiverAdapter2.address, power2)

        const newQuorumThreshold = 67;
        const dataForUpdateQuorum = multiMessageReceiver.interface.encodeFunctionData("updateQuorumThreshold",
            [newQuorumThreshold]);
        dataDispatched = multiMessageReceiver.interface.encodeFunctionData("receiveMessage",
            [ {
                dstChainId: chainId,
                nonce: 1,
                target: multiMessageReceiver.address,
                callData: dataForUpdateQuorum,
                bridgeName: bridgeName,
            }]);
        await expect(
            mockReceiverAdapter.executeMessage(
                mockReceiverAdapter.address,
                chainId,
                ethers.utils.hexZeroPad("0x01", 32),
                ethers.utils.getAddress("0x0000000000000000000000000000000000000001"),
                multiMessageReceiver.address,
                dataDispatched,
            )
        ).to.emit(multiMessageReceiver, "SingleBridgeMsgReceived")
            .withArgs(chainId, bridgeName, 1, mockReceiverAdapter.address)
            .not.to.emit(multiMessageReceiver, "MessageExecuted")
        await expect(
            mockReceiverAdapter2.executeMessage(
                mockReceiverAdapter2.address,
                chainId,
                ethers.constants.HashZero,
                ethers.utils.getAddress("0x0000000000000000000000000000000000000001"),
                multiMessageReceiver.address,
                dataDispatched,
            )
        ).to.emit(multiMessageReceiver, "SingleBridgeMsgReceived")
            .withArgs(chainId, bridgeName, 1, mockReceiverAdapter2.address)
            .to.emit(multiMessageReceiver, "MessageExecuted")
            .withArgs(chainId, 1, multiMessageReceiver.address, dataForUpdateQuorum)
            .to.emit(multiMessageReceiver, "QuorumThresholdUpdated")
            .withArgs(newQuorumThreshold)
    });
})