import { ethers } from 'hardhat';
import { MockCaller, MockAdapter, MultiMessageSender, MultiMessageReceiver } from '../typechain';

interface SenderFixture {
  mockCaller: MockCaller;
  multiMessageSender: MultiMessageSender;
  mockSenderAdapter: MockAdapter;
}

interface ReceiverFixture {
  multiMessageReceiver: MultiMessageReceiver;
  mockReceiverAdapter: MockAdapter;
}

async function deployMockAdapter(): Promise<MockAdapter> {
  const adapterFactory = await ethers.getContractFactory('MockAdapter');
  const adapter = (await adapterFactory.deploy()) as MockAdapter;
  await adapter.deployed();
  return adapter;
}

export async function senderFixture(): Promise<SenderFixture> {
  const mockCallerFactory = await ethers.getContractFactory('MockCaller');
  const mockCaller = (await mockCallerFactory.deploy()) as MockCaller;
  await mockCaller.deployed();

  const multiMessageSenderFactory = await ethers.getContractFactory('MultiMessageSender');
  const multiMessageSender = (await multiMessageSenderFactory.deploy(mockCaller.address)) as MultiMessageSender;
  await multiMessageSender.deployed();

  let tx = await mockCaller.setMultiMessageSender(multiMessageSender.address);
  await tx.wait();

  const mockSenderAdapter = await deployMockAdapter();

  const network = await ethers.provider.getNetwork();
  tx = await mockSenderAdapter.updateReceiverAdapter([network.chainId], [mockSenderAdapter.address]);
  await tx.wait();

  tx = await mockCaller.addSenderAdapters([mockSenderAdapter.address]);
  await tx.wait();
  const callRole = await mockCaller.CALLER_ROLE();
  const [wallet] = await ethers.getSigners();
  tx = await mockCaller.grantRole(callRole, wallet.address);
  await tx.wait();
  return { mockCaller, multiMessageSender, mockSenderAdapter };
}

export async function receiverFixture(): Promise<ReceiverFixture> {
  const multiMessageReceiverFactory = await ethers.getContractFactory('MultiMessageReceiver');
  const multiMessageReceiver = (await multiMessageReceiverFactory.deploy()) as MultiMessageReceiver;
  await multiMessageReceiver.deployed();

  const mockReceiverAdapter = await deployMockAdapter();

  const network = await ethers.provider.getNetwork();
  let tx = await mockReceiverAdapter.updateSenderAdapter([network.chainId], [mockReceiverAdapter.address]);
  await tx.wait();

  tx = await multiMessageReceiver.initialize(
    [network.chainId],
    [ethers.utils.getAddress('0x0000000000000000000000000000000000000001')],
    [mockReceiverAdapter.address],
    [1]
  );
  await tx.wait();

  return { multiMessageReceiver, mockReceiverAdapter };
}
