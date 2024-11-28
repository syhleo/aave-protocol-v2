AAVE v2是对AAVE协议的重要升级，主要变化包括：
1、债务Token化：用户债务现在以债务Token形式存在，替代内部记账，简化代码，并允许用户持有代表其债务的Token。这支持借取可变和稳定利率贷款的混合，并引入了信用额度转移功能。

2、信用额度转移与委托：用户可以转移他们在AAVE中获得的信用额度给其他账户，这些账户能直接利用这些额度借贷。信用委托允许用户将信用额度委托给他人或智能合约，增加了灵活性和信任最小化。

3、Flash Loan V2：改进了Flash Loan机制，解决了非重入性问题，使得从AAVE获取的Flash Loan可以再用于AAVE内的操作，提高了资金利用效率和协议的灵活性。

4、治理升级：Aave Governance V2引入了更去中心化的链上治理，任何人都能提交和实施AIP（Aave改进提案），而不仅仅是创始团队。它包括表决权与提案权分离、多种投票策略、多个执行实体和守护者机制，增强了协议的民主性和响应速度。

5、经济模型调整：aToken支持EIP-2612，流动性率计算方式调整，考虑了资金利用率和年化利率，以及累计流动性指数的概念，使经济模型更加精细和动态。

这些变化提升了AAVE协议的效率、安全性和用户体验，同时也加强了其在DeFi领域的竞争力。

LIt：累积流动性指数
LIt = (LRt∆Tyear + 1)LIt−1
LI0 = 1 × 10^27 = 1 ray

NIt:储备金累积的持续利息 (就等于LIt)
NIt = (LRt∆Tyear + 1)LIt−1



Rt:借款利率



在任意时间点，用户的aToken余额可以写为：
aBt(x) = ScBt(x)NIt



LRt ： 如何计算？
VRt:当前的浮动借贷利率.




transfer魔改了，债务没法转移

资金利用率Utilization Rate = (Total borrowed)/(Total supplied) 反映：存的钱，有多少被借了，即借贷池中有多少资金被借出去了。
资金利用率Utilization Rate越高，借贷利率就越高，同时，存款利率也会更高（因为需求多了，鼓励大家存钱，存款利率越高，希望更多的人存钱）
当资金利用率过高时，借贷利率会很高，高利率鼓励大家偿还债务和额外供应（存款）。


利率模型的原理
利率模型是指协议中的总流动性和借款需求之间的关系，Aave 的利率模型使用的是双斜率函数，目的是降低流动性风险的同时兼顾资本利用率，其表现为存贷款利率随着市场供需关系的变化而变化，
比如：
当借款人越来越多的时，存贷款利率都会上升以鼓励人们降低借贷行为
当借款人越来越少的时，存贷款利率都会下降以鼓励人们增加借贷行为
其中决定这些变化的关键指标是【资金利用率U】，即借贷池中有多少资金被借出去了。

资金利用率U 等于 总债务 占 总储蓄 的比例
    获取资金利用率 U = totalDebt / totalLiquidity
    totalLiquidity = 可用流动性 + 总债务（已借出的流动性）
即 Aave 为每个资产都设置了一个最佳利用率的临界点，当【资金利用率】 > 【最佳资金利用率】时，存贷款利息都会呈指数型上升，从而吸引存款及还款行为的发生，降低了流动性风险。
除此之外，Aave 为不同风险偏好的用户提供了【浮动利率】和【固定利率】两种选项，由于固定利率的可预测性，其利率通常比浮动利率要高。
https://mirror.xyz/0xCD99Dfa00c358FD021207eadc4176C74150d606c/D3ZUKa-jzsrtFkr4dJYT0CjOcRvdMfJdnDzPv8TKjeM




variable 类型的债务利率不断随着池子的利用率产生变化，所以每个池子会全局记录一个 variableBorrowIndex 来实时更新债务和缩放数量的比例；
而 stable 类型的债务，对于用户来说，每一笔的债务利率都是固定在当时借贷时刻的，所以只需要以固定利率和时间来计算债务数量；由于用户可能借出多笔不同固定利率的债务，实际计算需要使用加权平均后的固定利率，具体公式在V2白皮书 3.4 Stable Debt












存款利率肯定低于贷款利率。

reserve factor:储备系数

AAVE 是 AAVE 的原生治理 Token，主要用于投票治理以及质押
aave 代币持有者报表：
https://etherscan.io/token/tokenholderchart/0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9



DAI稳定币：
https://app.aave.com/reserve-overview/?underlyingAsset=0x6b175474e89094c44da98b954eedeac495271d0f&marketName=proto_mainnet_v3

WBTC:
https://app.aave.com/reserve-overview/?underlyingAsset=0x2260fac5e5542a773aa44fbcfedf7c193bc2c599&marketName=proto_mainnet_v3






闪电贷/信贷委托  --- 待了解？



参考：
https://web3caff.com/zh/archives/34624
https://learnblockchain.cn/article/3137
https://mirror.xyz/0xCD99Dfa00c358FD021207eadc4176C74150d606c/D3ZUKa-jzsrtFkr4dJYT0CjOcRvdMfJdnDzPv8TKjeM
https://github.com/Dapp-Learning-DAO/Dapp-Learning/blob/main/defi/Aave/contract/6-ReserveLogic.md#updateState
https://s3cunda.github.io/2022/03/13/AAVE%E8%B0%83%E7%A0%94%E6%8A%A5%E5%91%8A.html#v2



