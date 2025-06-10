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
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        uint lpAmount;
        lpToken.totalSupply() == 0 ? lpAmount = amount : lpAmount = amount * lpToken.totalSupply() / usdc.balanceOf(address(this));
        lpToken.mint(msg.sender, lpAmount);
    }

    function depositCollateral(uint amount) external {
        wHYPE.safeTransferFrom(msg.sender, address(this), amount);
        Account storage account = accounts[msg.sender];
        if (account.lastInterestAccrual == 0) { account.lastInterestAccrual = block.timestamp; }
        account.collateral += amount; totalCollateral += amount;
    }

    function takeLoan(uint amount) external {
        updateInterest(msg.sender);
        Account storage account = accounts[msg.sender];
        account.debt += amount; totalDebt += amount;
        require(checkHealth(msg.sender));
        usdc.safeTransfer(msg.sender, amount);
    }

    function payback(uint amount) external {
        updateInterest(msg.sender);
        Account storage account = accounts[msg.sender];
        uint paybackAmount = amount > account.debt ? account.debt : amount;
        account.debt -= paybackAmount; totalDebt -= paybackAmount;
        usdc.safeTransferFrom(msg.sender, address(this), paybackAmount);
    }

    function redeem(uint amount) external {
        uint totalUsdc = usdc.balanceOf(address(this));
        uint usdcAmount = amount * totalUsdc / lpToken.totalSupply();
        lpToken.burn(msg.sender, amount); usdc.safeTransfer(msg.sender, usdcAmount);
    }

    function removeCollateral(uint amount) external {
        updateInterest(msg.sender);
        accounts[msg.sender].collateral -= amount; totalCollateral -= amount;
        require(checkHealth(msg.sender));
        wHYPE.safeTransfer(msg.sender, amount);
    }

    function liquidatePosition(address borrower) external {
        updateInterest(borrower);
        require(!checkHealth(borrower));
        Account storage account = accounts[borrower];
        uint debt = account.debt;
        uint seizedHYPE = debt * 1e18 / (priceOracle.latestAnswer() * 1e10);
        account.collateral = 0; account.debt = 0; totalCollateral -= seizedHYPE; totalDebt -= debt;
        wHYPE.safeTransfer(msg.sender, seizedHYPE); usdc.safeTransferFrom(msg.sender, address(this), debt);
    }

    function checkHealth(address user) public view returns (bool) {
        Account storage account = accounts[user];
        uint collateralValue = account.collateral * (priceOracle.latestAnswer() * 1e10) / 1e18;
        uint maxBorrow = collateralValue * LTV / 100;
        uint debtWithInterest = account.debt + calculateInterest(account);
        return debtWithInterest <= maxBorrow;
    }

    function calculateInterest(Account storage account) internal view returns (uint) {
        uint timeElapsed = block.timestamp - account.lastInterestAccrual;
        return account.debt * INTEREST_RATE * timeElapsed / 365 days / 100;
    }

    function updateInterest(address user) internal {
        Account storage account = accounts[user];
        uint interest = calculateInterest(account);
        account.debt += interest; totalDebt += interest; account.lastInterestAccrual = block.timestamp;
    }
}

contract LPToken is ERC20("LwHYPE", "LwHYPE", 18) {
    address public pool;
    constructor(address _pool) { pool = _pool; }
    modifier onlyPool() { require(pool == msg.sender); _; }
    function mint(address to, uint amount) public onlyPool { _mint(to, amount); }
    function burn(address from, uint amount) public onlyPool { _burn(from, amount); }
}