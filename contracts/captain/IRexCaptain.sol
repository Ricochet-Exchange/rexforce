// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.14;

import { RexCaptainStorage } from "./RexCaptainStorage.sol";

interface IREXCaptain {
    function isCaptain(address _addr) external view;
    function isCaptainDisputed(address _addr) external view returns (bool);
}
