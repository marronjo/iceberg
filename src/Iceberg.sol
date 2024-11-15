// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

//Uniswap Imports
import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {IERC20Minimal} from "@uniswap/v4-core/src/interfaces/external/IERC20Minimal.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {EpochLibrary, Epoch} from "./EpochLibrary.sol";

//Fhenix Imports
import { 
    FHE,
    euint256,
    euint128,
    euint32,
    ebool
    } from "@fhenixprotocol/contracts/FHE.sol";
import {IFHERC20} from "./IFHERC20.sol";
import {FHERC6909} from "./FHERC6909.sol";

contract Iceberg is BaseHook, FHERC6909 {

    error NotManager();
    error ZeroLiquidity();
    error InRange();
    error CrossedRange();
    error Filled();
    error NotFilled();
    error NotPoolManagerToken();

    modifier onlyByManager() {
        if (msg.sender != address(poolManager)) revert NotManager();
        _;
    }

    using PoolIdLibrary for PoolKey;
    using EpochLibrary for Epoch;
    using CurrencyLibrary for Currency;
    using CurrencySettler for Currency;
    using StateLibrary for IPoolManager;

    bytes internal constant ZERO_BYTES = bytes("");

    Epoch private constant EPOCH_DEFAULT = Epoch.wrap(0);

    mapping(PoolId => int24) public tickLowerLasts;
    Epoch public epochNext = Epoch.wrap(1);

    struct EpochInfo {
        bool filled;
        Currency currency0;
        Currency currency1;
        uint256 token0Total;
        uint256 token1Total;
        uint128 liquidityTotal;
        mapping(address => uint128) liquidity;
    }

    mapping(bytes32 => Epoch) public epochs;
    mapping(Epoch => EpochInfo) public epochInfos;

    struct EncEpochInfo {
        ebool filled;
        Currency currency0;
        Currency currency1;
        euint256 token0Total;
        euint256 token1Total;
        euint128 liquidityTotal;
        mapping(address => euint128) liquidity;
    }

    mapping(Epoch => EncEpochInfo) public encEpochInfos;

    mapping(bytes32 tokenId => euint128 totalSupply) public totalSupply;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function getTickLowerLast(PoolId poolId) public view returns (int24) {
        return tickLowerLasts[poolId];
    }

    function setTickLowerLast(PoolId poolId, int24 tickLower) private {
        tickLowerLasts[poolId] = tickLower;
    }

    function getEpoch(PoolKey memory key, int24 tickLower, bool zeroForOne) public view returns (Epoch) {
        return epochs[keccak256(abi.encode(key, tickLower, zeroForOne))];
    }

    function setEpoch(PoolKey memory key, int24 tickLower, bool zeroForOne, Epoch epoch) private {
        epochs[keccak256(abi.encode(key, tickLower, zeroForOne))] = epoch;
    }

    function getEpochLiquidity(Epoch epoch, address owner) external view returns (uint256) {
        return epochInfos[epoch].liquidity[owner];
    }

    function getEncEpoch(PoolKey memory key, euint32 tickLower, ebool zeroForOne) public view returns (Epoch) {
        return epochs[keccak256(abi.encode(key, tickLower, zeroForOne))];
    }

    function setEncEpoch(PoolKey memory key, euint32 tickLower, ebool zeroForOne, Epoch epoch) private {
        epochs[keccak256(abi.encode(key, tickLower, zeroForOne))] = epoch;
    }

    function getEncEpochLiquidity(Epoch epoch, address owner) external view returns (euint128) {
        return encEpochInfos[epoch].liquidity[owner];
    }

    function getTick(PoolId poolId) private view returns (int24 tick) {
        (, tick,,) = poolManager.getSlot0(poolId);
    }

    function getTickLower(int24 tick, int24 tickSpacing) private pure returns (int24) {
        int24 compressed = tick / tickSpacing;
        if (tick < 0 && tick % tickSpacing != 0) compressed--;
        return compressed * tickSpacing;
    }

    function _getTokenFromPoolKey(PoolKey calldata poolKey, bool zeroForOne) private pure returns(address token){
        token = zeroForOne ? Currency.unwrap(poolKey.currency0) : Currency.unwrap(poolKey.currency1);
    }

    function afterInitialize(address, PoolKey calldata key, uint160, int24 tick)
        external
        override
        onlyByManager
        returns (bytes4)
    {
        setTickLowerLast(key.toId(), getTickLower(tick, key.tickSpacing));
        return Iceberg.afterInitialize.selector;
    }

    function placeIcebergOrder(PoolKey calldata key, euint32 tickLower, ebool zeroForOne, euint128 liquidity)
        external
        onlyValidPools(key.hooks)
    {
        FHE.req(FHE.gt(liquidity, FHE.asEuint128(0)));

        // poolManager.unlock(
        //     abi.encodeCall(
        //         this.unlockCallbackPlace, (key, tickLower, zeroForOne, int256(uint256(liquidity)), msg.sender)
        //     )
        // );

        bytes32 tokenId = keccak256(abi.encode(key, tickLower, zeroForOne));

        //mint FHERC6909 tokens to user as receipt of order
        _mintEnc(msg.sender, tokenId, liquidity);
        totalSupply[tokenId] = FHE.add(totalSupply[tokenId], liquidity);

        EncEpochInfo storage epochInfo;
        Epoch epoch = getEncEpoch(key, tickLower, zeroForOne);
        if (epoch.equals(EPOCH_DEFAULT)) {
            unchecked {
                setEncEpoch(key, tickLower, zeroForOne, epoch = epochNext);
                epochNext = epoch.unsafeIncrement();
            }
            epochInfo = encEpochInfos[epoch];
            epochInfo.currency0 = key.currency0;
            epochInfo.currency1 = key.currency1;
        } else {
            epochInfo = encEpochInfos[epoch];
        }

        unchecked {
            epochInfo.liquidityTotal = FHE.add(epochInfo.liquidityTotal, liquidity);
            epochInfo.liquidity[msg.sender] = FHE.add(epochInfo.liquidity[msg.sender], liquidity);
        }

        //TODO Transfer in FHERC20 tokens!! TransferFrom
        euint128 zero = FHE.asEuint128(0);

        euint128 token0Amount = FHE.select(zeroForOne, liquidity, zero);
        euint128 token1Amount = FHE.select(zeroForOne, zero, liquidity);

        // send both tokens, one amount is zero to obscure trade direction
        IFHERC20(Currency.unwrap(key.currency0)).transferFromEncrypted(msg.sender, address(this), token0Amount);
        IFHERC20(Currency.unwrap(key.currency1)).transferFromEncrypted(msg.sender, address(this), token1Amount);
    }

}