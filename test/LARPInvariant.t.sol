// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {LARPToken} from "../src/LARPToken.sol";

/// @dev Closed actor set so every base unit is counted after arbitrary call sequences.
contract LARPHandler is Test {
    LARPToken public immutable token;
    address[4] public actors;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(LARPToken token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, token.balanceOf(from));
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 approved = expectedAllowance[owner][spender];
        uint256 balance = token.balanceOf(owner);
        amount = bound(amount, 0, approved < balance ? approved : balance);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        if (approved != type(uint256).max) {
            expectedAllowance[owner][spender] = approved - amount;
        }
    }
}

contract LARPInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    LARPToken private token;
    LARPHandler private handler;
    address[4] private actors;

    function setUp() public {
        token = new LARPToken();
        actors = [makeAddr("actor 0"), makeAddr("actor 1"), makeAddr("actor 2"), makeAddr("actor 3")];
        for (uint256 i; i < actors.length; ++i) {
            token.transfer(actors[i], SUPPLY / actors.length);
        }
        handler = new LARPHandler(token, actors);
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = LARPHandler.transfer.selector;
        selectors[1] = LARPHandler.approve.selector;
        selectors[2] = LARPHandler.transferFrom.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_supplyIsConstantAndAllBalancesAreConserved() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    function invariant_allowancesMatchApprovalsAndSpending() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.expectedAllowance(actors[i], actors[j]));
            }
        }
    }
}
