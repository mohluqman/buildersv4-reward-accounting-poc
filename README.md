# BuildersV4 reward accounting — `claimedRewards` exceeds `distributedRewards`

Morpheus Bug Bounty v2 submission (deployed bytecode, Base mainnet).

## Target

| | |
|---|---|
| Contract | `BuildersV4` |
| Address | `0x42BB446eAE6dca7723a9eBdb81EA88aFe77eF4B9` (Base, ERC1967 proxy) |
| Implementation | `0x18FAEf315b40A6D9cf49628f1133B1Aa507513B0` (`version()` = 4) |
| Pinned fork block | `52390000` |

## Run it

```
git clone <this repo> && cd <repo>
export BASE_RPC=<any Base mainnet RPC URL>
forge test -vv
```

`forge` only. No API keys, no private keys, no `vm.prank` as owner/admin/multisig.
`forge-std` is vendored under `lib/`, so there is no `forge install` step.

## Invariant that breaks

A reward distributor must never pay out more than it accrued:

```
claimedRewards  <=  distributedRewards
```

and cumulative payouts must stay inside the reward-pool emission allocated to Builders
(`RewardPool` pool 3 emission x `networkShare`).

## Mechanism

`BuildersV4` carries two reward accumulators:

* **global** — `allSubnetsData.rate`
* **per-subnet** — `subnetsData[s].rate`

A subnet's entitlement is recomputed at claim time as

```
(allSubnetsData.rate - subnetsData[s].rate) * subnetsData[s].deposited / PRECISION
```

`allSubnetsData.rate` rises on every touch of **any** subnet. `subnetsData[s].rate` rises only when
**that** subnet is touched. A subnet nobody touches therefore keeps accruing against a global rate
that has already risen from other subnets' activity, so the sum of per-subnet entitlements grows
faster than the emission that funds them.

`claim()` sizes the payout from the per-subnet number, so the payout follows the inflated figure.

## Evidence (fork block 52390000)

The contract's own two getters document the same quantity and disagree by about 69%:

| Getter | Value |
|---|---|
| `SUM over s of getCurrentSubnetRewards(s)` | `107133630188557761469217` |
| `getCurrentSubnetsRewards()` | `63308542715366517248201` |
| `distributedRewards - claimedRewards` | `63277941629506322919313` |

Executing every subnet's legitimate claim then drives `claimedRewards` above `distributedRewards`
and above the whole Builders emission budget, and makes the contract's own aggregate getter
underflow:

| | |
|---|---|
| `distributedRewards` after | `698512329491396007144864` |
| `claimedRewards` after | `706888131836536250629722` |
| `claimedRewards` - `distributedRewards` | `8375802345140243484858` |
| Builders emission budget (pool 3 x 80%, V4 cut to fork) | `699609267967320887979999` |
| `claimedRewards` - emission budget | `7278863869215362649723` |

## Tests

* `test_A_gettersDisagree` — the two getters disagree
* `test_B_claimedExceedsDistributed` — legitimate claims push cumulative payouts past cumulative accruals
* `test_C_claimsExceedEmissionBudget` — cumulative claims pass the whole Builders emission budget
* `test_D_orderDependence` — control: the total extracted depends on claim order at the same block
