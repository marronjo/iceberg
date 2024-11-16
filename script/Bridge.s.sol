// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";
import { FhenixConfig } from "./FhenixConfig.s.sol";

interface IBridge {
    function depositEth() external payable;
}

contract BridgeScript is Script {

    modifier broadcast {
        vm.startBroadcast(msg.sender);
        _;
        vm.stopBroadcast();
    }

    FhenixConfig config = new FhenixConfig();

    function run() broadcast public {
        run(0.01 ether);
    }

    function run(uint256 v) broadcast public {
        address bridge = config.getFhenixConfig();
        IBridge(bridge).depositEth{ value: v }();
    }
}