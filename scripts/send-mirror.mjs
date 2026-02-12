import { Connection, Keypair, PublicKey, Transaction } from '@solana/web3.js';
import { getAssociatedTokenAddress, createAssociatedTokenAccountInstruction, createTransferInstruction } from '@solana/spl-token';
import fs from 'fs';

const MIRROR_MINT = new PublicKey('JCwYyprqV92Vf1EaFBTxRtbvfd56uMw5yFSgrBKEs21u');
const connection = new Connection('https://api.mainnet-beta.solana.com', 'confirmed');

const keypairData = JSON.parse(fs.readFileSync('/root/.openclaw/agents/macmini/agent/solana/id.json'));
const wallet = Keypair.fromSecretKey(Uint8Array.from(keypairData));

const recipient = new PublicKey(process.argv[2]);
const amount = parseInt(process.argv[3]) * 100000; // MIRROR has 5 decimals

async function main() {
  console.log('Sending', amount / 100000, 'MIRROR to', recipient.toBase58());
  
  const myAta = await getAssociatedTokenAddress(MIRROR_MINT, wallet.publicKey);
  const recipientAta = await getAssociatedTokenAddress(MIRROR_MINT, recipient);
  
  const tx = new Transaction();
  
  // Check if recipient ATA exists
  const recipientAtaInfo = await connection.getAccountInfo(recipientAta);
  if (!recipientAtaInfo) {
    console.log('Creating recipient ATA...');
    tx.add(createAssociatedTokenAccountInstruction(
      wallet.publicKey,
      recipientAta,
      recipient,
      MIRROR_MINT
    ));
  }
  
  tx.add(createTransferInstruction(
    myAta,
    recipientAta,
    wallet.publicKey,
    amount
  ));
  
  const { blockhash } = await connection.getLatestBlockhash();
  tx.recentBlockhash = blockhash;
  tx.feePayer = wallet.publicKey;
  
  const sig = await connection.sendTransaction(tx, [wallet]);
  console.log('Sent! Signature:', sig);
  
  await connection.confirmTransaction(sig, 'confirmed');
  console.log('Confirmed!');
}

main().catch(console.error);
