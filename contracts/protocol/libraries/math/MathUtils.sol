// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {SafeMath} from '../../../dependencies/openzeppelin/contracts/SafeMath.sol';
import {WadRayMath} from './WadRayMath.sol';

library MathUtils {
  using SafeMath for uint256;
  using WadRayMath for uint256;

  /// @dev Ignoring leap years
  uint256 internal constant SECONDS_PER_YEAR = 365 days;

  /**
  interest（利息）
    用于使用线性利率公式计算一段时间内累积的利息。
   * @dev Function to calculate the interest accumulated using a linear interest rate formula
   * @param rate The interest rate, in ray  利率，以ray为单位。   利率（rate）：假设年利率为5%，用"ray"单位表示即为0.05 * 1e27 = 5 * 1e25。
   * @param lastUpdateTimestamp The timestamp of the last update of the interest    上次更新利息的时间戳。
   * @return The interest rate linearly accumulated during the timeDelta, in ray   累积的利息，以ray为单位。
   返回值：上次更新时间和当前时间戳之间所经历的时间，以来累积的线性利息。 单位也是ray。 【注意返回值+1,类似于+1】
   (rate.mul(timeDifference) / SECONDS_PER_YEAR).add(WadRayMath.ray()) 相当于： rate年化利率 *（时间差/年） + 1，复利公式中的1+m
   **/

  function calculateLinearInterest(uint256 rate, uint40 lastUpdateTimestamp)
    internal
    view
    returns (uint256)
  {
    // 计算当前区块时间与上次更新时间的时间差。
    //solium-disable-next-line
    uint256 timeDifference = block.timestamp.sub(uint256(lastUpdateTimestamp));

    /**
      使用线性公式 (rate * timeDifference) / SECONDS_PER_YEAR + WadRayMath.ray() 计算累积的利息。
      rate.mul(timeDifference) / SECONDS_PER_YEAR：根据线性公式计算累积的利息部分。
      WadRayMath.ray()：获取1 ray的值，通常用于标准化计算结果。
      (rate.mul(timeDifference) / SECONDS_PER_YEAR).add(WadRayMath.ray())：将累积的利息部分加上1 ray，得到最终的累积利息。
      WadRayMath.ray() 函数返回 1 ray，即 10^27。
     */
    return (rate.mul(timeDifference) / SECONDS_PER_YEAR).add(WadRayMath.ray());
  }

  /**
  这个函数用于计算在一定时间内的复利累积利息。
  由于使用幂运算（指数计算）在区块链上会消耗大量的gas费，该函数采用二项式近似来避免昂贵的幂次运算，从而大幅降低计算成本。
   使用复利计息公式计算利息的函数
   * @dev Function to calculate the interest using a compounded interest rate formula
   计算采用二项式近似法
   * To avoid expensive exponentiation, the calculation is performed using a binomial approximation:
   *二项式近似公式为： 泰勒级数展开
   *  (1+x)^n = 1+n*x+[n/2*(n-1)]*x^2+[n/6*(n-1)*(n-2)*x^3...
   *     n: 表示复利利息的计算次数，这里指的是时间段（以秒为单位）。这里就是exp 
         x: 表示每秒的利率（即单位时间的增长率），它在这里是 ratePerSecond (ratePerSecond计算每秒的利率)
   *
    x 的数值越小时，公式越精确：当x足够小，（远小于1）0.00002，高阶项（x^4,x^5）会变得很小，可以忽略。

   
   * The approximation slightly underpays liquidity providers and undercharges borrowers, with the advantage of great gas cost reductions
   * The whitepaper contains reference to the approximation and a table showing the margin of error per different time periods
   *
   * @param rate The interest rate, in ray
   * @param lastUpdateTimestamp The timestamp of the last update of the interest
   * @return The interest rate compounded during the timeDelta, in ray
  我们只取【二项式近似法】前三项，即到 x 的三次方为止，后面的项由于已经很小，所以可以舍弃，对总体结果影响不大(实际结果略少于理论值)。
  这样就是兼具节省 gas 和准确性的计算方案。

   **/
  function calculateCompoundedInterest(
    uint256 rate,
    uint40 lastUpdateTimestamp,
    uint256 currentTimestamp
  ) internal pure returns (uint256) {

    // exp表示从上次更新时间到当前时间的时间差（以秒为单位）。 是n
    //solium-disable-next-line
    uint256 exp = currentTimestamp.sub(uint256(lastUpdateTimestamp));

    if (exp == 0) {
      return WadRayMath.ray();
    }

    // 公式中的 n-1
    uint256 expMinusOne = exp - 1;
    // 公式中的 n-2
    uint256 expMinusTwo = exp > 2 ? exp - 2 : 0;

    // ratePerSecond计算每秒的利率，即年利率rate除以一年的秒数SECONDS_PER_YEAR，获得每秒利率。  是x    秒化利率
    uint256 ratePerSecond = rate / SECONDS_PER_YEAR;

    /**
    二项式近似公式的依据来源于泰勒级数展开的前几项，它可以用于小数近似，因为当 ∣x∣ 非常小时，高次项对结果的影响较小。
    这里的 ratePerSecond 是一个小数值（通常很小），所以我们可以使用二项式展开前几项的近似结果：
    由于每秒的利率非常小，使用这种近似公式可以得到足够接近的结果，同时节省了大量的计算资源。
     */
     // x的平方
    uint256 basePowerTwo = ratePerSecond.rayMul(ratePerSecond);
    // x的三次方
    uint256 basePowerThree = basePowerTwo.rayMul(ratePerSecond);
    // [n/2*(n-1)]*x^2
    uint256 secondTerm = exp.mul(expMinusOne).mul(basePowerTwo) / 2;
    // [n/6*(n-1)*(n-2)*x^3
    uint256 thirdTerm = exp.mul(expMinusOne).mul(expMinusTwo).mul(basePowerThree) / 6;

    return WadRayMath.ray().add(ratePerSecond.mul(exp)).add(secondTerm).add(thirdTerm);
  }

  /**
   * @dev Calculates the compounded interest between the timestamp of the last update and the current block timestamp
   * @param rate The interest rate (in ray)
   * @param lastUpdateTimestamp The timestamp from which the interest accumulation needs to be calculated
   **/
  function calculateCompoundedInterest(uint256 rate, uint40 lastUpdateTimestamp)
    internal
    view
    returns (uint256)
  {
    return calculateCompoundedInterest(rate, lastUpdateTimestamp, block.timestamp);
  }
}
