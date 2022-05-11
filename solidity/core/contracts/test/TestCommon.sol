// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0;

import "../Common.sol";

contract TestCommon is Common {
    constructor(uint32 _localDomain) Common(_localDomain) {}

    function initialize(address _validatorManager) external {
        __Common_initialize(_validatorManager);
    }
}
