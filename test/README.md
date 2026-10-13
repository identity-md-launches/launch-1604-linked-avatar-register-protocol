# LARP tests

The test oracle is a supply of `10^27` base units (one billion tokens with
18 decimals), minted once to the immediate deployer. Transfers must deliver the
exact requested amount, and delegated transfers must respect the owner's current
approval of the immediate caller.

| Suite | Coverage |
| --- | --- |
| `LARPToken.t.sol` | Metadata, constructor allocation and mint event, transfer/approval events, zero and full amounts, self-transfers, insufficient funds/approval, failure rollback, and fuzzed balance/allowance boundaries. |
| `LARPLaunchFlow.t.sol` | CREATE2 factory allocation, exact token distribution and claim transfers, absence of privileged mint/freeze/seizure paths, and runtime restrictions. Pool movements model only the ERC-20 legs; they do not execute Uniswap. |
| `LARPTokenAdversarial.t.sol` | Repeated spending after refill, maximum and near-maximum amounts, approval replacement/revocation after spending, ownership and caller isolation, retries after a failed spend, round trips, and split-versus-combined delegated transfers. |
| `LARPInvariant.t.sol` | Four actors and 11 targeted actions, mixing valid transfers and approvals with expected failures over random sequences. |

The invariant model starts from the fixture's specified allocation, independently
of `balanceOf`. Only successful authorized movements update expected balances;
only approvals and successful finite-allowance spends update expected allowances.
Every sequence step checks each holder's balance, all 16 actor allowance pairs,
zero-address allowances, constant supply, and aggregate conservation. Expected
failures must return the exact custom error and leave the model unchanged.
Unexpected reverts fail the campaign.

The handler explicitly exercises revocation, infinite approval, full-balance
transfers, zero amounts, and one base unit. After each sequence, every holder must
still be able to transfer their entire balance, and the consolidated supply must
be transferable again. Inline configuration sets 256 sequences of depth 96; the
new stateless fuzz properties use 1,024 runs each.

Run from the repository root with the existing vendored dependencies and compiler:

```sh
forge build --offline --out test/scratch/out --cache-path test/scratch/cache
forge test --offline --out test/scratch/out --cache-path test/scratch/cache
```

These output overrides keep temporary build files under `test/scratch/`. The
tests also run with ordinary `forge test`; no scratch file is imported or needed.
No network, fork, FFI, or environment-variable setup is required.
