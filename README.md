# Linked Avatar Register Protocol (LARP)

LARP is a fixed-supply ERC-20. Its constructor mints all tokens to its immediate
deployer. The implementation uses the vendored OpenZeppelin Contracts v5.0.2
ERC-20 without overriding its transfer or allowance behavior.

## Contract and deployment parameters

| Parameter | Value |
| --- | --- |
| Solidity contract | `src/LARPToken.sol:LARPToken` |
| Token name | `Linked Avatar Register Protocol` |
| Symbol | `LARP` |
| Decimals | `18` |
| Supply in tokens | `1,000,000,000` |
| Supply in base units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None |
| Constructor ETH value | Zero |
| Initial recipient | Immediate deployer (`msg.sender`) |
| Launch chain | Ethereum, chain ID 1 |
| Compiler | Solidity `0.8.26` |
| EVM target | Cancun |
| Optimizer | Enabled, 200 runs |
| Metadata bytecode hash | `none` |

Deploy the creation bytecode built for `LARPToken` with no appended constructor
arguments. There are no external library links or constructor calls to other
contracts. A factory deployment gives the factory the full supply; the originating
wallet receives none directly from the constructor. Both CREATE and CREATE2 work.
The token does not require a chain RPC, an owner, configuration addresses, or
post-deployment initialization.

## Behavior and assumptions

- The brief specifies a token only. The name does not introduce avatar registry,
  identity, NFT, governance, or application behavior.
- Supply is minted exactly once. There are no externally callable mint or burn
  functions, rebases, fees, transfer limits, vesting, or reserved allocations.
- Standard `transfer`, `approve`, `transferFrom`, `balanceOf`, `allowance`, and
  `totalSupply` are available. Successful transfers deliver the exact amount and
  return `true`. Transfers and approvals emit the standard ERC-20 events.
- Zero-value transfers and self-transfers work. Transfers to the zero address
  and approvals to a zero spender revert. Insufficient balances and allowances
  revert without partial changes, using OpenZeppelin's ERC-6093 errors.
- Finite allowances are consumed by `transferFrom`. An allowance of
  `type(uint256).max` remains unchanged when spent. OpenZeppelin v5 does not emit
  an `Approval` event when `transferFrom` consumes an allowance; consumers should
  query `allowance` for its current value.
- There is no owner, pause, blacklist, seizure, recovery, upgrade, proxy, or
  privileged factory path. Spending another account's tokens requires that
  account's allowance, even for the deployer.
- The token makes no external calls or recipient callbacks. Normal ETH sends
  revert. Tokens sent to this contract, or assets forcibly sent to it, cannot be
  rescued. Users must choose recipients that can manage ERC-20 balances.

## Build and checks

From the repository root, with Foundry and Solidity 0.8.26 installed:

```sh
forge build
forge test
forge fmt --check
```

All Solidity dependencies and their licenses are ordinary files in `lib/`.
No package installation, submodule initialization, FFI, filesystem permissions,
environment variables, fork, or network connection is required by the tests.
The verifier supplies the pinned compiler; no compiler binary is included here.
See [dependency provenance](lib/DEPENDENCIES.json) for upstream release URLs,
archive hashes, and individual file hashes.

The suite covers metadata and mint events; EOA and CREATE2 factory deployment;
exact launch allocation and claim transfers; ordinary pool-like buy/sell
transfers; approvals and revocation; zero values, self-transfers, maximum values,
and failure rollback; attempts to mint, initialize, upgrade, seize, or freeze;
and runtime checks for prohibited opcodes. Fuzz and stateful invariant tests
check balance conservation, constant supply, and allowance accounting.
The local launch-flow test models token movements; it does not simulate Uniswap
pricing or replace the supplied independent launch admission harness.

## Operational responsibilities

The launch service deploys the token and distributes the initial supply. For the
specified launch, the factory sends 10% to the launch MerkleDistributor, allocates
80% to pool seeding, and forwards the remaining 10% to the requester's recipient.
These are factory operations, not constructor allocations or token restrictions.
Every participant can transfer the full amount without exemption configuration.
Pool configuration and the separate launch manifest belong to the launch service.

Before release, the deployer is responsible for independent review, confirming
the artifact and compiler settings, verifying the published source, and checking
the deployed metadata, total supply, mint recipient, and resulting distribution.
No deployment, broadcast, or wallet access is performed by this project.

After launch, there are no owner settings, maintenance transactions, privileged
keys, or upgrade steps. Holders and integrations are responsible for recipient
addresses and spender permissions. Prefer exact allowances and revoke unused
ones; changing a nonzero allowance has the standard ERC-20 transaction-ordering
race, so clients should zero it before granting a replacement and account for
any spending that occurred before revocation.

Foundry tests are local evidence, not a security audit. Slither and Mythril are
not part of the recorded checks. Bugs in an immutable deployment cannot be
patched through an administrative function.
