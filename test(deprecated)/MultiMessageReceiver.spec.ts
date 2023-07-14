import { receiverFixture } from './fixtures';
import { ethers } from 'hardhat';
import { Wallet } from 'ethers';
import { expect } from 'chai';
import { keccak256 } from '@ethersproject/solidity';
import { MockAdapter, MultiMessageReceiver } from '../typechain';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';

describe('MultiMessageReceiver test', function () {
  let wallet: Wallet;
  let multiMessageReceiver: MultiMessageReceiver;
  let mockReceiverAdapter: MockAdapter;
  let chainId: number;
  let bridgeName: string;
  const errABI = ['function Error(string reason)'];
  const errInterface = new ethers.utils.Interface(errABI);

  before('preparation', async () => {
    [wallet] = await (ethers as any).getSigners();
    chainId = (await ethers.provider.getNetwork()).chainId;
  });

  beforeEach('deploy fixture', async () => {
    ({ multiMessageReceiver, mockReceiverAdapter } = await loadFixture(receiverFixture));
    bridgeName = await mockReceiverAdapter.name();
    await mockReceiverAdapter.updateSenderAdapter([chainId], [mockReceiverAdapter.address]);
  });

  it('only initialize once', async function () {
    await expect(
      multiMessageReceiver.initialize(
        chainId,
        ethers.utils.getAddress('0x0000000000000000000000000000000000000002'),
        [mockReceiverAdapter.address],
        [2]
      )
    ).to.be.revertedWith('Initializable: contract is already initialized');
  });

  it('not allowed sender adapter', async function () {
    await expect(
      mockReceiverAdapter.executeMessage(
        ethers.constants.AddressZero,
        chainId,
        ethers.constants.HashZero,
        ethers.utils.getAddress('0x0000000000000000000000000000000000000001'),
        multiMessageReceiver.address,
        ethers.utils.randomBytes(1)
      )
    ).to.be.revertedWith('not allowed message sender');
  });

  it('not directly callable', async function () {
    await expect(multiMessageReceiver.updateQuorumThreshold(100)).to.be.revertedWith('not self');
  });

  function generateDispatchedMessage(
    dstChainId: number,
    nonce: number,
    target: string,
    callData: string,
    bridgeName: string
  ): string {
    return multiMessageReceiver.interface.encodeFunctionData('receiveMessage', [
      {
        dstChainId: dstChainId,
        nonce: nonce,
        target: target,
        callData: callData,
        expiration: 0,
        bridgeName: bridgeName
      }
    ]);
  }

  describe('#quorum threshold', () => {
    let newQuorumThreshold: number;
    let dataForTarget: string;
    let dataDispatched: string;
    before('generate calldata', async () => {
      newQuorumThreshold = 1;
      dataForTarget = multiMessageReceiver.interface.encodeFunctionData('updateQuorumThreshold', [newQuorumThreshold]);
      dataDispatched = generateDispatchedMessage(chainId, 0, multiMessageReceiver.address, dataForTarget, bridgeName);
    });

    it('should successfully update', async function () {
      const msgId = keccak256(
        ['uint64', 'uint64', 'uint32', 'address', 'bytes', 'uint64'],
        [chainId, chainId, 0, multiMessageReceiver.address, dataForTarget, 0]
      );
      await expect(
        mockReceiverAdapter.executeMessage(
          mockReceiverAdapter.address,
          chainId,
          ethers.constants.HashZero,
          ethers.utils.getAddress('0x0000000000000000000000000000000000000001'),
          multiMessageReceiver.address,
          dataDispatched
        )
      )
        .to.emit(multiMessageReceiver, 'SingleBridgeMsgReceived')
        .withArgs(msgId, chainId, bridgeName, 0, mockReceiverAdapter.address);

      await expect(
        multiMessageReceiver.executeMessage(chainId, chainId, 0, multiMessageReceiver.address, dataForTarget, 0)
      )
        .to.emit(multiMessageReceiver, 'MessageExecuted')
        .withArgs(msgId, chainId, 0, multiMessageReceiver.address, dataForTarget)
        .to.emit(multiMessageReceiver, 'QuorumThresholdUpdated')
        .withArgs(newQuorumThreshold);

      await expect(
        mockReceiverAdapter.executeMessage(
          mockReceiverAdapter.address,
          chainId,
          ethers.constants.HashZero,
          ethers.utils.getAddress('0x0000000000000000000000000000000000000001'),
          multiMessageReceiver.address,
          dataDispatched
        )
      )
        .to.be.revertedWithCustomError(mockReceiverAdapter, 'MessageIdAlreadyExecuted')
        .withArgs(ethers.constants.HashZero);
    });

    it('should revert with customer error MessageFailure(not from MultiMessageSender)', async function () {
      const error = errInterface.encodeFunctionData('Error', ['not from MultiMessageSender']);
      await expect(
        mockReceiverAdapter.executeMessage(
          mockReceiverAdapter.address,
          chainId,
          ethers.constants.HashZero,
          ethers.utils.getAddress('0x0000000000000000000000000000000000000000'),
          multiMessageReceiver.address,
          dataDispatched
        )
      )
        .to.be.revertedWithCustomError(mockReceiverAdapter, 'MessageFailure')
        .withArgs(ethers.constants.HashZero, error);
    });

    it('should revert with customer error MessageFailure(external message execution failed)', async function () {
      newQuorumThreshold = 2;
      dataForTarget = multiMessageReceiver.interface.encodeFunctionData('updateQuorumThreshold', [newQuorumThreshold]);
      dataDispatched = generateDispatchedMessage(chainId, 1, multiMessageReceiver.address, dataForTarget, bridgeName);
      const nonce = ethers.utils.hexZeroPad('0x01', 32);
      await expect(
        mockReceiverAdapter.executeMessage(
          mockReceiverAdapter.address,
          chainId,
          nonce,
          ethers.utils.getAddress('0x0000000000000000000000000000000000000001'),
          multiMessageReceiver.address,
          dataDispatched
        )
      );
      await expect(
        multiMessageReceiver.executeMessage(chainId, chainId, nonce, multiMessageReceiver.address, dataForTarget, 0)
      ).to.be.revertedWith('external message execution failed');
    });
  });

  async function addMockAdapter2(): Promise<MockAdapter> {
    const mockReceiverAdapterFactory = await ethers.getContractFactory('MockAdapter');
    const mockReceiverAdapter2 = (await mockReceiverAdapterFactory.deploy()) as MockAdapter;
    await mockReceiverAdapter2.deployed();
    await mockReceiverAdapter2.updateSenderAdapter([chainId], [mockReceiverAdapter2.address]);

    const dataForAdd = multiMessageReceiver.interface.encodeFunctionData('updateReceiverAdapter', [
      [mockReceiverAdapter2.address],
      [true]
    ]);
    let dataDispatched = generateDispatchedMessage(chainId, 0, multiMessageReceiver.address, dataForAdd, bridgeName);

    let msgId = keccak256(
      ['uint64', 'uint64', 'uint32', 'address', 'bytes', 'uint64'],
      [chainId, chainId, 0, multiMessageReceiver.address, dataForAdd, 0]
    );

    // add MockAdapter2
    await expect(
      mockReceiverAdapter.executeMessage(
        mockReceiverAdapter.address,
        chainId,
        ethers.constants.HashZero,
        ethers.utils.getAddress('0x0000000000000000000000000000000000000001'),
        multiMessageReceiver.address,
        dataDispatched
      )
    )
      .to.emit(multiMessageReceiver, 'SingleBridgeMsgReceived')
      .withArgs(msgId, chainId, bridgeName, 0, mockReceiverAdapter.address);

    await expect(multiMessageReceiver.executeMessage(chainId, chainId, 0, multiMessageReceiver.address, dataForAdd, 0))
      .to.emit(multiMessageReceiver, 'MessageExecuted')
      .withArgs(msgId, chainId, 0, multiMessageReceiver.address, dataForAdd)
      .to.emit(multiMessageReceiver, 'ReceiverAdapterUpdated')
      .withArgs(mockReceiverAdapter2.address, true);

    const newQuorumThreshold = 2;
    const dataForUpdateQuorum = multiMessageReceiver.interface.encodeFunctionData('updateQuorumThreshold', [
      newQuorumThreshold
    ]);
    dataDispatched = generateDispatchedMessage(
      chainId,
      1,
      multiMessageReceiver.address,
      dataForUpdateQuorum,
      bridgeName
    );

    msgId = keccak256(
      ['uint64', 'uint64', 'uint32', 'address', 'bytes', 'uint64'],
      [chainId, chainId, 1, multiMessageReceiver.address, dataForUpdateQuorum, 0]
    );
    // update quorum threshold to 2 with 1 adapter
    await expect(
      mockReceiverAdapter2.executeMessage(
        mockReceiverAdapter2.address,
        chainId,
        ethers.constants.HashZero,
        ethers.utils.getAddress('0x0000000000000000000000000000000000000001'),
        multiMessageReceiver.address,
        dataDispatched
      )
    )
      .to.emit(multiMessageReceiver, 'SingleBridgeMsgReceived')
      .withArgs(msgId, chainId, bridgeName, 1, mockReceiverAdapter2.address);

    await expect(
      multiMessageReceiver.executeMessage(chainId, chainId, 1, multiMessageReceiver.address, dataForUpdateQuorum, 0)
    )
      .to.emit(multiMessageReceiver, 'MessageExecuted')
      .withArgs(msgId, chainId, 1, multiMessageReceiver.address, dataForUpdateQuorum)
      .to.emit(multiMessageReceiver, 'QuorumThresholdUpdated')
      .withArgs(newQuorumThreshold);

    return mockReceiverAdapter2;
  }

  describe('#two adapters cases', () => {
    let mockReceiverAdapter2: MockAdapter;
    beforeEach('add MockAdapter2', async () => {
      mockReceiverAdapter2 = await addMockAdapter2();
    });

    it('should successfully update quorum threshold', async () => {
      const newQuorumThreshold = 2;
      const dataForUpdateQuorum = multiMessageReceiver.interface.encodeFunctionData('updateQuorumThreshold', [
        newQuorumThreshold
      ]);
      const dataDispatched = generateDispatchedMessage(
        chainId,
        2,
        multiMessageReceiver.address,
        dataForUpdateQuorum,
        bridgeName
      );

      const msgId = keccak256(
        ['uint64', 'uint64', 'uint32', 'address', 'bytes', 'uint64'],
        [chainId, chainId, 2, multiMessageReceiver.address, dataForUpdateQuorum, 0]
      );

      // update quorum threshold to 2 with 2 adapters
      await expect(
        mockReceiverAdapter.executeMessage(
          mockReceiverAdapter.address,
          chainId,
          ethers.utils.hexZeroPad('0x01', 32),
          ethers.utils.getAddress('0x0000000000000000000000000000000000000001'),
          multiMessageReceiver.address,
          dataDispatched
        )
      )
        .to.emit(multiMessageReceiver, 'SingleBridgeMsgReceived')
        .withArgs(msgId, chainId, bridgeName, 2, mockReceiverAdapter.address);

      await expect(
        multiMessageReceiver.executeMessage(chainId, chainId, 2, multiMessageReceiver.address, dataForUpdateQuorum, 0)
      ).to.be.revertedWith('threshold not met');

      await expect(
        mockReceiverAdapter2.executeMessage(
          mockReceiverAdapter2.address,
          chainId,
          ethers.utils.hexZeroPad('0x01', 32),
          ethers.utils.getAddress('0x0000000000000000000000000000000000000001'),
          multiMessageReceiver.address,
          dataDispatched
        )
      )
        .to.emit(multiMessageReceiver, 'SingleBridgeMsgReceived')
        .withArgs(msgId, chainId, bridgeName, 2, mockReceiverAdapter2.address);

      await expect(
        multiMessageReceiver.executeMessage(chainId, chainId, 2, multiMessageReceiver.address, dataForUpdateQuorum, 0)
      )
        .to.emit(multiMessageReceiver, 'MessageExecuted')
        .withArgs(msgId, chainId, 2, multiMessageReceiver.address, dataForUpdateQuorum)
        .to.emit(multiMessageReceiver, 'QuorumThresholdUpdated')
        .withArgs(newQuorumThreshold);
    });

    it('should not remove adapter2 before decreasing quorum threshold', async () => {
      const dataForRemoveAdapter2 = multiMessageReceiver.interface.encodeFunctionData('updateReceiverAdapter', [
        [mockReceiverAdapter2.address],
        [false]
      ]);
      const dataDispatched = generateDispatchedMessage(
        chainId,
        2,
        multiMessageReceiver.address,
        dataForRemoveAdapter2,
        bridgeName
      );

      const msgId = keccak256(
        ['uint64', 'uint64', 'uint32', 'address', 'bytes', 'uint64'],
        [chainId, chainId, 2, multiMessageReceiver.address, dataForRemoveAdapter2, 0]
      );

      await expect(
        mockReceiverAdapter.executeMessage(
          mockReceiverAdapter.address,
          chainId,
          ethers.utils.hexZeroPad('0x01', 32),
          ethers.utils.getAddress('0x0000000000000000000000000000000000000001'),
          multiMessageReceiver.address,
          dataDispatched
        )
      )
        .to.emit(multiMessageReceiver, 'SingleBridgeMsgReceived')
        .withArgs(msgId, chainId, bridgeName, 2, mockReceiverAdapter.address);

      await expect(
        mockReceiverAdapter2.executeMessage(
          mockReceiverAdapter2.address,
          chainId,
          ethers.utils.hexZeroPad('0x01', 32),
          ethers.utils.getAddress('0x0000000000000000000000000000000000000001'),
          multiMessageReceiver.address,
          dataDispatched
        )
      )
        .to.emit(multiMessageReceiver, 'SingleBridgeMsgReceived')
        .withArgs(msgId, chainId, bridgeName, 2, mockReceiverAdapter2.address);

      await expect(
        multiMessageReceiver.executeMessage(chainId, chainId, 2, multiMessageReceiver.address, dataForRemoveAdapter2, 0)
      ).to.be.revertedWith('external message execution failed');
    });
  });
});
