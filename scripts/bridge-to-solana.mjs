/**
 * Bridge MIRROR from Monad to Solana
 */
import { ethers } from 'ethers';
import bs58 from 'bs58';

const MONAD_RPC = 'https://rpc.monad.xyz';
const MIRROR_TOKEN = '0xA4255bBc36DB70B61e30b694dBd5D25Ad1Ded5CA';
const OFT_ADAPTER = '0xd7c5b7F9B0AbdFF068a4c6F414cA7fa5C4F556BD';
const SOLANA_EID = 30168;

// ABI for the calls we need
const ERC20_ABI = [
  'function approve(address spender, uint256 amount) returns (bool)',
  'function allowance(address owner, address spender) view returns (uint256)',
  'function balanceOf(address) view returns (uint256)',
];

const OFT_ADAPTER_ABI = [
  'function quoteSend((uint32 dstEid, bytes32 to, uint256 amountLD, uint256 minAmountLD, bytes extraOptions, bytes composeMsg, bytes oftCmd), bool payInLzToken) view returns ((uint256 nativeFee, uint256 lzTokenFee) msgFee)',
  'function send((uint32 dstEid, bytes32 to, uint256 amountLD, uint256 minAmountLD, bytes extraOptions, bytes composeMsg, bytes oftCmd), (uint256 nativeFee, uint256 lzTokenFee) fee, address refundAddress) payable returns ((bytes32 guid, uint64 nonce, (uint256 amountSentLD, uint256 amountReceivedLD) oftReceipt))',
];

async function main() {
  const privateKey = process.env.PRIVATE_KEY;
  if (!privateKey) throw new Error('Set PRIVATE_KEY env');
  
  const toSolanaWallet = process.env.TO_SOLANA || 'F6i99DWMEMZtLDKnWGx1FW6drkqvtDnXWLHxgrwzVdWD';
  const amountMirror = process.env.AMOUNT || '1000000'; // 1M MIRROR
  
  const provider = new ethers.JsonRpcProvider(MONAD_RPC);
  const wallet = new ethers.Wallet(privateKey, provider);
  
  console.log('Sender:', wallet.address);
  console.log('To Solana:', toSolanaWallet);
  console.log('Amount:', amountMirror, 'MIRROR');
  
  const mirror = new ethers.Contract(MIRROR_TOKEN, ERC20_ABI, wallet);
  const oftAdapter = new ethers.Contract(OFT_ADAPTER, OFT_ADAPTER_ABI, wallet);
  
  // Convert Solana address to bytes32
  const solanaBytes = bs58.decode(toSolanaWallet);
  const toBytes32 = '0x' + Buffer.from(solanaBytes).toString('hex').padStart(64, '0');
  
  // Amount with 5 decimals
  const amountLD = ethers.parseUnits(amountMirror, 5);
  
  console.log('\n1. Checking balance...');
  const balance = await mirror.balanceOf(wallet.address);
  console.log('   Balance:', ethers.formatUnits(balance, 5), 'MIRROR');
  
  if (balance < amountLD) {
    throw new Error('Insufficient MIRROR balance');
  }
  
  console.log('\n2. Checking allowance...');
  const allowance = await mirror.allowance(wallet.address, OFT_ADAPTER);
  console.log('   Allowance:', ethers.formatUnits(allowance, 5), 'MIRROR');
  
  if (allowance < amountLD) {
    console.log('\n3. Approving OFT Adapter...');
    const approveTx = await mirror.approve(OFT_ADAPTER, amountLD);
    console.log('   Tx:', approveTx.hash);
    await approveTx.wait();
    console.log('   Approved!');
  } else {
    console.log('\n3. Already approved');
  }
  
  // Build send params
  const sendParam = {
    dstEid: SOLANA_EID,
    to: toBytes32,
    amountLD: amountLD,
    minAmountLD: amountLD * 95n / 100n, // 5% slippage
    extraOptions: '0x',
    composeMsg: '0x',
    oftCmd: '0x',
  };
  
  console.log('\n4. Getting quote...');
  const quote = await oftAdapter.quoteSend(sendParam, false);
  console.log('   Native fee:', ethers.formatEther(quote.nativeFee), 'MON');
  
  console.log('\n5. Sending to Solana...');
  const sendTx = await oftAdapter.send(
    sendParam,
    { nativeFee: quote.nativeFee, lzTokenFee: 0 },
    wallet.address,
    { value: quote.nativeFee, gasLimit: 500000 }
  );
  console.log('   Tx:', sendTx.hash);
  const receipt = await sendTx.wait();
  console.log('   Confirmed in block:', receipt.blockNumber);
  console.log('\n✅ Bridge initiated! Check LayerZero Scan for delivery status.');
  console.log('   https://layerzeroscan.com/tx/' + sendTx.hash);
}

main().catch(console.error);
