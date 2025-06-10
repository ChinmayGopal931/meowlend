# LendingPool Protocol

A decentralized lending protocol built on hyperEVM that enables users to supply USDC liquidity, borrow against wHYPE collateral, and earn interest.

## Overview

LendingPool is a collateralized lending protocol where:
- Liquidity providers deposit USDC to earn yield
- Borrowers deposit wHYPE as collateral to borrow USDC
- Interest accrues continuously at 5% APR
- Positions are liquidatable when health factor drops below 75% LTV

## Features

- **Supply & Earn**: Deposit USDC to mint LP tokens and earn from borrower interest
- **Collateralized Borrowing**: Use wHYPE as collateral with 75% loan-to-value ratio
- **Automatic Interest Accrual**: 5% annual interest rate calculated per second
- **Liquidations**: Unhealthy positions can be liquidated by anyone
- **LP Token System**: Proportional share tokens representing pool ownership

## Installation

### Prerequisites

- [Foundry](https://getfoundry.sh/)
- [Git](https://git-scm.com/)



### Dependencies

```bash
forge install transmissions11/solmate
```

## Building

```bash
forge build
```

## Testing

```bash
# Run all tests
forge test

# Run tests with gas reporting
forge test --gas-report

# Run tests with verbosity
forge test -vvvv

# Run specific test
forge test --match-test testDeposit
```

## Deployment

### Local Deployment

```bash
# Start local node
anvil

# Deploy
forge script script/Deploy.s.sol:DeployScript --rpc-url http://localhost:8545 --private-key $PRIVATE_KEY --broadcast
```

### hyperEVM Deployment

```bash
# Set environment variables
export RPC_URL=<YOUR_HYPEREVM_RPC>
export PRIVATE_KEY=<YOUR_PRIVATE_KEY>
export ETHERSCAN_API_KEY=<YOUR_API_KEY>

# Deploy and verify
forge script script/Deploy.s.sol:DeployScript --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast --verify
```


## Usage

### For Liquidity Providers

```solidity
// Approve USDC
usdc.approve(address(lendingPool), amount);

// Deposit USDC
lendingPool.deposit(amount);

// Redeem LP tokens for USDC
lendingPool.redeem(lpTokenAmount);
```

### For Borrowers

```solidity
// Approve and deposit wHYPE collateral
wHYPE.approve(address(lendingPool), collateralAmount);
lendingPool.depositCollateral(collateralAmount);

// Borrow USDC (up to 75% of collateral value)
lendingPool.takeLoan(borrowAmount);

// Repay loan
usdc.approve(address(lendingPool), repayAmount);
lendingPool.payback(repayAmount);

// Withdraw collateral (if healthy)
lendingPool.removeCollateral(amount);
```

### For Liquidators

```solidity
// Check if position is liquidatable
bool isHealthy = lendingPool.checkHealth(borrower);

// Liquidate unhealthy position
if (!isHealthy) {
    usdc.approve(address(lendingPool), debtAmount);
    lendingPool.liquidatePosition(borrower);
}
```


### Running Locally

```bash
# Run local fork
forge script script/Interact.s.sol:InteractScript --fork-url $RPC_URL

# Generate coverage report
forge coverage --report lcov

# Generate documentation
forge doc
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Built with [Foundry](https://github.com/foundry-rs/foundry)
- Using [Solmate](https://github.com/transmissions11/solmate) for optimized contracts
- Deployed on [hyperEVM](https://hyperliquid.xyz)

# meowlend
# meowlend
