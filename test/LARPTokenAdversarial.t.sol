// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {LARPToken} from "src/LARPToken.sol";

/// @dev Tests allowance ownership across a real intermediate contract call.
contract LARPSpendingRelay {
    function spend(LARPToken token, address owner, address recipient, uint256 amount) external returns (bool) {
        return token.transferFrom(owner, recipient, amount);
    }
}

/// forge-config: default.fuzz.runs = 1024
contract LARPTokenAdversarialTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    LARPToken private token;
    address private alice;
    address private bob;
    address private spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new LARPToken();
        alice = makeAddr("adversarial alice");
        bob = makeAddr("adversarial bob");
        spender = makeAddr("adversarial spender");
    }

    function test_oneBaseUnitAllowanceCannotBeReusedAfterRefill() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.allowance(alice, spender), 0);

        assertTrue(token.transfer(alice, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        _assertBalances(SUPPLY - 2, 1, 1, 0);
    }

    function test_largestFiniteAllowanceIsNotTreatedAsInfinite() public {
        uint256 approved = type(uint256).max - 1;
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), approved - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY - 1));
        assertEq(token.allowance(address(this), spender), approved - SUPPLY);
        _assertBalances(0, SUPPLY, 0, 0);
    }

    function test_maximumTransferFailsEvenWithInfiniteAllowance() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), bob, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        _assertBalances(SUPPLY, 0, 0, 0);
    }

    function test_maximumDirectTransferRevertsWithoutArithmeticPanic() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(bob, type(uint256).max);
        _assertBalances(SUPPLY, 0, 0, 0);
    }

    function test_zeroSpenderIsInvalidEvenWhenRevoking() public {
        assertTrue(token.approve(spender, 7));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.allowance(address(this), spender), 7);
        _assertBalances(SUPPLY, 0, 0, 0);
    }

    function test_zeroDelegatedTransferToZeroStillReverts() public {
        assertTrue(token.approve(spender, 7));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 0);
        assertEq(token.allowance(address(this), spender), 7);
        _assertBalances(SUPPLY, 0, 0, 0);
    }

    function test_zeroAddressCannotBeUsedAsTransferFromSource() public {
        // With no approval from zero, both the zero-amount and positive-amount paths must reject it.
        vm.expectRevert();
        vm.prank(spender);
        token.transferFrom(address(0), bob, 0);
        vm.expectRevert();
        vm.prank(spender);
        token.transferFrom(address(0), bob, 1);
        assertEq(token.allowance(address(0), spender), 0);
        _assertBalances(SUPPLY, 0, 0, 0);
    }

    function test_selfApprovalIsConsumedEvenWhenAllThreeRolesCoincide() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(alice, 1));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, alice, 1);
        vm.prank(alice);
        assertTrue(token.transferFrom(alice, alice, 1));
        assertEq(token.allowance(alice, alice), 0);
        _assertBalances(SUPPLY - 1, 1, 0, 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(alice, alice, 1);
        _assertBalances(SUPPLY - 1, 1, 0, 0);
    }

    function test_infiniteAllowanceCanBeRevokedAfterSpending() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 0);
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        _assertBalances(SUPPLY - 1, 1, 0, 0);
    }

    function test_infiniteAllowanceCanBeReplacedWithFiniteAllowance() public {
        assertTrue(token.approve(spender, type(uint256).max));
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 1));
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        _assertBalances(SUPPLY - 1, 0, 1, 0);
    }

    function test_intermediateContractCannotUseTransactionOriginsApproval() public {
        LARPSpendingRelay relay = new LARPSpendingRelay();
        assertTrue(token.transfer(alice, 2));
        vm.prank(alice);
        assertTrue(token.approve(spender, 2));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(relay), 0, 1));
        vm.prank(spender, spender);
        relay.spend(token, alice, bob, 1);
        assertEq(token.allowance(alice, spender), 2);
        _assertBalances(SUPPLY - 2, 2, 0, 0);

        vm.prank(alice);
        assertTrue(token.approve(address(relay), 1));
        vm.prank(spender, spender);
        assertTrue(relay.spend(token, alice, bob, 1));
        assertEq(token.allowance(alice, address(relay)), 0);
        assertEq(token.allowance(alice, spender), 2);
        _assertBalances(SUPPLY - 2, 1, 1, 0);
    }

    function test_approvalDoesNotAuthorizeADifferentOwnersFunds() public {
        assertTrue(token.transfer(alice, 10));
        assertTrue(token.transfer(bob, 10));
        vm.prank(alice);
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(bob, spender, 1);
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.allowance(bob, spender), 0);
        _assertBalances(SUPPLY - 20, 10, 10, 0);
    }

    function testFuzz_directTransferDoesNotConsumeAllowances(uint256 amount, uint256 approved) public {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.approve(spender, approved));
        assertTrue(token.approve(alice, type(uint256).max));
        assertTrue(token.transfer(alice, amount));
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.allowance(address(this), alice), type(uint256).max);
        assertEq(token.allowance(alice, spender), 0);
        _assertBalances(SUPPLY - amount, amount, 0, 0);
    }

    function testFuzz_replacingPartlySpentAllowanceResetsTheLimit(uint256 approved, uint256 spent, uint256 replacement)
        public
    {
        approved = bound(approved, 1, SUPPLY - 1);
        spent = bound(spent, 0, approved);
        replacement = bound(replacement, 0, SUPPLY - spent - 1);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, spent));

        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, replacement);
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(address(this), spender), replacement);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, replacement, replacement + 1
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), bob, replacement + 1);
        assertEq(token.allowance(address(this), spender), replacement);
        _assertBalances(SUPPLY - spent, spent, 0, 0);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, replacement));
        assertEq(token.allowance(address(this), spender), 0);
        _assertBalances(SUPPLY - spent - replacement, spent, replacement, 0);
    }

    function testFuzz_failedSpendCanBeRetriedAfterFunding(uint256 funded, uint256 spent) public {
        funded = bound(funded, 1, SUPPLY - 1);
        spent = bound(spent, 0, funded);
        assertTrue(token.transfer(alice, funded));
        vm.prank(alice);
        assertTrue(token.approve(spender, funded + 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, spent));

        uint256 remaining = funded - spent;
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, remaining, remaining + 1)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, remaining + 1);
        assertEq(token.allowance(alice, spender), remaining + 1);
        _assertBalances(SUPPLY - funded, remaining, spent, 0);

        assertTrue(token.transfer(alice, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, remaining + 1));
        assertEq(token.allowance(alice, spender), 0);
        _assertBalances(SUPPLY - funded - 1, 0, funded + 1, 0);
    }

    function testFuzz_roundTripRestoresPreviouslyFundedBalances(uint256 aliceFunds, uint256 bobFunds, uint256 amount)
        public
    {
        aliceFunds = bound(aliceFunds, 0, SUPPLY);
        bobFunds = bound(bobFunds, 0, SUPPLY - aliceFunds);
        amount = bound(amount, 0, aliceFunds);
        assertTrue(token.transfer(alice, aliceFunds));
        assertTrue(token.transfer(bob, bobFunds));
        vm.prank(alice);
        assertTrue(token.transfer(bob, amount));
        _assertBalances(SUPPLY - aliceFunds - bobFunds, aliceFunds - amount, bobFunds + amount, 0);
        vm.prank(bob);
        assertTrue(token.transfer(alice, amount));
        _assertBalances(SUPPLY - aliceFunds - bobFunds, aliceFunds, bobFunds, 0);
    }

    function testFuzz_splittingDelegatedTransferHasSameEffect(uint256 amount, uint256 first, uint256 approved) public {
        amount = bound(amount, 0, SUPPLY);
        first = bound(first, 0, amount);
        approved = bound(approved, amount, type(uint256).max);
        assertTrue(token.approve(spender, approved));
        uint256 snapshot = vm.snapshotState();

        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, first));
        assertTrue(token.transferFrom(address(this), alice, amount - first));
        vm.stopPrank();
        uint256 splitOwnerBalance = token.balanceOf(address(this));
        uint256 splitRecipientBalance = token.balanceOf(alice);
        uint256 splitAllowance = token.allowance(address(this), spender);
        _assertBalances(SUPPLY - amount, amount, 0, 0);

        assertTrue(vm.revertToStateAndDelete(snapshot));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.balanceOf(address(this)), splitOwnerBalance);
        assertEq(token.balanceOf(alice), splitRecipientBalance);
        assertEq(token.allowance(address(this), spender), splitAllowance);
        assertEq(splitAllowance, approved == type(uint256).max ? approved : approved - amount);
        _assertBalances(SUPPLY - amount, amount, 0, 0);
    }

    function _assertBalances(uint256 deployerBalance, uint256 aliceBalance, uint256 bobBalance, uint256 spenderBalance)
        private
        view
    {
        assertEq(token.balanceOf(address(this)), deployerBalance);
        assertEq(token.balanceOf(alice), aliceBalance);
        assertEq(token.balanceOf(bob), bobBalance);
        assertEq(token.balanceOf(spender), spenderBalance);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
