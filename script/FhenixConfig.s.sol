// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";

contract FhenixConfig is Script {

    error FhenixConfig__UnsupportedBridge(uint256 chainId);

    function getFhenixConfig() public view returns(address) {
        if(block.chainid == 11155111){
            return address(0x0f54FE89Cdd04211A3c68823Fb6d5B05d8C86768);
        }
        revert FhenixConfig__UnsupportedBridge(block.chainid);
    }

}