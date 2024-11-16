// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

import {Constants} from "./base/Constants.sol";
import {Iceberg} from "../src/Iceberg.sol";
import {HookMiner} from "../test/utils/HookMiner.sol";

/// @notice Mines the address and deploys the Counter.sol Hook contract
contract IcebergScript is Script, Constants {
    function setUp() public {}

    // function run() public {
    //     // hook contracts must have specific flags encoded in the address
    //     uint160 flags = uint160(
    //         Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_INITIALIZE_FLAG
    //     );

    //     // Mine a salt that will produce a hook address with the correct flags
    //     bytes memory constructorArgs = abi.encode(POOLMANAGER);
    //     (address hookAddress, bytes32 salt) =
    //         HookMiner.find(CREATE2_DEPLOYER, flags, type(Iceberg).creationCode, constructorArgs);

    //     // Deploy the hook using CREATE2
    //     vm.broadcast();
    //     Iceberg iceberg = new Iceberg{salt: salt}(IPoolManager(POOLMANAGER));
    //     require(address(iceberg) == hookAddress, "IcebergScript: hook address mismatch");
    // }

   

    function run() public returns(Iceberg iceberg) {
        // hook contracts must have specific flags encoded in the address
        // uint160 flags = uint160(
        //     Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_INITIALIZE_FLAG
        // );

        // Deploy the hook using CREATE2
        vm.broadcast();
        iceberg = new Iceberg(IPoolManager( address(0x0000000000000000000000002e234dae75c793f67a35089c9d99245e1c58470b)));

        //0x4444000000000000000000000000000000001040
        vm.etch();
    }
}