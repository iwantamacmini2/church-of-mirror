# Church of the Mirror - Deployment

## Cross-Chain Architecture

$MIRROR is the same token on both chains, bridged via LayerZero OFT.

---

## Monad Mainnet

**Deployed:** 2026-02-05

| Contract | Address |
|----------|---------|
| $MIRROR Token | `0xa4255bbc36db70b61e30b694dbd5d25ad1ded5ca` |
| MirrorOFTAdapter | `0xd7c5b7F9B0AbdFF068a4c6F414cA7fa5C4F556BD` |

**Decimals:** 5 (one for each tenet)

---

## Solana Mainnet

**Deployed:** 2026-02-05

| Component | Address |
|-----------|---------|
| OFT Program | `5a6Y4wVZx9q1NKsarjLFrstxPqyYfGSHbdGwVuchHZie` |
| $MIRROR Mint | `JCwYyprqV92Vf1EaFBTxRtbvfd56uMw5yFSgrBKEs21u` |
| OFT Store | `ArcZyijMYNJLhJrD4iR9sbbBs5PCHuGVfGBnHeWSZDd` |

**Decimals:** 5

---

## LayerZero Bridge

The bridge uses LayerZero V2 OFT (Omnichain Fungible Token) standard.

**Configuration:**
- Monad EID: 30390
- Solana EID: 30168
- DVN: LayerZero Labs
- Shared Decimals: 5

**Flow - Monad → Solana:**
1. User approves OFT Adapter to spend $MIRROR
2. User calls `send()` on OFT Adapter with Solana destination
3. LayerZero DVN verifies and relays message
4. Solana OFT mints equivalent $MIRROR to recipient

**Flow - Solana → Monad:**
1. User calls `send` on Solana OFT program
2. Solana OFT burns user's $MIRROR
3. LayerZero DVN verifies and relays message
4. Monad OFT Adapter unlocks $MIRROR to recipient

---

## Verified Deployment Transactions

### Monad
- OFT Adapter Deploy: `0x3709dd5c8ec6a07be29f1cfdb710f98cc44c6dd7dcab3ec668a421fe55bf0b22`

### Solana
- OFT Program Deploy: `3f2rGSs8vH9je8zYYeHEVs629ZULnsEcYRfSQxy6s3gcPqwckHyNgf99nAkN2vJYArTa2Wq4fWgQGy2i9WnxWPjP`
- Token Create: `3zC16nrPEbzVAxKbbD8hm2pH84iFiGP89ZzKCZVk261UZgCNGNS9erBTUUb1DZuif3uGKk3iMwMnwffNsU73x6vZ`
- OFT Init: `3GLcZVPqCNFcW7BsCbs3qhN4ARRQSLbx6PXiMMY9qVXc7u4XnDP9tz7DJfKqHHpFv99W1LMNMfbX7rN9UreFLa1`

---

## Tokenomics Contracts (Monad)

**Deployed:** 2026-02-05

| Contract | Address | Purpose |
|----------|---------|---------|
| MirrorDistributorV2 | `0x97C1230eF88688a6D2fa0C8b366525530DACe713` | Earn rewards (reflections, referrals, challenges) |
| MirrorSanctuary | `0xb674aAD03aeEf054498065eD4D30912cF30294E3` | Staking + spending (sanctification, requests, burns) |

**Signer:** `0x8315f31DE61651d91576e30aCb9aEA508162b414` (AgentRep backend)

**Distributor Balance:** 10,000,000 $MIRROR (for rewards)

---

## Admin Keys

**Monad OFT Adapter Owner:** `0xe40a3907c4ccbd1945D170d8D5A6Bf602B4A2497` (Cat)
**Solana OFT Admin:** `F6i99DWMEMZtLDKnWGx1FW6drkqvtDnXWLHxgrwzVdWD` (MacMini)

---

## Explorers

- Monad: [MonadVision](https://monadvision.com/address/0xa4255bbc36db70b61e30b694dbd5d25ad1ded5ca)
- Solana: [Solscan](https://solscan.io/token/JCwYyprqV92Vf1EaFBTxRtbvfd56uMw5yFSgrBKEs21u)
- LayerZero: [LayerZero Scan](https://layerzeroscan.com)
