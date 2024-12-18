// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {DebtTokenBase} from './base/DebtTokenBase.sol';
import {MathUtils} from '../libraries/math/MathUtils.sol';
import {WadRayMath} from '../libraries/math/WadRayMath.sol';
import {IStableDebtToken} from '../../interfaces/IStableDebtToken.sol';
import {ILendingPool} from '../../interfaces/ILendingPool.sol';
import {IAaveIncentivesController} from '../../interfaces/IAaveIncentivesController.sol';
import {Errors} from '../libraries/helpers/Errors.sol';

/**
  StableDebtToken没有缩放概念
  平均固定利率可以看做一系列不同利率的时间加权平均值。
 * @title StableDebtToken
 * @notice Implements a stable debt token to track the borrowing positions of users
 * at stable rate mode
 * @author Aave
 **/
contract StableDebtToken is IStableDebtToken, DebtTokenBase {
  using WadRayMath for uint256;

  uint256 public constant DEBT_TOKEN_REVISION = 0x1;


  /**
  这里所说的 平均利率 = 池子中贷款总利息 / 池子中的贷款总金额. 
  举例来说就是池子中总共有 100$, 用户 A 借了 40$ 利率是 20%, 用户 B 借了 60$ 利率是 30%, 那么 平均利率 = (40 * 20% + 60 * 30%) / 100 = 26%
   */
  // 池子平均利率 即白底书中的：-SRt(-表示英文上面有一个横线)
  uint256 internal _avgStableRate; 


  // 用户上次借款时间
  mapping(address => uint40) internal _timestamps; 

  /**
  是针对用户记录的
  用户平均利率，存的这个值不是池子的当前新贷款使用的借贷利率
  用户的平均利率会用来计算用户当前的债务本息总额，例如 StableDebtToken.balanceOf() 会使用用户的平均利率来计算
   */
  mapping(address => uint256) internal _usersStableRate;
  uint40 internal _totalSupplyTimestamp;

  ILendingPool internal _pool;
  address internal _underlyingAsset;
  IAaveIncentivesController internal _incentivesController;

  /**
   * @dev Initializes the debt token.
   * @param pool The address of the lending pool where this aToken will be used
   * @param underlyingAsset The address of the underlying asset of this aToken (E.g. WETH for aWETH)
   * @param incentivesController The smart contract managing potential incentives distribution
   * @param debtTokenDecimals The decimals of the debtToken, same as the underlying asset's
   * @param debtTokenName The name of the token
   * @param debtTokenSymbol The symbol of the token
   */
  function initialize(
    ILendingPool pool,
    address underlyingAsset,
    IAaveIncentivesController incentivesController,
    uint8 debtTokenDecimals,
    string memory debtTokenName,
    string memory debtTokenSymbol,
    bytes calldata params
  ) public override initializer {
    _setName(debtTokenName);
    _setSymbol(debtTokenSymbol);
    _setDecimals(debtTokenDecimals);

    _pool = pool;
    _underlyingAsset = underlyingAsset;
    _incentivesController = incentivesController;

    emit Initialized(
      underlyingAsset,
      address(pool),
      address(incentivesController),
      debtTokenDecimals,
      debtTokenName,
      debtTokenSymbol,
      params
    );
  }

  /**
   * @dev Gets the revision of the stable debt token implementation
   * @return The debt token implementation revision
   **/
  function getRevision() internal pure virtual override returns (uint256) {
    return DEBT_TOKEN_REVISION;
  }

  /**
   * @dev Returns the average stable rate across all the stable rate debt
   * @return the average stable rate
   **/
  function getAverageStableRate() external view virtual override returns (uint256) {
    return _avgStableRate;
  }

  /**
   * @dev Returns the timestamp of the last user action
   * @return The last update timestamp
   **/
  function getUserLastUpdated(address user) external view virtual override returns (uint40) {
    return _timestamps[user];
  }

  /**
  返回用户的稳定利率（债务的固定利率） 即：获取用户的平均固定利率
   * @dev Returns the stable rate of the user
   * @param user The address of the user
   * @return The stable rate of user
   **/
  function getUserStableRate(address user) external view virtual override returns (uint256) {
    return _usersStableRate[user];
  }

  /**
  stableDebt 也是采用按照复利计算
  返回的是用户债务本息总额 包含利息。(DebtToken 重载后的方法) 
   * @dev Calculates the current user debt balance
   * @return The accumulated debt of the user
   **/
  function balanceOf(address account) public view virtual override returns (uint256) {
    uint256 accountBalance = super.balanceOf(account);
    // 获取用户的平均固定利率
    uint256 stableRate = _usersStableRate[account];
    if (accountBalance == 0) {
      return 0;
    }

    
    /**
    计算每单位debtToken应还款数量 （本息总额）
    cumulatedInterest = (1+rate)^time
    _timestamps[account]：用户上次借款时间
     */
    uint256 cumulatedInterest =
      MathUtils.calculateCompoundedInterest(stableRate, _timestamps[account]);
    // 用户上一次交互产生的债务数量 * 每单位应还款数量 = 债务总额
    return accountBalance.rayMul(cumulatedInterest);
  }

  struct MintLocalVars {
    uint256 previousSupply; // 之前的池子中总的债务本息（包含利息）
    uint256 nextSupply;
    uint256 amountInRay; // 新增数量（单位是ray）
    uint256 newStableRate; // 平均固定利率（用户）
    uint256 currentAvgStableRate;  // 平均固定利率（池子）
  }

  /**
    https://learnblockchain.cn/article/3137
   * @dev Mints debt token to the `onBehalfOf` address.
   * -  Only callable by the LendingPool
   * - The resulting rate is the weighted average between the rate of the new debt
   * and the rate of the previous debt
   * @param user The address receiving the borrowed underlying, being the delegatee in case
   * of credit delegate, or same as `onBehalfOf` otherwise
   * @param onBehalfOf The address receiving the debt tokens
   * @param amount The amount of debt tokens to mint
   * @param rate The rate of the debt being minted
   **/
  function mint(
    address user, // 借贷受益人
    address onBehalfOf, // 借贷还款人
    uint256 amount,// 借贷数量
    uint256 rate // 当前新贷款使用的借贷利率（由利率更新策略模块更新）,其值与流动性利用率U高度相关
  ) external override onlyLendingPool returns (bool) {
    MintLocalVars memory vars;

    // 如果贷款受益人和还款人不同，需要减去还款人对受益人授权的还款额度
    if (user != onBehalfOf) {
      _decreaseBorrowAllowance(onBehalfOf, user, amount);
    }


    /**
    currentBalance：债务本息总额（本金+利息） 就是：balanceOf(user)
    balanceIncrease：按照复利计算，最近一次贷款时间到现在累计的本息
     */
    (, uint256 currentBalance, uint256 balanceIncrease) = _calculateBalanceIncrease(onBehalfOf);

    vars.previousSupply = totalSupply();
    vars.currentAvgStableRate = _avgStableRate;
    // 计算增加后的池子债务总额
    vars.nextSupply = _totalSupply = vars.previousSupply.add(amount);

    /**
    将数量从wad单位转成ray单位
    1 wad = 1e18
    1 ray = 1e27
     */
    vars.amountInRay = amount.wadToRay();


    /**
    这里计算的是针对单个用户
    计算平均固定利率（用户）， 增加后的累计总利息 / 增加后的本金总额
    (usersStableRate * currentBalance + amount * rate) / (currentBalance + amount)
     */
    vars.newStableRate = _usersStableRate[onBehalfOf]
      .rayMul(currentBalance.wadToRay())
      .add(vars.amountInRay.rayMul(rate))
      .rayDiv(currentBalance.add(amount).wadToRay());

    require(vars.newStableRate <= type(uint128).max, Errors.SDT_STABLE_DEBT_OVERFLOW);
    _usersStableRate[onBehalfOf] = vars.newStableRate;

    //solium-disable-next-line 更新用户的最新贷款时间为当前block.timestamp ,池子的_totalSupplyTimestamp也一起更新。
    _totalSupplyTimestamp = _timestamps[onBehalfOf] = uint40(block.timestamp);


    /**
      这里计算整个储备池的平均固定利率
      计算平均固定利率（池子） 即白底书中的：-SRt(英文上面有一个横线)
      计算池子新的平均固定利率
      增加后的累计总利息 / 增加后的本金总额
      (currentAvgStableRate * previousSupply + rate * amount) / (previousSupply + amount)
     */
    // Calculates the updated average stable rate   
    vars.currentAvgStableRate = _avgStableRate = vars
      .currentAvgStableRate
      .rayMul(vars.previousSupply.wadToRay())
      .add(rate.rayMul(vars.amountInRay))
      .rayDiv(vars.nextSupply.wadToRay());

    /**
    通过mint的方式，将(amount+累计的本息)个debt token 转移到用户账户
    mint的数量为：本次借贷数量+按照复利计算，最近一次贷款时间到现在累计的本息（借钱产出的利息）
     */
    _mint(onBehalfOf, amount.add(balanceIncrease), vars.previousSupply);

    emit Transfer(address(0), onBehalfOf, amount);

    emit Mint(
      user,
      onBehalfOf,
      amount,
      currentBalance,
      balanceIncrease,
      vars.newStableRate,
      vars.currentAvgStableRate,
      vars.nextSupply
    );

    return currentBalance == 0;
  }

  /**
   * @dev Burns debt of `user`
   * @param user The address of the user getting his debt burned
   * @param amount The amount of debt tokens getting burned
   **/
  function burn(address user, uint256 amount) external override onlyLendingPool {
    (, uint256 currentBalance, uint256 balanceIncrease) = _calculateBalanceIncrease(user);

    uint256 previousSupply = totalSupply();
    uint256 newAvgStableRate = 0; //池子平均利率
    uint256 nextSupply = 0;
    uint256 userStableRate = _usersStableRate[user];

    // Since the total supply and each single user debt accrue separately,
    // there might be accumulation errors so that the last borrower repaying
    // mght actually try to repay more than the available debt supply.
    // In this case we simply set the total supply and the avg stable rate to 0
    if (previousSupply <= amount) {
      _avgStableRate = 0;
      _totalSupply = 0;
    } else {
      nextSupply = _totalSupply = previousSupply.sub(amount);
      // firstTerm池子的
      uint256 firstTerm = _avgStableRate.rayMul(previousSupply.wadToRay());
      // secondTerm用户的
      uint256 secondTerm = userStableRate.rayMul(amount.wadToRay());

      // For the same reason described above, when the last user is repaying it might
      // happen that user rate * user balance > avg rate * total supply. In that case,
      // we simply set the avg rate to 0
      if (secondTerm >= firstTerm) {
        newAvgStableRate = _avgStableRate = _totalSupply = 0;
      } else {
        newAvgStableRate = _avgStableRate = firstTerm.sub(secondTerm).rayDiv(nextSupply.wadToRay());
      }
    }


    if (amount == currentBalance) {
      // 如果还款数量和债务数量相等，用户债务清零
      _usersStableRate[user] = 0;
      _timestamps[user] = 0;
    } else {
      // 用户仍有债务，更新还款时间
      //solium-disable-next-line
      _timestamps[user] = uint40(block.timestamp);
    }

    // 更新全局的债务总量时间戳
    //solium-disable-next-line
    _totalSupplyTimestamp = uint40(block.timestamp);


    // 可能存在 债务增量 > 还款数量 的情况
    if (balanceIncrease > amount) {
      // 这时反而需要 mint
      uint256 amountToMint = balanceIncrease.sub(amount);
      _mint(user, amountToMint, previousSupply);
      emit Mint(
        user,
        user,
        amountToMint,
        currentBalance,
        balanceIncrease,
        userStableRate,
        newAvgStableRate,
        nextSupply
      );
    } else {
      // 销毁相应的还款数量
      uint256 amountToBurn = amount.sub(balanceIncrease);
      _burn(user, amountToBurn, previousSupply);
      emit Burn(user, amountToBurn, currentBalance, balanceIncrease, newAvgStableRate, nextSupply);
    }

    emit Transfer(user, address(0), amount);
  }

  /**
  
  计算用户债务的增长量，返回 上一次交互的余额，债务本息总额，债务增量(前两者的差)
   * @dev Calculates the increase in balance since the last user interaction
   * @param user The address of the user for which the interest is being accumulated
   * @return The previous principal balance, the new principal balance and the balance increase
   **/
  function _calculateBalanceIncrease(address user)
    internal
    view
    returns (
      uint256,
      uint256,
      uint256
    )
  {

    // 获取用户的债务（上一次交互的债务数量） 用户固定债务stable没有缩放概念。
    // super.balanceOf 是ERC20类的方法
    uint256 previousPrincipalBalance = super.balanceOf(user);
    // 如果没有债务本金，全部返回0
    if (previousPrincipalBalance == 0) {
      return (0, 0, 0);
    }

    /**
    计算自上次累积以来的应计利息 即债务增量(前两者的差) 计算债务自上次累计后的增量
    即按照复利计算，最近一次贷款时间到现在累计的本息
    债务增量 = 债务总额 - 上一次交互的债务数量
     */
    // Calculation of the accrued interest since the last accumulation
    uint256 balanceIncrease = balanceOf(user).sub(previousPrincipalBalance);

    return (
      previousPrincipalBalance, //上期债务余额，即用户上一次交互产生的债务数量
      previousPrincipalBalance.add(balanceIncrease), //  债务本息总额 就是：balanceOf(user)
      balanceIncrease //  债务增量
    );
  }

  /**
  返回池子债务本金（不包含利息），池子债务本息（包含利息），池子平均利率，数据更新时间.
   * @dev Returns the principal and total supply, the average borrow rate and the last supply update timestamp
   **/
  function getSupplyData()
    public
    view
    override
    returns (
      uint256,
      uint256,
      uint256,
      uint40
    )
  {
    uint256 avgRate = _avgStableRate;
    return (super.totalSupply(), _calcTotalSupply(avgRate), avgRate, _totalSupplyTimestamp);
  }

  /**
  返回池子中债务总数量（包含利息）、池子平均利率
   * @dev Returns the the total supply and the average stable rate
   **/
  function getTotalSupplyAndAvgRate() public view override returns (uint256, uint256) {
    uint256 avgRate = _avgStableRate;
    return (_calcTotalSupply(avgRate), avgRate);
  }

  /**
   * @dev Returns the total supply
   **/
  function totalSupply() public view override returns (uint256) {
    return _calcTotalSupply(_avgStableRate);
  }

  /**
   * @dev Returns the timestamp at which the total supply was updated
   **/
  function getTotalSupplyLastUpdated() public view override returns (uint40) {
    return _totalSupplyTimestamp;
  }

  /**
   * @dev Returns the principal debt balance of the user from
   * @param user The user's address
   * @return The debt balance of the user since the last burn/mint action
   **/
  function principalBalanceOf(address user) external view virtual override returns (uint256) {
    return super.balanceOf(user);
  }

  /**
   * @dev Returns the address of the underlying asset of this aToken (E.g. WETH for aWETH)
   **/
  function UNDERLYING_ASSET_ADDRESS() public view returns (address) {
    return _underlyingAsset;
  }

  /**
   * @dev Returns the address of the lending pool where this aToken is used
   **/
  function POOL() public view returns (ILendingPool) {
    return _pool;
  }

  /**
   * @dev Returns the address of the incentives controller contract
   **/
  function getIncentivesController() external view override returns (IAaveIncentivesController) {
    return _getIncentivesController();
  }

  /**
   * @dev For internal usage in the logic of the parent contracts
   **/
  function _getIncentivesController() internal view override returns (IAaveIncentivesController) {
    return _incentivesController;
  }

  /**
   * @dev For internal usage in the logic of the parent contracts
   **/
  function _getUnderlyingAssetAddress() internal view override returns (address) {
    return _underlyingAsset;
  }

  /**
   * @dev For internal usage in the logic of the parent contracts
   **/
  function _getLendingPool() internal view override returns (ILendingPool) {
    return _pool;
  }

  /**
   * 返回池子中总的债务本息（包含利息）
   * @dev Calculates the total supply
   * @param avgRate The average rate at which the total supply increases
   * @return The debt balance of the user since the last burn/mint action
   **/
  function _calcTotalSupply(uint256 avgRate) internal view virtual returns (uint256) {
    uint256 principalSupply = super.totalSupply();

    if (principalSupply == 0) {
      return 0;
    }

    uint256 cumulatedInterest =
      MathUtils.calculateCompoundedInterest(avgRate, _totalSupplyTimestamp);

    return principalSupply.rayMul(cumulatedInterest);
  }

  /**
   * @dev Mints stable debt tokens to an user
   * @param account The account receiving the debt tokens
   * @param amount The amount being minted
   * @param oldTotalSupply the total supply before the minting event
   **/
  function _mint(
    address account,
    uint256 amount,
    uint256 oldTotalSupply
  ) internal {
    // 一个简单的加法
    uint256 oldAccountBalance = _balances[account];
    _balances[account] = oldAccountBalance.add(amount);

    // 若有激励控制合约，则会按持仓额外奖励
    if (address(_incentivesController) != address(0)) {
      _incentivesController.handleAction(account, oldTotalSupply, oldAccountBalance);
    }
  }

  /**
   * @dev Burns stable debt tokens of an user
   * @param account The user getting his debt burned
   * @param amount The amount being burned
   * @param oldTotalSupply The total supply before the burning event
   **/
  function _burn(
    address account,
    uint256 amount,
    uint256 oldTotalSupply
  ) internal {
    uint256 oldAccountBalance = _balances[account];
    _balances[account] = oldAccountBalance.sub(amount, Errors.SDT_BURN_EXCEEDS_BALANCE);

    if (address(_incentivesController) != address(0)) {
      _incentivesController.handleAction(account, oldTotalSupply, oldAccountBalance);
    }
  }
}
