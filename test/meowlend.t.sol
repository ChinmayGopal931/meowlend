// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console2} from "forge-std/Test.sol";
import {MeowLend, LPToken} from "../src/MeowLend.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";

// Mock Tokens
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol, 18) {}
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Mock Price Oracle
contract MockPriceOracle {
    uint256 public price = 100e8; // $100 with 8 decimals
    
    function latestAnswer() external view returns (uint256) {
        return price;
    }
    
    function setPrice(uint256 _price) external {
        price = _price;
    }
}

contract MeowLendTest is Test {
    MeowLend public meowLend;
    LPToken public lpToken;
    MockERC20 public usdc;
    MockERC20 public wHYPE;
    MockPriceOracle public priceOracle;
    
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    address public liquidator = address(0x4);
    
    uint256 constant INITIAL_BALANCE = 1000000e18;
    uint256 constant DEPOSIT_AMOUNT = 10000e18;
    uint256 constant COLLATERAL_AMOUNT = 100e18;
    
    event Transfer(address indexed from, address indexed to, uint256 amount);
    
    function setUp() public {
        // Deploy mocks
        usdc = new MockERC20("USDC", "USDC");
        wHYPE = new MockERC20("Wrapped HYPE", "wHYPE");
        priceOracle = new MockPriceOracle();
        
        // Deploy MeowLend
        meowLend = new MeowLend(address(usdc), address(wHYPE), address(priceOracle));
        lpToken = meowLend.lpToken();
        
        // Mint tokens to test users
        usdc.mint(alice, INITIAL_BALANCE);
        usdc.mint(bob, INITIAL_BALANCE);
        usdc.mint(charlie, INITIAL_BALANCE);
        usdc.mint(liquidator, INITIAL_BALANCE);
        
        wHYPE.mint(alice, INITIAL_BALANCE);
        wHYPE.mint(bob, INITIAL_BALANCE);
        wHYPE.mint(charlie, INITIAL_BALANCE);
        
        // Approve MeowLend
        vm.prank(alice);
        usdc.approve(address(meowLend), type(uint256).max);
        vm.prank(alice);
        wHYPE.approve(address(meowLend), type(uint256).max);
        
        vm.prank(bob);
        usdc.approve(address(meowLend), type(uint256).max);
        vm.prank(bob);
        wHYPE.approve(address(meowLend), type(uint256).max);
        
        vm.prank(charlie);
        usdc.approve(address(meowLend), type(uint256).max);
        vm.prank(charlie);
        wHYPE.approve(address(meowLend), type(uint256).max);
        
        vm.prank(liquidator);
        usdc.approve(address(meowLend), type(uint256).max);
    }
    
    // ============ Deposit Tests ============
    
    function test_Deposit() public {
        vm.prank(alice);
        meowLend.deposit(DEPOSIT_AMOUNT);
        
        assertEq(lpToken.balanceOf(alice), DEPOSIT_AMOUNT);
        assertEq(usdc.balanceOf(address(meowLend)), DEPOSIT_AMOUNT);
        assertEq(lpToken.totalSupply(), DEPOSIT_AMOUNT);
    }
    
    function test_DepositMultipleUsers() public {
        // Alice deposits first
        vm.prank(alice);
        meowLend.deposit(DEPOSIT_AMOUNT);
        
        // Bob deposits same amount - since no interest accrued, should get same LP tokens
        vm.prank(bob);
        meowLend.deposit(DEPOSIT_AMOUNT);
        
        assertEq(lpToken.balanceOf(alice), DEPOSIT_AMOUNT);
        assertEq(lpToken.balanceOf(bob), DEPOSIT_AMOUNT);
        assertEq(lpToken.totalSupply(), DEPOSIT_AMOUNT * 2);
    }
    
    function test_DepositCorrectLPCalculation() public {
        // Alice deposits first
        vm.prank(alice);
        meowLend.deposit(DEPOSIT_AMOUNT);
        
        // Simulate interest accrual by directly sending USDC
        usdc.mint(address(meowLend), DEPOSIT_AMOUNT); // Double the USDC in pool
        
        // Bob deposits - should get half the LP tokens Alice got
        // LP calculation: amount * totalSupply / poolBalance
        // 10000e18 * 10000e18 / 20000e18 = 5000e18
        vm.prank(bob);
        meowLend.deposit(DEPOSIT_AMOUNT);
        
        assertEq(lpToken.balanceOf(bob), DEPOSIT_AMOUNT / 2);
    }
    
    function testFuzz_Deposit(uint256 amount) public {
        vm.assume(amount > 0 && amount <= INITIAL_BALANCE);
        
        vm.prank(alice);
        meowLend.deposit(amount);
        
        assertEq(lpToken.balanceOf(alice), amount);
        assertEq(usdc.balanceOf(address(meowLend)), amount);
    }
    
    // ============ Deposit Collateral Tests ============
    
    function test_DepositCollateral() public {
        vm.prank(alice);
        meowLend.depositCollateral(COLLATERAL_AMOUNT);
        
        (uint256 lastInterest, uint256 collateral, , uint256 debt) = meowLend.accounts(alice);
        
        assertEq(collateral, COLLATERAL_AMOUNT);
        assertEq(debt, 0);
        assertEq(lastInterest, block.timestamp);
        assertEq(meowLend.totalCollateral(), COLLATERAL_AMOUNT);
    }
    
    function test_DepositCollateralMultipleTimes() public {
        vm.startPrank(alice);
        meowLend.depositCollateral(COLLATERAL_AMOUNT);
        meowLend.depositCollateral(COLLATERAL_AMOUNT);
        vm.stopPrank();
        
        (, uint256 collateral, , ) = meowLend.accounts(alice);
        assertEq(collateral, COLLATERAL_AMOUNT * 2);
    }
    
    // ============ Take Loan Tests ============
    
    function test_TakeLoan() public {
        // Setup liquidity pool
        vm.prank(bob);
        meowLend.deposit(DEPOSIT_AMOUNT);
        
        // Alice deposits collateral
        vm.prank(alice);
        meowLend.depositCollateral(COLLATERAL_AMOUNT);
        
        // Calculate max loan (75% LTV of $100 * 100 wHYPE)
        // Price: 100e8 (8 decimals), Collateral: 100e18
        // Collateral value = 100e18 * 100e8 / 1e8 = 10000e18
        // Max loan = 10000e18 * 75 / 100 = 7500e18
        uint256 maxLoan = 7500e18;
        
        vm.prank(alice);
        meowLend.takeLoan(maxLoan);
        
        (, , , uint256 debt) = meowLend.accounts(alice);
        assertEq(debt, maxLoan);
        assertEq(meowLend.totalDebt(), maxLoan);
    }
    
    function test_TakeLoanRevertsOverLTV() public {
        // Setup liquidity pool
        vm.prank(bob);
        meowLend.deposit(DEPOSIT_AMOUNT);
        
        // Alice deposits collateral
        vm.prank(alice);
        meowLend.depositCollateral(COLLATERAL_AMOUNT);
        
        // Try to take more than 75% LTV
        // Max loan = 7500e18, try to take 7600e18
        uint256 tooMuchLoan = 7600e18;
        
        vm.prank(alice);
        vm.expectRevert("Position would be unhealthy");
        meowLend.takeLoan(tooMuchLoan);
    }
    
    function test_TakeLoanAccruesInterest() public {
        // Setup
        vm.prank(bob);
        meowLend.deposit(DEPOSIT_AMOUNT);
        
        vm.prank(alice);
        meowLend.depositCollateral(COLLATERAL_AMOUNT);
        
        uint256 loanAmount = 1000e18;
        vm.prank(alice);
        meowLend.takeLoan(loanAmount);
        
        // Fast forward 1 year
        vm.warp(block.timestamp + 365 days);
        
        // Take another small loan to trigger interest update
        vm.prank(alice);
        meowLend.takeLoan(1e18);
        
        (, , , uint256 debt) = meowLend.accounts(alice);
        // Debt should be original + 5% annual interest + new loan
        uint256 expectedDebt = loanAmount + (loanAmount * 5 / 100) + 1e18;
        assertEq(debt, expectedDebt);
    }
    
    // ============ Payback Tests ============
    
    function test_Payback() public {
        // Setup loan
        vm.prank(bob);
        meowLend.deposit(DEPOSIT_AMOUNT);
        
        vm.prank(alice);
        meowLend.depositCollateral(COLLATERAL_AMOUNT);
        
        uint256 loanAmount = 1000e18;
        vm.prank(alice);
        meowLend.takeLoan(loanAmount);
        
        // Payback half
        vm.prank(alice);
        meowLend.payback(500e18);
        
        (, , , uint256 debt) = meowLend.accounts(alice);
        assertEq(debt, 500e18);
    }
    
    function test_PaybackMoreThanDebt() public {
        // Setup loan
        vm.prank(bob);
        meowLend.deposit(DEPOSIT_AMOUNT);
        
        vm.prank(alice);
        meowLend.depositCollateral(COLLATERAL_AMOUNT);
        
        uint256 loanAmount = 1000e18;
        vm.prank(alice);
        meowLend.takeLoan(loanAmount);
        
        uint256 aliceBalanceBefore = usdc.balanceOf(alice);
        
        // Try to payback more than debt
        vm.prank(alice);
        meowLend.payback(2000e18);
        
        (, , , uint256 debt) = meowLend.accounts(alice);
        assertEq(debt, 0);
        // Should only transfer actual debt amount
        assertEq(usdc.balanceOf(alice), aliceBalanceBefore - loanAmount);
    }
    
    // ============ Redeem Tests ============
    
    function test_Redeem() public {
        vm.prank(alice);
        meowLend.deposit(DEPOSIT_AMOUNT);
        
        uint256 redeemAmount = DEPOSIT_AMOUNT / 2;
        vm.prank(alice);
        meowLend.redeem(redeemAmount);
        
        assertEq(lpToken.balanceOf(alice), DEPOSIT_AMOUNT / 2);
        assertEq(usdc.balanceOf(alice), INITIAL_BALANCE - DEPOSIT_AMOUNT / 2);
    }
    
    function test_RedeemWithInterest() public {
        // Alice deposits
        vm.prank(alice);
        meowLend.deposit(DEPOSIT_AMOUNT);
        
        // Simulate interest by sending USDC to pool
        usdc.mint(address(meowLend), DEPOSIT_AMOUNT);
        
        // Alice redeems all - should get back double
        vm.prank(alice);
        meowLend.redeem(DEPOSIT_AMOUNT);
        
        assertEq(usdc.balanceOf(alice), INITIAL_BALANCE + DEPOSIT_AMOUNT);
    }
    
    // ============ Remove Collateral Tests ============
    
    function test_RemoveCollateral() public {
        vm.prank(alice);
        meowLend.depositCollateral(COLLATERAL_AMOUNT);
        
        vm.prank(alice);
        meowLend.removeCollateral(COLLATERAL_AMOUNT / 2);
        
        (, uint256 collateral, , ) = meowLend.accounts(alice);
        assertEq(collateral, COLLATERAL_AMOUNT / 2);
    }
    
    function test_RemoveCollateralRevertsUnhealthy() public {
        // Setup loan at max LTV
        vm.prank(bob);
        meowLend.deposit(DEPOSIT_AMOUNT);
        
        vm.prank(alice);
        meowLend.depositCollateral(COLLATERAL_AMOUNT);
        
        uint256 maxLoan = 7500e18;
        vm.prank(alice);
        meowLend.takeLoan(maxLoan);
        
        // Try to remove any collateral - should fail
        vm.prank(alice);
        vm.expectRevert("Position would be unhealthy");
        meowLend.removeCollateral(1);
    }
    
    // ============ Liquidation Tests ============
    
    function test_Liquidation() public {
        // Setup
        vm.prank(bob);
        meowLend.deposit(DEPOSIT_AMOUNT);
        
        vm.prank(alice);
        meowLend.depositCollateral(COLLATERAL_AMOUNT);
        
        // Take loan at 70% LTV
        uint256 loanAmount = 7000e18;
        vm.prank(alice);
        meowLend.takeLoan(loanAmount);
        
        // Drop price to make position unhealthy
        priceOracle.setPrice(50e8); // $50
        
        // Liquidate
        vm.prank(liquidator);
        meowLend.liquidatePosition(alice);
        
        // Check alice's position is cleared
        (, uint256 collateral, , uint256 debt) = meowLend.accounts(alice);
        assertEq(collateral, 0);
        assertEq(debt, 0);
        
        // Check liquidator received all collateral
        assertEq(wHYPE.balanceOf(liquidator), COLLATERAL_AMOUNT);
    }
    
    function test_LiquidationRevertsIfHealthy() public {
        // Setup healthy position
        vm.prank(bob);
        meowLend.deposit(DEPOSIT_AMOUNT);
        
        vm.prank(alice);
        meowLend.depositCollateral(COLLATERAL_AMOUNT);
        
        vm.prank(alice);
        meowLend.takeLoan(1000e18); // Small loan
        
        // Try to liquidate healthy position
        vm.prank(liquidator);
        vm.expectRevert("Position is healthy");
        meowLend.liquidatePosition(alice);
    }
    
    function test_LiquidationWithInterest() public {
        // Setup
        vm.prank(bob);
        meowLend.deposit(DEPOSIT_AMOUNT);
        
        vm.prank(alice);
        meowLend.depositCollateral(COLLATERAL_AMOUNT);
        
        // Take loan at 72% LTV (leaving room for interest)
        uint256 loanAmount = 7200e18;
        vm.prank(alice);
        meowLend.takeLoan(loanAmount);
        
        // Wait for interest to accrue
        vm.warp(block.timestamp + 365 days);
        
        // With 5% annual interest, debt is now 7200 + 360 = 7560
        // At $100 price, this is 75.6% LTV - unhealthy
        
        // Liquidate
        uint256 expectedDebt = loanAmount + (loanAmount * 5 / 100);
        vm.prank(liquidator);
        meowLend.liquidatePosition(alice);
        
        // Verify liquidator paid the right amount
        assertEq(usdc.balanceOf(liquidator), INITIAL_BALANCE - expectedDebt);
    }
    
    // ============ Health Check Tests ============
    
    function test_CheckHealth() public {
        // Alice deposits collateral
        vm.prank(alice);
        meowLend.depositCollateral(COLLATERAL_AMOUNT);
        
        // With no debt, the position should be healthy
        assertTrue(meowLend.checkHealth(alice), "Position should be healthy with no debt");
        
        // Bob provides liquidity to the pool
        vm.prank(bob);
        meowLend.deposit(DEPOSIT_AMOUNT);
        
        // Alice takes a loan at exactly the 75% LTV limit
        // Collateral Value = 100e18 * (100e8 / 1e8) = 10000e18
        // Max Loan = 10000e18 * 75 / 100 = 7500e18
        uint256 maxLoan = 7500e18;
        vm.prank(alice);
        meowLend.takeLoan(maxLoan);
        
        // The position should still be considered healthy at exactly 75% LTV
        assertTrue(meowLend.checkHealth(alice), "Position should be healthy at exactly 75% LTV");
        
        // Now, try to take a loan for just 1 more wei.
        // This should fail because it would push the debt over the LTV limit.
        vm.prank(alice);
        // We expect the contract to revert with the specified error message.
        vm.expectRevert("Position would be unhealthy"); 
        meowLend.takeLoan(1);
    }
    
    // ============ LP Token Tests ============
    
    function test_LPTokenOnlyPool() public {
        vm.expectRevert("Only pool");
        lpToken.mint(alice, 1000e18);
        
        vm.expectRevert("Only pool");
        lpToken.burn(alice, 1000e18);
    }
    
    // ============ Edge Cases and Security Tests ============
    
    function test_DepositZeroReverts() public {
        vm.prank(alice);
        vm.expectRevert("Amount must be greater than 0");
        meowLend.deposit(0);
    }
    
    function test_AllZeroAmountReverts() public {
        // Test deposit collateral
        vm.prank(alice);
        vm.expectRevert("Amount must be greater than 0");
        meowLend.depositCollateral(0);
        
        // Setup for other tests
        vm.prank(bob);
        meowLend.deposit(DEPOSIT_AMOUNT);
        
        vm.prank(alice);
        meowLend.depositCollateral(COLLATERAL_AMOUNT);
        
        // Test take loan
        vm.prank(alice);
        vm.expectRevert("Amount must be greater than 0");
        meowLend.takeLoan(0);
        
        // Take a loan to test payback
        vm.prank(alice);
        meowLend.takeLoan(1000e18);
        
        // Test payback
        vm.prank(alice);
        vm.expectRevert("Amount must be greater than 0");
        meowLend.payback(0);
        
        // Test redeem
        vm.prank(bob);
        vm.expectRevert("Amount must be greater than 0");
        meowLend.redeem(0);
        
        // Test remove collateral
        vm.prank(alice);
        vm.expectRevert("Amount must be greater than 0");
        meowLend.removeCollateral(0);
    }
    
    function test_RedeemMoreThanBalanceReverts() public {
        vm.prank(alice);
        meowLend.deposit(DEPOSIT_AMOUNT);
        
        vm.prank(alice);
        vm.expectRevert();
        meowLend.redeem(DEPOSIT_AMOUNT + 1);
    }
    
    function test_RedeemWithZeroSupplyReverts() public {
        // Try to redeem when no LP tokens exist
        vm.prank(alice);
        vm.expectRevert("No LP tokens to redeem");
        meowLend.redeem(1);
    }
    
    function test_RemoveMoreCollateralThanDepositedReverts() public {
        vm.prank(alice);
        meowLend.depositCollateral(COLLATERAL_AMOUNT);
        
        vm.prank(alice);
        vm.expectRevert("Insufficient collateral");
        meowLend.removeCollateral(COLLATERAL_AMOUNT + 1);
    }
    
function test_PriceManipulationProtection() public {
    // Setup position
    vm.prank(bob);
    // Increase Bob's deposit to ensure enough liquidity for the test
    meowLend.deposit(100000e18); // Increased from 10000e18/50000e18

    // ... (rest of the test logic remains the same)
    vm.prank(alice);
    meowLend.depositCollateral(COLLATERAL_AMOUNT);

    vm.prank(alice);
    meowLend.takeLoan(1000e18);

    // Manipulate price up
    priceOracle.setPrice(1000e8); // $1000

    // Should be able to take more loan
    vm.prank(alice);
    meowLend.takeLoan(50000e18); // This will now succeed
    assertTrue(meowLend.checkHealth(alice));

    // Price drops back
    priceOracle.setPrice(100e8);

    // Now position should be unhealthy
    assertFalse(meowLend.checkHealth(alice));
}
    
    function test_InterestAccrualPrecision() public {
        // Setup
        vm.prank(bob);
        meowLend.deposit(DEPOSIT_AMOUNT);
        
        vm.prank(alice);
        meowLend.depositCollateral(COLLATERAL_AMOUNT);
        
        uint256 loanAmount = 1000e18;
        vm.prank(alice);
        meowLend.takeLoan(loanAmount);
        
        // Record initial state
        (, , , uint256 debtBefore) = meowLend.accounts(alice);
        
        // Fast forward 1 day
        vm.warp(block.timestamp + 1 days);
        
        // Trigger interest update
        vm.prank(alice);
        meowLend.takeLoan(1);
        
        (, , , uint256 debtAfter) = meowLend.accounts(alice);
        
        // Calculate expected interest: 1000 * 5% * 1/365
        uint256 expectedInterest = loanAmount * 5 * 1 days / 365 days / 100;
        assertEq(debtAfter, debtBefore + expectedInterest + 1);
    }
    
    // ============ Integration Tests ============
    
    function test_FullUserFlow() public {
        // Bob provides liquidity
        vm.prank(bob);
        meowLend.deposit(50000e18);
        
        // Alice deposits collateral and takes loan
        vm.startPrank(alice);
        meowLend.depositCollateral(100e18); // $10,000 worth at $100/token
        meowLend.takeLoan(5000e18); // 50% LTV
        vm.stopPrank();
        
        // Time passes
        vm.warp(block.timestamp + 180 days);
        
        // Alice pays back half (interest has accrued)
        vm.prank(alice);
        meowLend.payback(2600e18); // Paying back more than half to account for interest
        
        // Alice removes some collateral
        vm.prank(alice);
        meowLend.removeCollateral(20e18);
        
        // Bob redeems some LP tokens
        vm.prank(bob);
        meowLend.redeem(10000e18);
        
        // Verify final state
        assertTrue(meowLend.checkHealth(alice));
        assertGt(lpToken.totalSupply(), 0);
        assertGt(meowLend.totalDebt(), 0);
    }
}