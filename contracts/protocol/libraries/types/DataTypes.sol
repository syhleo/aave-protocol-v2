// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

/**
 资金利用率 = 总债务 / 总储蓄
 总债务 等于 浮动利率债务 与 稳定利率债务 之和
借贷需求旺盛时，借贷利率随着资金利用率上升；借贷需求萎靡时，借贷利率随着资金利用率下降

 */



library DataTypes {
  // refer to the whitepaper, section 1.1 basic concepts for a formal description of these properties.
  struct ReserveData {
    //stores the reserve configuration 资产的设置，以 bitmap 形式存储，即用一个 unit256 位数字存储，不同位数对应不同的配置。
    ReserveConfigurationMap configuration;

    /**
    liquidity cumulative index  每单位 liquidity (用户往协议中注入的抵押资产)累计的本息总额。
    即每单位流动性的本息（本金+利息）总额
     */
    //the liquidity index. Expressed in ray        其实就是LI(t-1)
    uint128 liquidityIndex;

    //variable borrow index. Expressed in ray 计算浮动利率复利的序列索引
    uint128 variableBorrowIndex;


    //the current supply rate. Expressed in ray 当前流动性利率。即当前该代币储备池的总收益率。
    uint128 currentLiquidityRate;
    //the current variable borrow rate. Expressed in ray 当前贷款可变（浮动）利率
    uint128 currentVariableBorrowRate;
    //the current stable borrow rate. Expressed in ray 当前贷款固定利率
    uint128 currentStableBorrowRate; 
    uint40 lastUpdateTimestamp;

    //tokens addresses 存款凭证的合约地址
    address aTokenAddress;
    // 固定贷款债务凭证的合约地址
    address stableDebtTokenAddress;
    // 可变贷款债务凭证的合约地址
    address variableDebtTokenAddress;
    //address of the interest rate strategy 利率模型合约地址
    address interestRateStrategyAddress;
    //the id of the reserve. Represents the position in the list of the active reserves
    uint8 id;
  }

  /**
   * 资产的设置，以 bitmap 形式存储，即用一个 unit256 位数字存储，不同位数对应不同的配置。
   * aave-protocol-v2/contracts/protocol/libraries/configuration/ReserveConfiguration.sol
   * 关注这种写法 ？ reserve.configuration.getDecimals()
   */
  struct ReserveConfigurationMap {
    //bit 0-15: LTV
    //bit 16-31: Liq. threshold
    //bit 32-47: Liq. bonus
    //bit 48-55: Decimals
    //bit 56: Reserve is active
    //bit 57: reserve is frozen
    //bit 58: borrowing is enabled
    //bit 59: stable rate borrowing enabled
    //bit 60-63: reserved
    //bit 64-79: reserve factor
    uint256 data;
  }

  /**
  用户相关的配置，和上述形式相同。
  aave-protocol-v2/contracts/protocol/libraries/configuration/UserConfiguration.sol
  mapping(address => DataTypes.UserConfigurationMap) internal _usersConfig;
  _usersConfig[onBehalfOf].setUsingAsCollateral(reserve.id, true);
   */
  struct UserConfigurationMap {
    uint256 data;
  }
  
  // 资产的计息类型
  enum InterestRateMode {NONE, STABLE, VARIABLE}
}
