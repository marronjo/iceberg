// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { FHE, euint128, inEuint128, ebool } from "@fhenixprotocol/contracts/FHE.sol";

interface IFHERC6909 {

    function transfer(address receiver, bytes32 id, euint128 amount) external returns (bool);
    function transferFrom(address sender, address receiver, bytes32 id, euint128 amount) external returns (bool);

    function approveEnc(address spender, bytes32 id, euint128 amount) external returns(bool);
    function setOperatorEnc(address operator, ebool approved) external returns (bool);

    function _mintEnc(address receiver, bytes32 id, euint128 amount) external;
    function _burnEnc(address sender, bytes32 id, euint128 amount) external;
}
