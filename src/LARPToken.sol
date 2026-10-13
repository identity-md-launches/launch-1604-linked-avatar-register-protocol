// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Linked Avatar Register Protocol (LARP)
/// @notice A fixed-supply ERC-20 with 18 decimals and no administrative powers.
contract LARPToken is ERC20 {
    /// @notice One billion tokens, expressed in the smallest token unit.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @notice Mints the entire supply once to the immediate deploying address.
    /// @dev When deployed by a factory, the factory receives the supply.
    constructor() ERC20("Linked Avatar Register Protocol", "LARP") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
