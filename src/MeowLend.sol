// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";

interface PriceOracle { function latestAnswer() external view returns (uint); }

contract MeowLend {
    using SafeTransferLib for ERC20;
    struct Account { uint lastInterestAccrual; uint collateral; uint liquidity; uint debt; }
    uint public constant INTEREST_RATE = 5;
    uint public constant LTV = 75;
    mapping(address => Account) public accounts;
    uint public totalDebt;
    uint public totalCollateral;
    LPToken public lpToken;
    ERC20 public usdc;
    ERC20 public wHYPE;
    PriceOracle public priceOracle;

    constructor(address _usdc, address _wHYPE, address _priceOracle) { 
        usdc = ERC20(_usdc); wHYPE = ERC20(_wHYPE); priceOracle = PriceOracle(_priceOracle); lpToken = new LPToken(address(this));
    }

    function deposit(uint amount) external {
        require(amount > 0, "Amount must be greater than 0"); // FIX: Add zero check
        
        // FIX: Calculate LP amount before transfer to get correct ratio
        uint lpAmount;
        uint totalSupply = lpToken.totalSupply();
        uint poolBalance = usdc.balanceOf(address(this));
        
        if (totalSupply == 0) {
            lpAmount = amount;
        } else {
            // Correct formula: new_shares = deposit * total_shares / pool_balance
            lpAmount = amount * totalSupply / poolBalance;
        }
        
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        lpToken.mint(msg.sender, lpAmount);
    }

    function depositCollateral(uint amount) external {
        require(amount > 0, "Amount must be greater than 0"); // FIX: Add zero check
        wHYPE.safeTransferFrom(msg.sender, address(this), amount);
        Account storage account = accounts[msg.sender];
        if (account.lastInterestAccrual == 0) { account.lastInterestAccrual = block.timestamp; }
        account.collateral += amount; totalCollateral += amount;
    }

    function takeLoan(uint amount) external {
        require(amount > 0, "Amount must be greater than 0"); // FIX: Add zero check
        updateInterest(msg.sender);
        Account storage account = accounts[msg.sender];
        account.debt += amount; totalDebt += amount;
        require(checkHealth(msg.sender), "Position would be unhealthy"); // FIX: Add error message
        usdc.safeTransfer(msg.sender, amount);
    }

    function payback(uint amount) external {
        require(amount > 0, "Amount must be greater than 0"); // FIX: Add zero check
        updateInterest(msg.sender);
        Account storage account = accounts[msg.sender];
        uint paybackAmount = amount > account.debt ? account.debt : amount;
        account.debt -= paybackAmount; totalDebt -= paybackAmount;
        usdc.safeTransferFrom(msg.sender, address(this), paybackAmount);
    }

    function redeem(uint amount) external {
        require(amount > 0, "Amount must be greater than 0"); // FIX: Add zero check
        uint totalUsdc = usdc.balanceOf(address(this));
        uint totalSupply = lpToken.totalSupply();
        require(totalSupply > 0, "No LP tokens to redeem"); // FIX: Prevent division by zero
        uint usdcAmount = amount * totalUsdc / totalSupply;
        lpToken.burn(msg.sender, amount); 
        usdc.safeTransfer(msg.sender, usdcAmount);
    }

    function removeCollateral(uint amount) external {
        require(amount > 0, "Amount must be greater than 0"); // FIX: Add zero check
        updateInterest(msg.sender);
        Account storage account = accounts[msg.sender];
        require(account.collateral >= amount, "Insufficient collateral"); // FIX: Add check
        account.collateral -= amount; 
        totalCollateral -= amount;
        require(checkHealth(msg.sender), "Position would be unhealthy"); // FIX: Add error message
        wHYPE.safeTransfer(msg.sender, amount);
    }

    function liquidatePosition(address borrower) external {
        updateInterest(borrower);
        require(!checkHealth(borrower), "Position is healthy"); // FIX: Add error message
        Account storage account = accounts[borrower];
        uint debt = account.debt;
        require(debt > 0, "No debt to liquidate"); // FIX: Add check
        
        // FIX: Calculate seized collateral properly
        uint collateralValue = account.collateral * priceOracle.latestAnswer() / 1e8; // Price oracle has 8 decimals
        uint seizedHYPE = account.collateral; // Seize all collateral
        
        // FIX: Update totals with actual seized amount
        totalCollateral -= account.collateral;
        totalDebt -= debt;
        
        account.collateral = 0; 
        account.debt = 0; 
        
        wHYPE.safeTransfer(msg.sender, seizedHYPE); 
        usdc.safeTransferFrom(msg.sender, address(this), debt);
    }

    function checkHealth(address user) public view returns (bool) {
        Account storage account = accounts[user];
        if (account.debt == 0) return true; // FIX: No debt = always healthy
        
        // FIX: Correct price calculation (oracle returns price with 8 decimals)
        uint collateralValue = account.collateral * priceOracle.latestAnswer() / 1e8;
        uint maxBorrow = collateralValue * LTV / 100;
        uint debtWithInterest = account.debt + calculateInterest(account);
        return debtWithInterest <= maxBorrow;
    }

    function calculateInterest(Account storage account) internal view returns (uint) {
        if (account.lastInterestAccrual == 0 || account.debt == 0) return 0; // FIX: Add checks
        uint timeElapsed = block.timestamp - account.lastInterestAccrual;
        return account.debt * INTEREST_RATE * timeElapsed / 365 days / 100;
    }

    function updateInterest(address user) internal {
        Account storage account = accounts[user];
        if (account.debt == 0) return; // FIX: Skip if no debt
        uint interest = calculateInterest(account);
        account.debt += interest; 
        totalDebt += interest; 
        account.lastInterestAccrual = block.timestamp;
    }
}

contract LPToken is ERC20("LwHYPE", "LwHYPE", 18) {
    address public pool;
    constructor(address _pool) { pool = _pool; }
    modifier onlyPool() { require(pool == msg.sender, "Only pool"); _; }
    function mint(address to, uint amount) public onlyPool { _mint(to, amount); }
    function burn(address from, uint amount) public onlyPool { _burn(from, amount); }
}