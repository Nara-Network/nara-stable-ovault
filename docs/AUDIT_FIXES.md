# Audit Fixes

Paladin audit remediation for StakingRewardsDistributor, MCT, NaraUSDPlus.

## Global

| #   | Issue                | Fix                                        |
| --- | -------------------- | ------------------------------------------ |
| 02  | Missing storage gaps | Added `__gap` to all upgradeable contracts |
| 03  | No-op setter updates | Added same-value revert checks             |

## StakingRewardsDistributor

| #   | Issue                                | Fix                                                  |
| --- | ------------------------------------ | ---------------------------------------------------- |
| 48  | `initialize()` couldn't set operator | Set operator directly instead of via `setOperator()` |

## MCT

| #           | Issue                       | Fix                                         |
| ----------- | --------------------------- | ------------------------------------------- |
| 50          | Missing interface           | Implemented `IMultiCollateralToken`         |
| 51          | Unused error                | Removed `InvalidToken`                      |
| 54          | Generic error for duplicate | Added `AssetAlreadySupported` error         |
| 49,52,53,55 | Governance considerations   | Added NatSpec noting privileged role powers |

## NaraUSDPlus

| #     | Issue                                       | Fix                                       |
| ----- | ------------------------------------------- | ----------------------------------------- |
| 28    | Immediate UUPS upgrades                     | Documented in NatSpec                     |
| 29    | Blacklist bypass in `unstake()`             | Added `_isBlacklisted(msg.sender)` check  |
| 30    | Silo shares ignored in redistribute         | Now includes cooldown shares              |
| 31    | MIN_SHARES violated in redistribute         | Added `_checkMinShares()`                 |
| 32    | `cooldownAssets` locks shares               | Documented in NatSpec                     |
| 33/35 | `maxRedeem`/`maxWithdraw` ignore MIN_SHARES | Added overrides                           |
| 34    | `burnAssets` underflow                      | Added unvested amount check               |
| 36    | `cancelCooldown` works when paused          | Added `whenNotPaused`                     |
| 37    | Blacklist doesn't check operator            | Documented as intentional                 |
| 38    | No dedicated pause role                     | Added `GATEKEEPER_ROLE`                   |
| 39    | `burnAssets` negative yield                 | Documented as intentional                 |
| 40    | Missing zero checks                         | Added to `addToBlacklist`, `rescueTokens` |

## Tests

`test/unit/AuditFixes.t.sol` - 14 tests covering all fixes.

```bash
forge test --match-path "test/unit/AuditFixes.t.sol" -v
```
