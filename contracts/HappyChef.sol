// SPDX-License-Identifier: GPLv3
// solhint-disable not-rely-on-time
pragma solidity 0.8.15;
//
//import "@openzeppelin/contracts/access/Ownable.sol";
//import { PangoChefFunding } from "./PangoChef.sol";
//import { Happiness } from "./Happy.sol";
//
//contract HappyChef is Ownable {
//    Happiness public immutable HAPPY;
//    PangoChefFunding public immutable CHEF;
//
//    uint256 public lastUpdate;
//
//    uint256 public halfSupply = 200 days;
//    uint256 public halfSupplyCooldownFinish;
//
//    uint256 public constant HALF_SUPPLY_MAX_DECREASE = 20 days;
//    uint256 public constant COOLDOWN = 2 days;
//    uint256 public constant MIN_HALF_SUPPLY = 10 days;
//
//    uint256 public immutable CAP;
//
//    event HalfSupplySet(uint256 newHalfSupply);
//    event Minted(uint256 amount);
//
//    constructor(address rewardToken, address pangoChef) {
//        require(rewardToken != address(0), "zero address");
//        require(pangoChef != address(0), "zero address");
//        CHEF = PangoChefFunding(pangoChef);
//        HAPPY = Happiness(rewardToken);
//        Happiness tmpRewardToken = Happiness(rewardToken);
//        tmpRewardToken.approve(pangoChef, type(uint256).max);
//        CAP = tmpRewardToken.cap();
//    }
//
//    function go() external onlyOwner {
//        require(lastUpdate == 0, 'already live');
//        lastUpdate = uint128(block.timestamp);
//    }
//
//    function setHalfSupply(uint256 newHalfSupply) external onlyOwner {
//        mint();
//        if (newHalfSupply < halfSupply) {
//            unchecked {
//                require(
//                    newHalfSupply >= MIN_HALF_SUPPLY &&
//                        halfSupply - newHalfSupply <= HALF_SUPPLY_MAX_DECREASE,
//                    "half supply too low"
//                );
//            }
//        } else {
//            require(newHalfSupply != halfSupply, "same half supply");
//        }
//        require(block.timestamp >= halfSupplyCooldownFinish, "too frequent");
//        halfSupplyCooldownFinish = block.timestamp + COOLDOWN;
//        halfSupply = newHalfSupply;
//        emit HalfSupplySet(newHalfSupply);
//    }
//
//    function rewardRate() external view returns (uint256) {
//        uint256 mintableTotal = CAP + HAPPY.burnedSupply() - (HAPPY.totalSupply() + pendingMint());
//        return mintableTotal / halfSupply;
//    }
//
//    function mint() public returns (uint256 amount) {
//        amount = _update();
//
//        if (amount != 0) {
//            HAPPY.mint(address(this), amount);
//            CHEF.addReward(amount);
//            emit Minted(amount);
//        }
//    }
//
//    function pendingMint() public view returns (uint256) {
//        uint256 interval = block.timestamp - lastUpdate;
//        require(interval != block.timestamp, "schedule not started");
//        uint256 mintableTotal = CAP + HAPPY.burnedSupply() - HAPPY.totalSupply();
//        uint256 reward = (interval * mintableTotal) / (halfSupply + interval);
//        return reward;
//    }
//
//    function _update() private returns (uint256 reward) {
//        reward = pendingMint();
//        lastUpdate = uint128(block.timestamp);
//    }
//}
