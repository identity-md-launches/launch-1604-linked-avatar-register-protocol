// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {LARPToken} from "../src/LARPToken.sol";

/// @dev A test-only factory fixture. All distribution below is driven by the test.
contract LARPFactoryFixture {
    function deploy(bytes32 salt) external returns (LARPToken) {
        return new LARPToken{salt: salt}();
    }
}

contract LARPLaunchFlowTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    LARPFactoryFixture private factory;
    LARPToken private token;
    address private holder;
    address private other;

    function setUp() public {
        factory = new LARPFactoryFixture();
        token = factory.deploy(keccak256("LARP launch fixture"));
        holder = makeAddr("holder");
        other = makeAddr("other");
    }

    function test_create2MintsFullSupplyToFactory() public view {
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_launchAllocationClaimsAndPoolTransfersAreExact() public {
        address distributor = makeAddr("distributor");
        address poolManager = makeAddr("pool manager");
        address remainderRecipient = makeAddr("remainder recipient");
        uint256 swarmShare = SUPPLY / 10;
        uint256 poolShare = SUPPLY * 8 / 10;
        uint256 remainder = SUPPLY - swarmShare - poolShare;

        vm.startPrank(address(factory));
        assertTrue(token.transfer(distributor, swarmShare));
        assertTrue(token.transfer(poolManager, poolShare));
        assertTrue(token.transfer(remainderRecipient, remainder));
        vm.stopPrank();
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(distributor), swarmShare);
        assertEq(token.balanceOf(poolManager), poolShare);
        assertEq(token.balanceOf(remainderRecipient), remainder);

        vm.prank(distributor);
        assertTrue(token.transfer(holder, swarmShare));
        assertEq(token.balanceOf(holder), swarmShare);
        assertEq(token.balanceOf(distributor), 0);

        // Model only the ERC-20 legs of a buy and sell, without a DEX mock.
        uint256 bought = 123 ether;
        vm.prank(poolManager);
        assertTrue(token.transfer(other, bought));
        assertEq(token.balanceOf(other), bought);
        assertEq(token.balanceOf(poolManager), poolShare - bought);
        vm.prank(other);
        assertTrue(token.transfer(poolManager, bought));
        assertEq(token.balanceOf(other), 0);
        assertEq(token.balanceOf(poolManager), poolShare);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(holder) + token.balanceOf(poolManager) + token.balanceOf(remainderRecipient), SUPPLY);
    }

    function test_deployerCannotSpendHolderFundsWithoutApproval() public {
        vm.prank(address(factory));
        token.transfer(holder, 100 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(factory), 0, 1)
        );
        vm.prank(address(factory));
        token.transferFrom(holder, address(factory), 1);
        assertEq(token.balanceOf(holder), 100 ether);
        vm.prank(holder);
        assertTrue(token.transfer(other, 100 ether));
        assertEq(token.balanceOf(other), 100 ether);
    }

    function test_noMintBurnOrAdministrativeEntryPoints() public {
        vm.prank(address(factory));
        token.transfer(holder, 100 ether);

        bytes[] memory calls = new bytes[](24);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", other, SUPPLY);
        calls[1] = abi.encodeWithSignature("mint(uint256)", SUPPLY);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("issue(uint256)", SUPPLY);
        calls[4] = abi.encodeWithSignature("setMinter(address)", other);
        calls[5] = abi.encodeWithSignature("initialize(address)", other);
        calls[6] = abi.encodeWithSignature("upgradeTo(address)", other);
        calls[7] = abi.encodeWithSignature("setOwner(address)", other);
        calls[8] = abi.encodeWithSignature("transferOwnership(address)", other);
        calls[9] = abi.encodeWithSignature("pause()");
        calls[10] = abi.encodeWithSignature("unpause()");
        calls[11] = abi.encodeWithSignature("blacklist(address)", holder);
        calls[12] = abi.encodeWithSignature("blocklist(address)", holder);
        calls[13] = abi.encodeWithSignature("freeze(address)", holder);
        calls[14] = abi.encodeWithSignature("freezeAccount(address)", holder);
        calls[15] = abi.encodeWithSignature("setBlacklist(address,bool)", holder, true);
        calls[16] = abi.encodeWithSignature("setBlocked(address,bool)", holder, true);
        calls[17] = abi.encodeWithSignature("lock(address)", holder);
        calls[18] = abi.encodeWithSignature("disableTransfers()");
        calls[19] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);
        calls[20] = abi.encodeWithSignature("burnFrom(address,uint256)", holder, 1);
        calls[21] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[22] = abi.encodeWithSignature("seize(address)", holder);
        calls[23] = abi.encodeWithSignature("initialize()");

        for (uint256 i; i < calls.length; ++i) {
            vm.prank(address(factory));
            (bool privileged,) = address(token).call(calls[i]);
            assertFalse(privileged, "unexpected deployer authority");
            vm.prank(other);
            (bool outsider,) = address(token).call(calls[i]);
            assertFalse(outsider, "unexpected public authority");
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(holder), 100 ether);
            assertEq(token.balanceOf(other), 0);
            assertEq(token.balanceOf(address(factory)), SUPPLY - 100 ether);
        }
        vm.prank(holder);
        assertTrue(token.transfer(other, 100 ether));
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(other), 100 ether);
    }

    function test_runtimeHasNoForbiddenOpcodesAndFitsDeploymentLimit() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf4, "DELEGATECALL");
            assertTrue(op != 0xf2, "CALLCODE");
            assertTrue(op != 0xff, "SELFDESTRUCT");
        }
    }
}
