// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

import {Iceberg} from "../src/Iceberg.sol";
import {FheEnabled} from "./utils/FheHelper.sol";
import {FHERC20} from "../src/FHERC20.sol";
import {IFHERC20} from "../src/interface/IFHERC20.sol";
import {FHE, inEuint128, euint128, inEuint32, euint32, inEbool, ebool} from "@fhenixprotocol/contracts/FHE.sol";
import {Permission, PermissionHelper} from "./utils/PermissionHelper.sol";

import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {EasyPosm} from "./utils/EasyPosm.sol";
import {Fixtures} from "./utils/Fixtures.sol";

contract IcebergTest is Test, Fixtures, FheEnabled {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    Iceberg hook;
    PoolId poolId;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    Currency fheCurrency0;
    Currency fheCurrency1;

    IFHERC20 fheToken0;
    IFHERC20 fheToken1;

    address public user;
    uint256 public userPrivateKey;
    PermissionHelper private permitHelperToken0;
    PermissionHelper private permitHelperToken1;
    Permission private permissionToken0;
    Permission private permissionToken1;

    PermissionHelper private permitHelperFHERC6909;
    Permission private permissionFHERC6909;

    function setUp() public {

        initializeFhe();

        userPrivateKey = 0xA11CE;
        user = vm.addr(userPrivateKey);

        // creates the pool manager, utility routers, and test tokens
        deployFreshManagerAndRouters();

        vm.startPrank(user);
        (fheCurrency0, fheCurrency1) = deployMintAndApprove2FHECurrencies();

        fheToken0 = IFHERC20(Currency.unwrap(fheCurrency0));
        fheToken1 = IFHERC20(Currency.unwrap(fheCurrency1));

        permitHelperToken0 = new PermissionHelper(address(fheToken0));
        permitHelperToken1 = new PermissionHelper(address(fheToken1));

        permissionToken0 = permitHelperToken0.generatePermission(userPrivateKey);
        permissionToken1 = permitHelperToken1.generatePermission(userPrivateKey);

        deployAndApprovePosm(manager, fheCurrency0, fheCurrency1);

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(
                Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_INITIALIZE_FLAG
            ) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        bytes memory constructorArgs = abi.encode(manager); //Add all the necessary constructor arguments from the hook
        deployCodeTo("Iceberg.sol:Iceberg", constructorArgs, flags);
        hook = Iceberg(flags);

        permitHelperFHERC6909 = new PermissionHelper(address(hook));
        permissionFHERC6909 = permitHelperFHERC6909.generatePermission(userPrivateKey);

        // Create the pool
        key = PoolKey(fheCurrency0, fheCurrency1, 3000, 60, IHooks(hook));
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1);

        // Provide full-range liquidity to the pool
        tickLower = TickMath.minUsableTick(key.tickSpacing);
        tickUpper = TickMath.maxUsableTick(key.tickSpacing);

        uint128 liquidityAmount = 100e18;

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );

        (tokenId,) = posm.mint(
            key,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            address(user),
            block.timestamp,
            ZERO_BYTES
        );

        vm.stopPrank();
    }

    function testPlaceIcebergOrder() private {
        uint128 max = type(uint128).max - 1;
        fheToken0.approveEncrypted(address(hook), encrypt128(max));
        fheToken1.approveEncrypted(address(hook), encrypt128(max));
        
        inEuint32 memory encTickLower = encrypt32(0);        // encrypted 0 tick
        inEbool memory encZeroForOne = encryptBool(0);       // encrypted false e.g. trade One for Zero!
        inEuint128 memory liquidity = encrypt128(987654321); // encrypted size of trade

        hook.placeIcebergOrder(key, encTickLower, encZeroForOne, liquidity);
    }

    function testRevertPlaceIcebergOrderZeroLiquidity() public {
        inEuint32 memory encTickLower = encrypt32(10);        // encrypted 10 tick
        inEbool memory encZeroForOne = encryptBool(1);       // encrypted true
        inEuint128 memory liquidity = encrypt128(0); // encrypted size of trade (0)

        vm.expectRevert();
        
        hook.placeIcebergOrder(key, encTickLower, encZeroForOne, liquidity);
    }

    function testAfterSwapIceberg() prank(user) printBalancesBeforeAfter public {
        //get user balance before placing order
        //get sealed output signed with users public key
        //unseal the output back into uint256 for test assertions
        string memory userEncryptedBalanceBefore = fheToken1.balanceOfEncrypted(user, permissionToken1);
        uint256 userBalanceBeforeToken1 = unseal(address(fheToken1), userEncryptedBalanceBefore);

        uint128 max = type(uint128).max - 1;
        fheToken0.approveEncrypted(address(hook), encrypt128(max));
        fheToken1.approveEncrypted(address(hook), encrypt128(max));

        testPlaceIcebergOrder(); //place iceberg order OneforZero

        uint256 amountToSwap = 12345678910;
        bool zeroForOne = true;                 //note swap is zeroForOne trade ... against the iceberg limit order
        int256 amountSpecified = int256(amountToSwap);

        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            sqrtPriceLimitX96: zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT
        });

        //swap crosses encrypted limit order tick, expected to fill
        swapRouter.swap(key, params, _defaultTestSettings(), ZERO_BYTES);

        string memory userEncryptedBalanceAfter = fheToken1.balanceOfEncrypted(user, permissionToken1);
        uint256 userBalanceAfterToken1 = unseal(address(fheToken1), userEncryptedBalanceAfter);

        // balance after should be reduced by iceberg order trade size
        // trade size is small, therefore negligible slippage
        assertEq(userBalanceBeforeToken1 - 987654321, userBalanceAfterToken1);
    }

    function testRedeemOrder() printBalancesBeforeAfter public {
        // user balance should increase on token0 since it is a oneForZero swap
        vm.startPrank(user);
        string memory userEncryptedBalanceBefore = fheToken0.balanceOfEncrypted(user, permissionToken0);
        uint256 userBalanceBeforeToken0 = unseal(address(fheToken0), userEncryptedBalanceBefore);
        vm.stopPrank();

        testAfterSwapIceberg();

        bytes32 tokId = keccak256(abi.encodePacked(key.toId(), uint32(0), false));

        vm.startPrank(user);
        string memory userEncryptedFHERC6909Balance = hook.sealedBalance(permissionFHERC6909, tokId);
        uint256 userBalanceFHERC6909 = unseal(address(hook), userEncryptedFHERC6909Balance);
        
        //ensure user has accurate number of FHERC6909 receipt tokens
        assertEq(userBalanceFHERC6909, 987654321);

        string memory userEncryptedBalanceMid = fheToken0.balanceOfEncrypted(user, permissionToken0);
        uint256 userBalanceMidToken0 = unseal(address(fheToken0), userEncryptedBalanceMid);

        hook.redeemOrder(key, tokId);

        string memory userFHERC6909BalanceAfterRedeem = hook.sealedBalance(permissionFHERC6909, tokId);
        uint256 userBalanceFHERC6909AfterRedeem = unseal(address(hook), userFHERC6909BalanceAfterRedeem);
        assertEq(userBalanceFHERC6909AfterRedeem, 0); //ensure all receipt tokens are burnt

        string memory userEncryptedBalanceAfter = fheToken0.balanceOfEncrypted(user, permissionToken0);
        uint256 userBalanceAfterToken0 = unseal(address(fheToken0), userEncryptedBalanceAfter);

        console2.logString("userBalanceBeforeToken0");
        console2.logUint(userBalanceBeforeToken0);

        console2.logString("userBalanceMidToken0");
        console2.logUint(userBalanceMidToken0);

        console2.logString("userBalanceAfterToken0");
        console2.logUint(userBalanceAfterToken0);

        assertGt(userBalanceBeforeToken0, userBalanceAfterToken0); //ensure balance increase from filled iceberg order

        vm.stopPrank();
    }

    function _defaultTestSettings() internal pure returns (PoolSwapTest.TestSettings memory testSetting) {
        return PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
    }

    function deployMintAndApproveCurrency(string memory name, string memory symbol) internal returns (Currency currency) {
        FHERC20 token = new FHERC20(name, symbol);
        token.mint(type(uint256).max);
        token.wrap(type(uint128).max - 1);

        address[9] memory toApprove = [
            address(swapRouter),
            address(swapRouterNoChecks),
            address(modifyLiquidityRouter),
            address(modifyLiquidityNoChecks),
            address(donateRouter),
            address(takeRouter),
            address(claimsRouter),
            address(nestedActionRouter.executor()),
            address(actionsRouter)
        ];

        for (uint256 i = 0; i < toApprove.length; i++) {
            token.approve(toApprove[i], type(uint256).max);
            //token.approveEncrypted(toApprove[i], encrypt128(type(uint128).max));
        }

        return Currency.wrap(address(token));
    }

    function deployMintAndApprove2FHECurrencies() internal returns (Currency currency0, Currency currency1) {
        Currency _currencyA = deployMintAndApproveCurrency("TokenA", "TOKA");
        address tokenA = Currency.unwrap(_currencyA);

        Currency _currencyB = deployMintAndApproveCurrency("TokenB", "TOKB");
        address tokenB = Currency.unwrap(_currencyB);

        if (tokenA < tokenB) {
            (currency0, currency1) = (Currency.wrap(tokenA), Currency.wrap(tokenB));
        } else {
            (currency0, currency1) = (Currency.wrap(tokenB), Currency.wrap(tokenA));
        }

        return (currency0, currency1);
    }

    modifier prank(address u) {
        vm.startPrank(u);
        _;
        vm.stopPrank();
    }

    modifier printBalancesBeforeAfter(){
        uint256 userBalanceBefore0 = fheCurrency0.balanceOf(address(user));
        uint256 userBalanceBefore1 = fheCurrency1.balanceOf(address(user));

        uint256 hookBalanceBefore0 = fheCurrency0.balanceOf(address(hook));
        uint256 hookBalanceBefore1 = fheCurrency1.balanceOf(address(hook));

        console2.log("--- STARTING BALANCES ---");

        console2.log("User balance in currency0 before swapping: ", userBalanceBefore0);
        console2.log("User balance in currency1 before swapping: ", userBalanceBefore1);
        console2.log("Hook balance in currency0 before swapping: ", hookBalanceBefore0);
        console2.log("Hook balance in currency1 before swapping: ", hookBalanceBefore1);

        euint128 encUserBalanceBefore0 = fheToken0.balanceOfEncrypted(address(user));
        euint128 encUserBalanceBefore1 = fheToken1.balanceOfEncrypted(address(user));

        euint128 encHookBalanceBefore0 = fheToken0.balanceOfEncrypted(address(hook));
        euint128 encHookBalanceBefore1 = fheToken1.balanceOfEncrypted(address(hook));

        console2.log("--- STARTING ENCRYPTED BALANCES ---");

        console2.log("Encrypted User balance in currency0 before swapping: ", FHE.decrypt(encUserBalanceBefore0));
        console2.log("Encrypted User balance in currency1 before swapping: ", FHE.decrypt(encUserBalanceBefore1));
        console2.log("Encrypted Hook balance in currency0 before swapping: ", FHE.decrypt(encHookBalanceBefore0));
        console2.log("Encrypted Hook balance in currency1 before swapping: ", FHE.decrypt(encHookBalanceBefore1));
        
        _;

        uint256 userBalanceAfter0 = fheCurrency0.balanceOf(address(user));
        uint256 userBalanceAfter1 = fheCurrency1.balanceOf(address(user));

        uint256 hookBalanceAfter0 = fheCurrency0.balanceOf(address(hook));
        uint256 hookBalanceAfter1 = fheCurrency1.balanceOf(address(hook));

        console2.log("--- ENDING BALANCES ---");

        console2.log("User balance in currency0 after swapping: ", userBalanceAfter0);
        console2.log("User balance in currency1 after swapping: ", userBalanceAfter1);
        console2.log("Hook balance in currency0 after swapping: ", hookBalanceAfter0);
        console2.log("Hook balance in currency1 after swapping: ", hookBalanceAfter1);

        euint128 encUserBalanceAfter0 = fheToken0.balanceOfEncrypted(address(user));
        euint128 encUserBalanceAfter1 = fheToken1.balanceOfEncrypted(address(user));

        euint128 encHookBalanceAfter0 = fheToken0.balanceOfEncrypted(address(hook));
        euint128 encHookBalanceAfter1 = fheToken1.balanceOfEncrypted(address(hook));

        console2.log("--- ENDING ENCRYPTED BALANCES ---");

        console2.log("Encrypted User balance in currency0 after swapping: ", FHE.decrypt(encUserBalanceAfter0));
        console2.log("Encrypted User balance in currency1 after swapping: ", FHE.decrypt(encUserBalanceAfter1));
        console2.log("Encrypted Hook balance in currency0 after swapping: ", FHE.decrypt(encHookBalanceAfter0));
        console2.log("Encrypted Hook balance in currency1 after swapping: ", FHE.decrypt(encHookBalanceAfter1));
    }

}