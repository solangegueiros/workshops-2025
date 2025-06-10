// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// Deploy this contract on Ronin Saigon
// Or get other Data Feeds: https://docs.chain.link/data-feeds/price-feeds/addresses

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface TokenInterface {
    function allowance(address owner, address spender) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function decimals() external view returns (uint8);
    function transfer(address to, uint256 value) external returns (bool);    
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}


contract SimpleLending is Ownable {
    AggregatorV3Interface public priceFeed;
    TokenInterface public stablecoin;

    uint256 public constant COLLATERAL_RATIO = 150; // 150%
    uint256 constant DATAFEED_PRICE_DECIMALS = 8;
    uint8 public tokenDecimals;

    mapping(address => uint256) public collateralNative;
    mapping(address => uint256) public debtStableCoin;

    constructor(address _stablecoin) Ownable(msg.sender){
        /**
        * Network: Ronin Saigon
        * Aggregator: RON/USD
        * Other Data Feeds: https://docs.chain.link/data-feeds/price-feeds/addresses
        */
        address _priceFeedAddress = 0xBaA0AfA2f390349e0074bE787509a098e3044fc8;
        priceFeed = AggregatorV3Interface(_priceFeedAddress);

        stablecoin = TokenInterface(_stablecoin);
        tokenDecimals = stablecoin.decimals();
    }

    /// @notice Deposit Native token as collateral
    function depositCollateral() external payable {
        require(msg.value > 0, "Must send Native Token");
        collateralNative[msg.sender] += msg.value;
    }

    /// @notice Borrow stablecoin against Collateral
    function borrow(uint256 amountStableCoin) external {
        require(collateralNative[msg.sender] >= minimumCollateral(amountStableCoin), "Insufficient collateral");

        debtStableCoin[msg.sender] += amountStableCoin;
        require(stablecoin.transfer(msg.sender, amountStableCoin), "Transfer failed");
    }

    /// @notice Repay loan
    function repay(uint256 amountStableCoin) external {
        require(debtStableCoin[msg.sender] >= amountStableCoin, "Too much repayment");

        debtStableCoin[msg.sender] -= amountStableCoin;
        require(stablecoin.transferFrom(msg.sender, address(this), amountStableCoin), "Transfer failed");
    }

    /// @notice Withdraw Collateral (only if loan is repaid)
    function withdrawCollateral(uint256 amount) external {
        require(debtStableCoin[msg.sender] == 0, "Pay all debt first");
        require(collateralNative[msg.sender] >= amount, "Not enough collateral");

        collateralNative[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
    }

    /// @notice Calculate the minimum native tokens as collateral to borrow the amount
    function minimumCollateral(uint256 amountStableCoin) public view returns (uint256) {
        uint256 ethPrice = getLatestPrice();

        //amountStableCoin in native token
        uint256 decimalsAdjustment = 10 ** (DATAFEED_PRICE_DECIMALS - uint256(tokenDecimals));
        uint256 amountNativeToken = (amountStableCoin * decimalsAdjustment) * 1e18 / ethPrice;
        
        uint256 requiredCollateral = (amountNativeToken * COLLATERAL_RATIO) / 100;        
        return requiredCollateral;
    }

    /// @notice Get latest Native Token / USD price from Chainlink Data Feeds
    function getLatestPrice() public view returns (uint256) {
        (, int price,,,) = priceFeed.latestRoundData();
        return uint256(price); // 8 decimals
    }

    // Admin: withdraw stuck tokens
    function rescueTokens(address token, uint256 amount) external onlyOwner {
        TokenInterface(token).transfer(owner(), amount);
    }

    receive() external payable {}
}
