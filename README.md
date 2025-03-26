# POOKA Overview

POOKA is an on-chain system composed of several smart contracts and a front-end dApp, all focused on enabling an AI-driven trading strategy around a custom token. It includes:

- **ERC20 Token (POOKA):** Minted at deployment with supply governed by the AI Agent, who acts as the authorized signer.
- **Uniswap V4 Pool:** Pairing POOKA with DAI, where participants can provide liquidity.
- **Uniswap V4 Hook:** Custom logic integrated with the Uniswap pool to manage aspects of fee tiers, trading, and liquidity provisioning.
- **ReactJS dApp:** Facilitates swaps between POOKA and DAI and handles interactions with the AI Agent.

The **POOKA AI Agent** is built on a recurrent Proximal Policy Optimization (PPO) model using an LSTM neural network. This Agent uses the POOKA/DAI pool as its source of liquidity (“trading warchest”), withdrawing DAI to trade on external DEXs and returning profits to the pool. By doing so, it grows the pool’s DAI reserves and consequently raises the value of POOKA (which represents fractional ownership of the pool). The token’s price is determined by the Uniswap invariant (`x * y = k`), reflecting the DAI in reserve relative to the outstanding supply of POOKA. This design combines automated AI-driven market operations with a decentralized liquidity framework.

---

## Explanation

The POOKA token is a unique ERC20 token that maintains a dynamic price based on the DAI reserves in the Uniswap V4 pool using the standard Uniswap `x * y = k` valuation curve. The Hook contract is a Uniswap V4 Hook that allows the owner to adjust the DAI reserves in the pool through fee-free swaps. This mechanism enables the owner to manage both the pool's DAI reserves and the POOKA token's price. In effect, the price action on POOKA is primarily determined by user swaps, while the agent swaps out DAI to secure trading funds and swaps in DAI profits without fees.

---

## Uniswap Trades

### Key Hook Mechanics

#### 1. AMM Integration
- **Price Determination:**  
  ```  
  POOKA_Price = (DAI_Reserves * 10^18) / POOKA_Supply  
  ```
- Maintains Uniswap's `x * y = k` invariant.
- All swaps modify pool reserves normally.

#### 2. Dynamic User Fees

```solidity
// --- Fee Calculation Logic ---
function getUserFee(address user) public view returns (uint24) {
    Position[] storage positions = userPositions[user];

    console.log("User: %s", user);
    console.log("Positions: %d", positions.length);
    // If no positions exist, return the initial fee (or another default value)
    if (positions.length == 0) {
        return uint24(INITIAL_FEE);
    }

    uint256 steps = positions[0].pookaAmount / VOLUME_STEP;
    console.log("Steps: %d", steps);
    console.log("Pooka amount: %d", positions[0].pookaAmount);
    steps = steps > 10 ? 10 : steps; // Max 10 steps

    uint256 feeReduction = steps * FEE_REDUCTION_PER_STEP;
    return
        feeReduction >= INITIAL_FEE
            ? uint24(INITIAL_FEE / 2)
            : uint24(INITIAL_FEE - feeReduction);
}
```

- Limits steps to a maximum of 10 (with 1000 per step, max 10,000 POOKA swapped).
- Caps total fee reduction at 1500 basis points (50% of the initial 0.3% fee).
- Ensures a minimum fee of 0.15%.
- Maintains a linear reduction of 0.015% per 10k POOKA swapped.
- The `afterSwap` hook adjusts the position for each user.

#### 3. Owner Privileges

In addition to executing core swaps without fees, the owner can adjust the pool's DAI reserves directly:

```solidity
function adjustWarchest(...) {
  // Owner can inject/withdraw DAI through fee-free swaps
  _executePrivilegedSwap(...);
}
```

- Owner swaps bypass fees (0% vs. the normal 0.3% fee).
- Large swaps move price significantly with minimal slippage.
- The DAI warchest amount has contract visibility.

#### 4. Price Adjustment Workflow

**Profit Taking:**

```
// Owner adds 1000 DAI to pool
hook.adjustWarchest(poolKey, true, 1000e6);
```

- Increases DAI reserves → POOKA price rises.
- Executes a DAI→POOKA swap with 0% fee.

**Loss Recovery:**

```
// Owner withdraws 500 DAI from pool
hook.adjustWarchest(poolKey, false, 500e6);
```

- Decreases DAI reserves → POOKA price drops.
- Executes a POOKA→DAI swap with 0% fee.

---

### Advantages of This Approach

1. **True AMM Compliance**
   - Maintains the `x * y = k` invariant.
   - Pool liquidity directly impacts pricing.
   - No artificial minting or burning.

2. **Transparent Price Impact**
   - **Before adjustment:**
     - DAI Reserves = 10,000
     - POOKA Supply = 10,000
     - Price = 1.00 DAI
   - **After owner deposits 1,000 DAI:**
     - DAI Reserves = 11,000
     - POOKA Supply = 9,166.66 (via swap)
     - New Price = 11,000 / 9,166.66 ≈ 1.20 DAI (+20%)

3. **Reduced Centralization Risk**
   - Price changes require actual capital movement.
   - The owner cannot arbitrarily set prices.
   - All adjustments are visible on-chain.