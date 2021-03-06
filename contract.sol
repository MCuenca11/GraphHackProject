// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";
import "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

// import statement for chainlink price feed
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title The EthBalanceMonitor contract
 * @notice A keeper-compatible contract that monitors and funds eth addresses
 */
contract EthBalanceMonitor is ConfirmedOwner, Pausable, KeeperCompatibleInterface {

    // observed limit of 45K + 10k buffer
    uint256 private constant MIN_GAS_FOR_TRANSFER = 55_000;

    event FundsAdded(uint256 amountAdded, uint256 newBalance, address sender);
    event FundsWithdrawn(uint256 amountWithdrawn, address payee);
    event TopUpSucceeded(address indexed recipient);
    event TopUpFailed(address indexed recipient);
    event KeeperRegistryAddressUpdated(address oldAddress, address newAddress);
    event MinWaitPeriodUpdated(uint256 oldMinWaitPeriod, uint256 newMinWaitPeriod);

    error InvalidWatchList();
    error OnlyKeeperRegistry();
    error DuplicateAddress(address duplicate);

    struct Target {
        bool isActive;
        uint96 minBalanceWei;
        uint96 topUpAmountWei;
        uint56 lastTopUpTimestamp; // enough space for 2 trillion years
    }

    address private s_keeperRegistryAddress;
    uint256 private s_minWaitPeriodSeconds;
    address[] private s_watchList;
    mapping(address => Target) internal s_targets;

    // Struct containing player info  
    struct playerInfo {
        bool isActive;
        uint league;
        uint balance;
        string assetName;
        int predictedAssetPrice;
        uint betAmount;
        int assetLatestPrice;
    }
  
    // Mapping of player addresses to their info stored in a struct
    mapping(address => playerInfo) internal addr2Info;
    // Needed for price feeds from ChainLink
    /**
     * Live Price Feed
    */
    AggregatorV3Interface internal priceFeed;

    /**
    * Mapping for the assets to their oracle addresses
    */
    mapping(string => address) private assetAddresses;

  /**
   * @param keeperRegistryAddress The address of the keeper registry contract
   * @param minWaitPeriodSeconds The minimum wait period for addresses between funding
   */
  constructor(address keeperRegistryAddress, uint256 minWaitPeriodSeconds) ConfirmedOwner(msg.sender) {
    setKeeperRegistryAddress(keeperRegistryAddress);
    setMinWaitPeriodSeconds(minWaitPeriodSeconds);

    //***********************************************
    // If new user update mapping, else nothing?
    //playerInfo memory player = playerInfo({isActive: true, league:2, balance:500, assetName:"", predictedAssetPrice:0, betAmount:0, assetLatestPrice:0});
    playerInfo storage user = addr2Info[msg.sender];
    user.balance = 500;
    user.isActive = true;
    user.league = 2;
    // Chain Link Price feeds set up
    priceFeed = AggregatorV3Interface(address(0));
    assetAddresses["ETH"] = 0x8A753747A1Fa494EC906cE90E9f37563A8AF630e;
    assetAddresses["BTC"] = 0xECe365B379E1dD183B20fc5f022230C044d51404;
    assetAddresses["OIL"] = 0x6292aA9a6650aE14fbf974E5029f36F95a1848Fd;
    assetAddresses["BAT"] = 0x031dB56e01f82f20803059331DC6bEe9b17F7fC9;
    assetAddresses["DAI"] = 0x2bA49Aaa16E6afD2a993473cfB70Fa8559B523cF;
    assetAddresses["LTC"] = 0x4d38a35C2D87976F334c2d2379b535F1D461D9B4;
    assetAddresses["EUR"] = 0x78F9e60608bF48a1155b4B2A5e31F32318a1d85F;
    assetAddresses["LINK"] = 0xd8bD0a1cB028a31AA859A21A3758685a95dE4623;
    assetAddresses["GBP"] = 0x7B17A813eEC55515Fb8F49F2ef51502bC54DD40F;
    assetAddresses["XRP"] = 0xc3E76f41CAbA4aB38F00c7255d4df663DA02A024;
  }

//   /**
//    * @notice Sets the list of addresses to watch and their funding parameters
//    * @param addresses the list of addresses to watch
//    * @param minBalancesWei the minimum balances for each address
//    * @param topUpAmountsWei the amount to top up each address
//    */
//   function setWatchList(
//     address[] calldata addresses,
//     uint96[] calldata minBalancesWei,
//     uint96[] calldata topUpAmountsWei
//   ) external onlyOwner {
//     if (addresses.length != minBalancesWei.length || addresses.length != topUpAmountsWei.length) {
//       revert InvalidWatchList();
//     }
//     address[] memory oldWatchList = s_watchList;
//     for (uint256 idx = 0; idx < oldWatchList.length; idx++) {
//       s_targets[oldWatchList[idx]].isActive = false;
//     }
//     for (uint256 idx = 0; idx < addresses.length; idx++) {
//       if (s_targets[addresses[idx]].isActive) {
//         revert DuplicateAddress(addresses[idx]);
//       }
//       if (addresses[idx] == address(0)) {
//         revert InvalidWatchList();
//       }
//       if (topUpAmountsWei[idx] == 0) {
//         revert InvalidWatchList();
//       }
//       s_targets[addresses[idx]] = Target({
//         isActive: true,
//         minBalanceWei: minBalancesWei[idx],
//         topUpAmountWei: topUpAmountsWei[idx],
//         lastTopUpTimestamp: 0
//       });
//     }
//     s_watchList = addresses;
//   }

//   /**
//    * @notice Gets a list of addresses that are under funded
//    * @return list of addresses that are underfunded
//    */
//   function getUnderfundedAddresses() public view returns (address[] memory) {
//     address[] memory watchList = s_watchList;
//     address[] memory needsFunding = new address[](watchList.length);
//     uint256 count = 0;
//     uint256 minWaitPeriod = s_minWaitPeriodSeconds;
//     uint256 balance = address(this).balance;
//     Target memory target;
//     for (uint256 idx = 0; idx < watchList.length; idx++) {
//       target = s_targets[watchList[idx]];
//       if (
//         target.lastTopUpTimestamp + minWaitPeriod <= block.timestamp &&
//         balance >= target.topUpAmountWei &&
//         watchList[idx].balance < target.minBalanceWei
//       ) {
//         needsFunding[count] = watchList[idx];
//         count++;
//         balance -= target.topUpAmountWei;
//       }
//     }
//     if (count != watchList.length) {
//       assembly {
//         mstore(needsFunding, count)
//       }
//     }
//     return needsFunding;
//   }

//   /**
//    * @notice Send funds to the addresses provided
//    * @param needsFunding the list of addresses to fund (addresses must be pre-approved)
//    */
//   function topUp(address[] memory needsFunding) public whenNotPaused {
//     uint256 minWaitPeriodSeconds = s_minWaitPeriodSeconds;
//     Target memory target;
//     for (uint256 idx = 0; idx < needsFunding.length; idx++) {
//       target = s_targets[needsFunding[idx]];
//       if (
//         target.isActive &&
//         target.lastTopUpTimestamp + minWaitPeriodSeconds <= block.timestamp &&
//         needsFunding[idx].balance < target.minBalanceWei
//       ) {
//         bool success = payable(needsFunding[idx]).send(target.topUpAmountWei);
//         if (success) {
//           s_targets[needsFunding[idx]].lastTopUpTimestamp = uint56(block.timestamp);
//           emit TopUpSucceeded(needsFunding[idx]);
//         } else {
//           emit TopUpFailed(needsFunding[idx]);
//         }
//       }
//       if (gasleft() < MIN_GAS_FOR_TRANSFER) {
//         return;
//       }
//     }
//   }

  /**
   * @notice Get list of addresses that are underfunded and return keeper-compatible payload
   * @return upkeepNeeded signals if upkeep is needed, performData is an abi encoded list of addresses that need funds
   */
  function checkUpkeep(bytes calldata)
    external
    view
    override
    whenNotPaused
    returns (bool upkeepNeeded, bytes memory performData)
  {

    performData;
    upkeepNeeded = false;

    // update player info if they change leagues
    if (addr2Info[msg.sender].league == 3) {
        if (addr2Info[msg.sender].balance < 100) {
            upkeepNeeded = true;
            return (upkeepNeeded, abi.encode(msg.sender, "down"));
        } else if (addr2Info[msg.sender].balance > 300) {
            upkeepNeeded = true;
            return (upkeepNeeded, abi.encode(msg.sender, "up"));
        }    
    } else if (addr2Info[msg.sender].league == 2) {
        if (addr2Info[msg.sender].balance < 300) {
            upkeepNeeded = true;
            return (upkeepNeeded, abi.encode(msg.sender, "down"));
        } else if (addr2Info[msg.sender].balance > 700) {
            upkeepNeeded = true;
            return (upkeepNeeded, abi.encode(msg.sender, "up"));
        }  
    } else if (addr2Info[msg.sender].league == 1) {
        if (addr2Info[msg.sender].balance < 700) {
            upkeepNeeded = true;
            return (upkeepNeeded, abi.encode(msg.sender, "down"));
        }
    // Remain in the same league    
    } else {
        return (upkeepNeeded, performData);
    }
  }

  /**
   * @notice Called by keeper to send funds to underfunded addresses
   * @param performData The abi encoded list of addresses to fund
   */
  function performUpkeep(bytes calldata performData) external override onlyKeeperRegistry whenNotPaused {
    address addr;
    string memory up_down;
    (addr, up_down) = abi.decode(performData, (address, string));

    // Kick the player out if their balance gets too low
    if (keccak256(abi.encodePacked((up_down))) == keccak256(abi.encodePacked(("down"))) && (addr2Info[msg.sender].league == 3)) {
        addr2Info[msg.sender].isActive = false;
    }
    // Update player struct to reflect changed league
    if (keccak256(abi.encodePacked((up_down))) == keccak256(abi.encodePacked(("up")))) {
        addr2Info[msg.sender].league -= 1;
    } else {
        addr2Info[msg.sender].league += 1;
    }
  }


  /**
    struct playerInfo {
        bool isActive;
        uint league;
        uint balance;
        string assetName;
        int predictedAssetPrice;
        uint betAmount;
        int assetLatestPrice;
    }
            address player_address = msg.sender;
        int assetPrice = addr2Info[player_address].assetLatestPrice;
        uint user_league = addr2Info[player_address].league;
        uint user_funds = addr2Info[player_address].balance;
        uint betAmount = addr2Info[player_address].betAmount;
        int prediction = addr2Info[player_address].predictedAssetPrice;
        int predictionDifference = percentDifference(int(prediction), int(assetPrice));
  */


  function getLeague() external view returns (uint current_league) {
    return addr2Info[msg.sender].league;
  }

  function getPlayerDetails() external view returns (bool activity, uint leagues, uint balances, string memory asset, int prediction, uint bet, int assetPrice) {
    return (addr2Info[msg.sender].isActive, addr2Info[msg.sender].league, addr2Info[msg.sender].balance, addr2Info[msg.sender].assetName, addr2Info[msg.sender].predictedAssetPrice, addr2Info[msg.sender].betAmount, addr2Info[msg.sender].assetLatestPrice);
  }
//Strings.toString(myUINT)

  /**
   * @notice Withdraws the contract balance
   * @param amount The amount of eth (in wei) to withdraw
   * @param payee The address to pay
   */
  function withdraw(uint256 amount, address payable payee) external onlyOwner {
    require(payee != address(0));
    emit FundsWithdrawn(amount, payee);
    payee.transfer(amount);
  }

  /**
   * @notice Receive funds
   */
  receive() external payable {
    emit FundsAdded(msg.value, address(this).balance, msg.sender);
  }

  /**
   * @notice Sets the keeper registry address
   */
  function setKeeperRegistryAddress(address keeperRegistryAddress) public onlyOwner {
    require(keeperRegistryAddress != address(0));
    emit KeeperRegistryAddressUpdated(s_keeperRegistryAddress, keeperRegistryAddress);
    s_keeperRegistryAddress = keeperRegistryAddress;
  }

  /**
   * @notice Sets the minimum wait period (in seconds) for addresses between funding
   */
  function setMinWaitPeriodSeconds(uint256 period) public onlyOwner {
    emit MinWaitPeriodUpdated(s_minWaitPeriodSeconds, period);
    s_minWaitPeriodSeconds = period;
  }

  /**
   * @notice Gets the keeper registry address
   */
  function getKeeperRegistryAddress() external view returns (address keeperRegistryAddress) {
    return s_keeperRegistryAddress;
  }

  /**
   * @notice Gets the minimum wait period
   */
  function getMinWaitPeriodSeconds() external view returns (uint256) {
    return s_minWaitPeriodSeconds;
  }

  /**
   * @notice Gets the list of addresses being watched
   */
  function getWatchList() external view returns (address[] memory) {
    return s_watchList;
  }

  /**
   * @notice Gets configuration information for an address on the watchlist
   */
  function getAccountInfo(address targetAddress)
    external
    view
    returns (
      bool isActive,
      uint96 minBalanceWei,
      uint96 topUpAmountWei,
      uint56 lastTopUpTimestamp
    )
  {
    Target memory target = s_targets[targetAddress];
    return (target.isActive, target.minBalanceWei, target.topUpAmountWei, target.lastTopUpTimestamp);
  }

  /**
   * @notice Pauses the contract, which prevents executing performUpkeep
   */
  function pause() external onlyOwner {
    _pause();
  }

  /**
   * @notice Unpauses the contract
   */
  function unpause() external onlyOwner {
    _unpause();
  }

  modifier onlyKeeperRegistry() {
    if (msg.sender != s_keeperRegistryAddress) {
      revert OnlyKeeperRegistry();
    }
    _;
  }

    /**
     *  Places bet
     */
    function placeBet(int _prediction, string calldata _asset, uint _betAmount) public {
        // assign gamblers predicted price, bet, and asset
        addr2Info[msg.sender].predictedAssetPrice = _prediction;
        addr2Info[msg.sender].betAmount = _betAmount;
        addr2Info[msg.sender].assetName = _asset;
        // call function to get latest asset price from chainlink
        addr2Info[msg.sender].assetLatestPrice = getLatestPrice();
    }

    /**
     * Returns the latest price using chainlink oracle
     */
    function getLatestPrice() private returns (int) {
        // grabs the assets addr from the dictionary and passes it to the price feed
        address assetAddr = assetAddresses[addr2Info[msg.sender].assetName];
        priceFeed = AggregatorV3Interface(assetAddr);
        // info needed by chainlink
        (
            uint80 roundID, 
            int price,
            uint startedAt,
            uint timeStamp,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        // converts price to an int
        return price/10**8;
    }
    
    /**
    * finds the absolute value of the truncated percent difference between 2 values
    */
    function percentDifference(int _value1, int _value2) private returns(int) {
        int valuesPercentDifference = ((_value1 - _value2)*100)/(_value2);
        valuesPercentDifference = valuesPercentDifference >= 0 ? valuesPercentDifference : -valuesPercentDifference;
        return valuesPercentDifference;
    }

    /**
    * Calculates prize
    */
    function calculatePrize() private {
        address player_address = msg.sender;
        int assetPrice = addr2Info[player_address].assetLatestPrice;
        uint user_league = addr2Info[player_address].league;
        uint user_funds = addr2Info[player_address].balance;
        uint betAmount = addr2Info[player_address].betAmount;
        int prediction = addr2Info[player_address].predictedAssetPrice;
        int predictionDifference = percentDifference(int(prediction), int(assetPrice));


        if (user_league == 1) {
            require(betAmount >= user_funds/5);
            if (predictionDifference <= 5) {
                user_funds += betAmount*2;
            } else {
                user_funds -= betAmount;
            }
        } else if (user_league == 2) {
            require(betAmount >= user_funds/10);
            if (predictionDifference <= 5) {
                user_funds += betAmount*3/2;
            } else {
                user_funds -= betAmount;
            }
        } else if (user_league == 3) {
            require(betAmount >= user_funds/20);
            if (predictionDifference <= 5) {
                user_funds += betAmount;
            } else {
                user_funds -= betAmount;
            }
        }
        addr2Info[msg.sender].balance = user_funds;
    }
}
