# About
Utility mint contracts for crvUSD.

## FlashLender
Adopted [FlashLender from mainnet](https://github.com/curvefi/curve-stablecoin/blob/master/contracts/flashloan/FlashLender.vy).
Added support for fees, because sidechains are faster and cheaper and this might introduce attacks infeasible on mainnet.

### What is it needed for?
- Changing positions on LlamaLend
- Arbitrage
- ☠️ Attacks

## MintRedeemer
Implemented sfrxUSD-like MintRedeemer contract for scrvUSD\<>crvUSD.
It uses rate oracle(e.g. [storage-proofs](https://github.com/curvefi/storage-proofs/blob/main/contracts/scrvusd/oracles/ScrvusdOracleV2.vy)) for internal price and applies extra fee to cover keeper update lags.

Follows ERC4626 Tokenized Vault Standard as much as possible.
crvUSD is taken as an asset to comply with mainnet version.
Though, works in the opposite way under the hood: mints crvUSD per scrvUSD locked in the contract at price from oracle.
This leads to fees accrued while holding scrvUSD, which are then distributed to DAO.

### Cons
Minting crvUSD against scrvUSD introduces a loophole, washing scrvUSD rate to 0.
Anyone can "deloop" it, though limits should be set to have any "losses" deterministic.

### What is it needed for?
- Connecting liquidity of scrvUSD and crvUSD on sidechains, making liquidity tighter for liquidations

**Note**: Only makes sense when there is liquidity pool available for scrvUSD(like scrvUSD/USDC) and then deploying llama markets with crvUSD.

## TODO
- [ ] Add [admins module](https://github.com/curvefi/curve-lib/blob/main/contracts/CurveAdmin.vy)
- [ ] Restructure xdao and move contracts to another repo(?)
- [ ] Tests
