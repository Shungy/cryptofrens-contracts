// SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.0;

interface IRewardRegulator {
    function getRewards(address account) external view returns (uint);

    function setRewards() external returns (uint);

    function mint(address to, uint amount) external;
}

interface ISunshineAndRainbows {
    function rewardVariables(uint rewards) external view returns (uint, uint);

    function userPositionsLengths(address owner) external view returns (uint);

    function userPositionsIndex(address owner, uint index) external view returns (uint);
}

contract SunshineAndRainbowsViews {
    ISunshineAndRainbows sunshine;
    IRewardRegulator regulator;

    constructor(
        address sunshineAndRainbows,
        address rewardRegulator
    ) {
        sunshine = ISunshineAndRainbows(sunshineAndRainbows);
        regulator = IRewardRegulator(rewardRegulator);
    }

    function getRewardVariables() external view returns (uint, uint) {
        return sunshine.rewardVariables(
            regulator.getRewards(address(sunshine))
        );
    }

    function userPositions(
        address owner,
        uint indexFrom,
        uint indexTo
    ) external view returns (uint[] memory) {
        uint length = sunshine.userPositionsLengths(owner);
        if (indexTo >= length) {
            indexTo = length - 1;
        }
        require(indexTo >= indexFrom, "invalid index bounds");
        uint[] memory posIds;
        uint i;
        while (indexTo >= indexFrom) {
            posIds[i] = sunshine.userPositionsIndex(owner, indexTo);
            indexTo++;
            i++;
        }
        return posIds;
    }

}
