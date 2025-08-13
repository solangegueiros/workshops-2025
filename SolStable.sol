// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";

contract SolStable is ERC20, AutomationCompatibleInterface {
    AggregatorV3Interface public priceFeed;

    uint256 public constant COLLATERAL_RATIO = 150; // 150%
    uint256 public constant DATAFEED_PRICE_DECIMALS = 8;
    uint256 public constant DECIMALS_FACTOR = 100; // 2 decimals

    address public liquidationAddress;

    //User Positions
    struct Position {
        uint256 collateralETH;
        uint256 stablecoinDebt; // in 2 decimals (e.g., $100 = 100)
    }
    mapping(address => Position) public positions;
    address[] public users;
    mapping(address => bool) private userExists;

    event Deposit(address indexed user, uint256 ethAmount, uint256 mintAmount);
    event Burn(address indexed user, uint256 burnAmount, uint256 ethReturned);
    event Liquidated(address indexed user, uint256 collateralSeized);    

    constructor() ERC20("Sol Stable", "SOLST") {
        /**
        * Network: Ethereum Sepolia
        * Aggregator: ETH/USD
        * Other Data Feeds: https://docs.chain.link/data-feeds/price-feeds/addresses
        */        
        address _priceFeedAddress = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
        priceFeed = AggregatorV3Interface(_priceFeedAddress);

        address _liquidationAddress = msg.sender;
        liquidationAddress = _liquidationAddress;
    }

    function decimals() public pure override returns (uint8) {
        return 2;
    }

    function estimateMintAmount(uint256 ethAmount) public view returns (uint256) {
        uint256 ethPrice = getLatestPrice();
        uint256 DECIMALS = 10 ** uint256(decimals());
        uint256 ethValueInUSD = (ethAmount * ethPrice * DECIMALS) / 1e8 / 1e18;
        return ethValueInUSD * 100 / COLLATERAL_RATIO;
    }

    // 🏦 Deposit ETH and mint SOLST
    function depositAndMint() external payable {
        require(msg.value > 0, "Must deposit ETH");

        uint256 mintAmount = estimateMintAmount(msg.value);
        _mint(msg.sender, mintAmount);

        if (positions[msg.sender].collateralETH == 0) {
            if (!userExists[msg.sender]) {
                users.push(msg.sender);
                userExists[msg.sender] = true;
            }
        }

        positions[msg.sender].collateralETH += msg.value;
        positions[msg.sender].stablecoinDebt += mintAmount;
        emit Deposit(msg.sender, msg.value, mintAmount);
    }

    function estimateWithdrawETH(uint256 burnAmount) public view returns (uint256) {
        require(burnAmount > 0, "Amount must be greater than 0");
        uint256 ethPrice = getLatestPrice();

        // Convert burnAmount (2 decimals) into full USD (18 decimals)
        uint256 burnUSD = (burnAmount * 1e18) / DECIMALS_FACTOR;

        // Apply collateral ratio of 150% (multiply by 150, divide by 100)
        uint256 collateralUSD = (burnUSD * COLLATERAL_RATIO) / 100;

        // Convert USD to ETH: ETH = (USD * 1e8) / priceFeed (with 8 decimals)
        uint256 ethToReturn = (collateralUSD * 1e8) / ethPrice;
        return ethToReturn;
    }

    // 🔁 Burn SOLST and withdraw ETH
    function burnAndWithdraw(uint256 burnAmount) external {
        require(balanceOf(msg.sender) >= burnAmount, "Insufficient SOLST");

        uint256 ethToReturn = estimateWithdrawETH(burnAmount);

        //uint256 usdValue = (burnAmount * COLLATERAL_RATIO) / DECIMALS_FACTOR;
        require(positions[msg.sender].collateralETH >= ethToReturn, "Not enough collateral");

        positions[msg.sender].collateralETH -= ethToReturn;
        positions[msg.sender].stablecoinDebt -= burnAmount;
        _burn(msg.sender, burnAmount);

        payable(msg.sender).transfer(ethToReturn);
        emit Burn(msg.sender, burnAmount, ethToReturn);
    }

    // 📉 Chainlink Oracle
    function getLatestPrice() public view returns (uint256) {
        (, int price,,,) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price");
        return uint256(price); // 8 decimals
    }

    // 🧮 Get user collateral in USD
    function getUserCollateralUSD(address user) public view returns (uint256) {
        uint256 ethPrice = getLatestPrice();
        Position memory pos = positions[user];

        uint256 DECIMALS = 10 ** uint256(decimals());
        uint256 collateralUSD = (pos.collateralETH * ethPrice * DECIMALS) / 1e8 / 1e18;
        return collateralUSD;
    }

    // 🔍 Calculate user's collateral ratio
    function getCollateralRatio(address user) public view returns (uint256) {
        Position memory pos = positions[user];
        if (pos.stablecoinDebt == 0) return type(uint256).max;

        uint256 collateralUSD = getUserCollateralUSD(user);

        //uint256 collateralUSD = (pos.collateralETH * ethPrice) / 1e8;
        //return (collateralUSD * DECIMALS_FACTOR) / pos.stablecoinDebt;
        return collateralUSD / pos.stablecoinDebt;
    }

    // ⚙️ Chainlink Automation: Check for undercollateralized users
    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory performData) {
        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            if (getCollateralRatio(user) < COLLATERAL_RATIO) {
                upkeepNeeded = true;
                performData = abi.encode(user);
                return (true, performData);
            }
        }
        return (false, bytes(""));
    }

    // 🔨 Liquidate undercollateralized user
    function performUpkeep(bytes calldata performData) external override {
        address user = abi.decode(performData, (address));
        require(getCollateralRatio(user) < COLLATERAL_RATIO, "User not liquidatable");

        Position memory positionUser = positions[user];
        _burn(user, positionUser.stablecoinDebt);

        uint256 collateralETH = positions[user].collateralETH;        
        positions[user].collateralETH = 0;
        positions[user].stablecoinDebt = 0;
        payable(liquidationAddress).transfer(collateralETH);
        emit Liquidated(user, collateralETH);
    }


    // 🔧 Get all users (for testing/debugging)
    function getUsers() external view returns (address[] memory) {
        return users;
    }
    // Allow contract to receive ETH
    receive() external payable {}
   
}
