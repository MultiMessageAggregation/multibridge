import { senderFixture } from './fixtures';
import { ethers } from 'hardhat';
import { Wallet } from 'ethers';
import { expect } from 'chai';
import { MockCaller, MockAdapter, MultiMessageSender } from '../typechain';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';

describe('MultiMessageSender test', function () {
  let wallet: Wallet;
  let mockCaller: MockCaller;
  let multiMessageSender: MultiMessageSender;
  let mockSenderAdapter: MockAdapter;
  let chainId: number;

  before('preparation', async () => {
    [wallet] = await (ethers as any).getSigners();
    chainId = (await ethers.getDefaultProvider().getNetwork()).chainId;
  });

  beforeEach('deploy fixture', async () => {
    ({ mockCaller, multiMessageSender, mockSenderAdapter } = await loadFixture(senderFixture));
  });

  it('check caller role', async function () {
    expect(await multiMessageSender.caller()).to.equal(mockCaller.address);
    expect(await mockCaller.hasRole(await mockCaller.CALLER_ROLE(), wallet.address)).to.equal(true);
  });

  it('not caller', async function () {
    await expect(
      multiMessageSender.remoteCall(
        0,
        ethers.constants.AddressZero,
        ethers.constants.AddressZero,
        ethers.utils.randomBytes(1)
      )
    ).to.be.revertedWith('not caller');
  });

  it('insufficient fee', async function () {
    await expect(
      mockCaller.remoteCall(0, ethers.constants.AddressZero, ethers.constants.AddressZero, ethers.utils.randomBytes(1))
    ).to.be.reverted;
  });

  it('should successfully remote call ', async function () {
    const data = ethers.utils.randomBytes(1);
    const fee = await multiMessageSender.estimateTotalMessageFee(
      chainId,
      ethers.constants.AddressZero,
      ethers.constants.AddressZero,
      data
    );
    await expect(
      mockCaller.remoteCall(chainId, ethers.constants.AddressZero, ethers.constants.AddressZero, data, { value: fee })
    )
      .to.emit(multiMessageSender, 'MultiMessageMsgSent')
      .withArgs(0, chainId, ethers.constants.AddressZero, ethers.utils.hexlify(data), [mockSenderAdapter.address]);
  });

  it('should successfully remove mock senderAdapter ', async function () {
    await expect(mockCaller.removeSenderAdapters([mockSenderAdapter.address]))
      .to.emit(multiMessageSender, 'SenderAdapterUpdated')
      .withArgs(mockSenderAdapter.address, false);
  });
});
