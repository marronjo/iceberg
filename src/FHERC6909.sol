// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IFHERC6909} from "./IFHERC6909.sol";
import { FHE, euint128, inEuint128, ebool } from "@fhenixprotocol/contracts/FHE.sol";

abstract contract FHERC6909 {

    mapping(address owner => mapping(address operator => ebool isOperator)) public isOperator;

    mapping(address owner => mapping(bytes32 id => euint128 balance)) public balanceOf;

    mapping(address owner => mapping(address spender => mapping(bytes32 id => euint128 amount))) public allowance;

    function transfer(address receiver, bytes32 id, euint128 amount) public virtual returns (bool) {
        balanceOf[msg.sender][id] = FHE.sub(balanceOf[msg.sender][id], amount);
        balanceOf[receiver][id] = FHE.add(balanceOf[receiver][id], amount);
        return true;
    }

    function transferFrom(address sender, address receiver, bytes32 id, euint128 amount) public virtual returns (bool) {
        // if (msg.sender != sender && !isOperator[sender][msg.sender]) {
        //     uint256 allowed = allowance[sender][msg.sender][id];
        //     if (allowed != type(uint256).max) allowance[sender][msg.sender][id] = allowed - amount;
        // }
        balanceOf[sender][id] = FHE.sub(balanceOf[sender][id], amount);
        balanceOf[receiver][id] = FHE.add(balanceOf[sender][id], amount);
        return true;
    }

    function approveEnc(address spender, bytes32 id, euint128 amount) public virtual returns(bool) {
        allowance[msg.sender][spender][id] = amount;
        return true;
    }

    function setOperatorEnc(address operator, ebool approved) public virtual returns (bool) {
        isOperator[msg.sender][operator] = approved;
        return true;
    }

    function _mintEnc(address receiver, bytes32 id, euint128 amount) internal virtual {
        balanceOf[receiver][id] = FHE.add(balanceOf[receiver][id], amount);
    }

    function _burnEnc(address sender, bytes32 id, euint128 amount) internal virtual {
        balanceOf[sender][id] = FHE.sub(balanceOf[sender][id], amount);
    }
}
