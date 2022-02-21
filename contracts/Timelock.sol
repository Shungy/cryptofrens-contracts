// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/governance/TimelockController.sol";

// Happy.sol ownership will be transferred to this contract.
// An EOA (i.e.: me) will be the sole proposer and executor.
contract Timelock is TimelockController {
    constructor(address[] memory admins)
        TimelockController(7 days, admins, admins)
    {}
}
