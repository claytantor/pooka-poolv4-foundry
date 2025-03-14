# Introduction
This repository contains the implementation of a simple ERC20 token and a contract that manages swaps between the token and DAI. The token is minted during deployment and can only be minted/burned by the contract managing the swaps. The contract uses Uniswap V4 to facilitate swaps between the token and DAI.

### Explanation
1### Key Mechanics

1. **AMM Integration**:
   ```solidity
   // Price determined by pool reserves
   POOKA_Price = (DAI_Reserves * 10^18) / POOKA_Supply
   ```
   - Maintains Uniswap's `x * y = k` invariant
   - All swaps modify pool reserves normally

2. **Owner Privileges**:
   ```solidity
   function adjustWarchest(...) {
       // Owner can inject/withdraw DAI through fee-free swaps
       _executePrivilegedSwap(...);
   }
   ```
   - Owner swaps bypass fees (`0%` vs normal `0.3%`)
   - Large swaps move price significantly with minimal slippage

3. **Price Adjustment Workflow**:
   - **Profit Taking**:
     ```javascript
     // Owner adds 1000 DAI to pool
     hook.adjustWarchest(poolKey, true, 1000e6);
     ```
     - Increases DAI reserves → POOKA price rises
     - Executes DAI→POOKA swap with 0% fee
   
   - **Loss Recovery**:
     ```javascript
     // Owner withdraws 500 DAI from pool
     hook.adjustWarchest(poolKey, false, 500e6);
     ```
     - Decreases DAI reserves → POOKA price drops
     - Executes POOKA→DAI swap with 0% fee

4. **Normal User Swaps**:
   ```solidity
   function _handleUserSwap(...) {
       return (..., 3000); // 0.3% fee
   }
   ```
   - Regular users pay standard fees
   - Their swaps affect reserves normally

### Advantages Of Approach

1. **True AMM Compliance**:
   - Maintains `x * y = k` invariant
   - Pool liquidity directly impacts pricing
   - No artificial minting/burning

2. **Transparent Price Impact**:
   ```text
   Before adjustment:
   DAI Reserves = 10,000
   POOKA Supply = 10,000
   Price = 1.00 DAI

   After owner deposits 1,000 DAI:
   DAI Reserves = 11,000
   POOKA Supply = 9,166.66 (via swap)
   New Price = 11,000 / 9,166.66 ≈ 1.20 DAI (+20%)
   ```

3. **Reduced Centralization Risk**:
   - Price changes require actual capital movement
   - Owner can't arbitrarily set prices
   - All adjustments visible on-chain

This implementation creates a hybrid system where:
- Regular users interact with a normal Uniswap V4 pool
- The owner can strategically adjust prices through large, privileged swaps
- All price changes are organic results of reserve changes via AMM math

### Usage
1. **Deploy Contracts**:
   - Deploy `POOKA` with the Hook's address.
   - Deploy `PookaValuationHook` with DAI and POOKA addresses.

2. **Create Uniswap V4 Pool**:
   - Use the `PookaValuationHook` address when creating the DAI/POOKA pool.

3. **Swapping**:
   - Users swap DAI for POOKA (minting) or POOKA for DAI (burning) through the pool, with the Hook managing the pricing. The owner can adjust prices by injecting/withdrawing DAI which they can use to make trades.

4. **POOKA Dilution for DAI Trading**:
   - The owner trades the accumulated DAI on external DEXs and updates `externalWarchest` via `adjustWarchest` to reflect profits/losses, dynamically adjusting POOKA's value.

This setup creates a liquidity pool where POOKA's value is directly tied to the owner's DAI balance, functioning as a managed "warchest" with dynamic token valuation.


# Setting up Dependencies
```shell
$ forge install OpenZeppelin/openzeppelin-contracts@5.2.0
$ forge install uniswap/v2-core
$ forge install uniswap/v3-core
$ forge install uniswap/v4-core
$ forge install uniswap/v4-periphery
$ forge install uniswap/universal-router
```

# Test the Contracts
```shell
$ forge test -vvv
```

# Deploying the Contracts via Anvil

rn anvil
```shell
$ anvil
```

1. **Deploy the Uniswap V4 Infra and the DAI Token**:
   ```shell
   forge script script/anvil/0_DeployUniswapV4.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
   forge script script/anvil/1_DeployDai.s.sol --tc DeployDAI --rpc-url http://127.0.0.1:8545 --broadcast


   ```

2. **Deploy the Pooka Token**:
   ```shell
   $ forge script script/0_DeployPooka.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
   ```

3. **Deploy the Pooka Valuation Hook**:
   always run this script if you have had to redeploy the Uniswap V4 infrastructure

   ```shell
   $ forge script script/1_DeployPookaHook.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
   ```

4. **Create the Uniswap V4 Pool (anvil version)**:
   ```shell
   $ forge script script/anvil/3_CreatePoolAndLiquidity.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
   ```

5. **Swap POOKA**:
   ```shell
   $ forge script script/anvil/6_SwapPooka.sol --rpc-url http://127.0.0.1:8545 --broadcast
   ```



