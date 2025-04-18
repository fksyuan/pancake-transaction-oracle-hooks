// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "./util/MockAttestationRegistry.t.sol";
import {Constants} from "pancake-v4-core/test/pool-cl/helpers/Constants.sol";
import {Currency} from "pancake-v4-core/src/types/Currency.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "pancake-v4-core/src/types/BeforeSwapDelta.sol";
import {CLExchangeVolumeHook} from "../../src/pool-cl/volume/CLExchangeVolumeHook.sol";
import {Test} from "forge-std/Test.sol";
import {Attestation} from "../../src/types/Common.sol";
import {ICLPoolManager} from "pancake-v4-core/src/pool-cl/interfaces/ICLPoolManager.sol";
import {CLPoolManager} from "pancake-v4-core/src/pool-cl/CLPoolManager.sol";
import {PoolKey} from "pancake-v4-core/src/types/PoolKey.sol";
import {IHooks} from "pancake-v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "pancake-v4-core/src/interfaces/IPoolManager.sol";
import {console} from "forge-std/console.sol";
import {IVault} from "pancake-v4-core/src/interfaces/IVault.sol";
import {Vault} from "pancake-v4-core/src/Vault.sol";
import {LPFeeLibrary} from "pancake-v4-core/src/libraries/LPFeeLibrary.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {CLPoolParametersHelper} from "pancake-v4-core/src/pool-cl/libraries/CLPoolParametersHelper.sol";

contract CLExchangeVolumeHookTest is Test {
    using CLPoolParametersHelper for bytes32;

    CLExchangeVolumeHook public clExchangeVolumeHook;
    IAttestationRegistry public iAttestationRegistry;
    ICLPoolManager public clPoolManager;

    function setUp() public {
        iAttestationRegistry = new MockAttestationRegistry();

        IVault vault = new Vault();
        clPoolManager = new CLPoolManager(vault);
        console.log("clPoolManager:", address(clPoolManager));
        // Create an attestation and add it to the registry
        Attestation memory attestation = Attestation({
            recipient: address(clPoolManager),
            exchange: "binance",
            value: 100000,
            timestamp: block.timestamp
        });
        console.log("address_(this) is", address(this));
        console.log("block.timestamp:", block.timestamp);
        MockAttestationRegistry(address(iAttestationRegistry)).addAttestation(attestation);

        // Initialize the CLExchangeVolumeHook with the mock registry
        clExchangeVolumeHook = new CLExchangeVolumeHook(clPoolManager, iAttestationRegistry, msg.sender);
        console.log("clExchangeVolumeHook owner is:", clExchangeVolumeHook.owner());
    }

    function testBeforeSwap() public {
        // Fetch attestation by recipient
        Attestation[] memory fetchedAttestation =
            MockAttestationRegistry(address(iAttestationRegistry)).getAttestationByRecipient(address(this));
        // Define a valid PoolKey (adjust fields as per actual definition)
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(0)), // Replace with actual token address
            currency1: Currency.wrap(address(1)), // Replace with actual token address
            hooks: IHooks(address(clExchangeVolumeHook)),
            poolManager: clPoolManager,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG, // Example fee, replace with actual value
            parameters: bytes32(uint256(IHooks(address(clExchangeVolumeHook)).getHooksRegistrationBitmap())).setTickSpacing(
                10
            )
        });

        // Define valid SwapParams (adjust fields as per actual definition)
        ICLPoolManager.SwapParams memory swapParams = ICLPoolManager.SwapParams({
            amountSpecified: 1000, // Example amount
            sqrtPriceLimitX96: 0, // Replace with appropriate value
            zeroForOne: true // Example direction
        });

        clPoolManager.initialize(poolKey, Constants.SQRT_RATIO_1_4);
        console.log("initialize pool size:", clExchangeVolumeHook.getInitializedPoolSize());
        //update fee
        vm.prank(clExchangeVolumeHook.owner());
        clExchangeVolumeHook.updatePoolFeeByPoolKey(poolKey, 3000);

        console.logString("start swap");
        vm.prank(address(clPoolManager));
        (bytes4 selector1, BeforeSwapDelta beforeSwapDelta1, uint24 fee1) =
            clExchangeVolumeHook.beforeSwap(address(clPoolManager), poolKey, swapParams, abi.encode("0"));
        console.logUint(fee1);
        assertTrue(fee1 == 3000, "fee1 is not equal");
        vm.stopPrank();
        vm.startPrank(address(clPoolManager), address(clPoolManager));

        (bytes4 selector2, BeforeSwapDelta beforeSwapDelta2, uint24 fee2) =
            clExchangeVolumeHook.beforeSwap(address(clPoolManager), poolKey, swapParams, abi.encode("0"));
        console.log("swap 2");

        console.logUint(fee2);
        assertTrue(fee2 == (1500 | LPFeeLibrary.OVERRIDE_FEE_FLAG), "fee2 is not equal");
        vm.stopPrank();
    }

    function testOnlyOwnerCanChangeFee() public {
        // Test that non-owner cannot change the fee
        address nonOwner = address(this);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        clExchangeVolumeHook.setDefaultFee(5000);

        // Simulate the owner calling the function
        address owner = clExchangeVolumeHook.owner();
        vm.prank(owner); // Mock the caller as the owner
        clExchangeVolumeHook.setDefaultFee(5000);

        // Verify the state update
        uint256 updatedFee = clExchangeVolumeHook.defaultFee();
        assertEq(updatedFee, 5000);
    }

    function testBaseValue() public {
        // Test that non-owner cannot change the baseValue
        address nonOwner = address(this);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        clExchangeVolumeHook.setBaseValue(20000);
        // Simulate the owner calling the function
        address owner = clExchangeVolumeHook.owner();
        vm.prank(owner); // Mock the caller as the owner
        clExchangeVolumeHook.setBaseValue(20000);
        // Verify the state update
        uint256 updatedFee = clExchangeVolumeHook.baseValue();
        assertEq(updatedFee, 20000);
    }

    function testGetParameters() public {
        bytes32 parameters = bytes32(uint256(clExchangeVolumeHook.getHooksRegistrationBitmap())).setTickSpacing(10);
        console.log("parameters:");
        console.logBytes32(parameters);
    }
}
