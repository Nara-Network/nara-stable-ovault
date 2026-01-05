# Audit Fixes

Paladin audit remediation for StakingRewardsDistributor, MCT, NaraUSDPlus.

## Global

| #   | Issue                | Fix                                        |
| --- | -------------------- | ------------------------------------------ |
| 02  | Missing storage gaps | Added `__gap` to all upgradeable contracts |
| 03  | No-op setter updates | Added same-value revert checks             |

## NaraUSD Contract

| #     | Issue                                                                                   | Fix                                                                                                                                                        |
| ----- | --------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 04    | Privileged roles have too much powers                                                   | Added NatSpec noting privileged role powers                                                                                                                |
| 05    | `redistributeLockedAmount` incomplete                                                   | Extended to handle both wallet and escrowed balances                                                                                                       |
| 07    | `updateRedemptionRequest()` missing blacklist/Keyring checks                            | Added blacklist and Keyring checks in "still insufficient collateral" branch                                                                               |
| 08    | `mintWithCollateralFor` pulls from beneficiary                                          | Removed `mintWithCollateralFor` and whole delegation feature, added `mintWithoutCollateralFor` for admin                                                   |
| 09    | `cancelRedeem()` can be invoked while paused                                            | Added `whenNotPaused` modifier                                                                                                                             |
| 10    | `minMintAmount` checked before fees                                                     | Moved check to after fee deduction, compares against actual minted amount                                                                                  |
| 06,11 | `mintedPerBlock` tracks pre-fee amount and uses wrong decimals in `_mintWithCollateral` | Updated to track actual minted amount (post-fee)                                                                                                           |
| 12    | misleading `ERC4626` implementation                                                     | Disabled ERC4626 deposit/mint/withdraw/redeem; overrode max\* functions to reflect constraints; added documentation                                        |
| 13    | Blacklisted `msg.sender` can call `transferFrom`                                        | Added `msg.sender` blacklist check in `_update()`                                                                                                          |
| 14    | NaraUSD does not implement INaraUSD                                                     | Added `INaraUSD` interface implementation, removed duplicate errors/events                                                                                 |
| 15    | Unused `InvalidToken` error                                                             | Removed unused error definition                                                                                                                            |
| 16    | User can self complete redemption via `updateRedemptionRequest`                         | Added `tryCompleteRedeem()` for explicit user self-completion; `updateRedemptionRequest()` now only updates queued amount                                  |
| 17    | `setMinMintFeeAmount` can exceed `minMintAmount`                                        | Added validation to ensure min fee < min amount                                                                                                            |
| 18    | Missing `address(0)` validation                                                         | Added `ZeroAddressException` checks to all admin setters                                                                                                   |
| 19    | Named return variables inconsistency                                                    | Changed to explicit returns for clarity                                                                                                                    |
| 20    | Redundant fee/normalization calculations                                                | Simplified `_mintWithCollateral` logic                                                                                                                     |
| 21    | `previewWithdraw()` uses floor rounding                                                 | Updated to use parent's implementation, e.g. `super.previewWithdraw()`                                                                                     |
| 22    | redemption queue is not ordered queue                                                   | Added comprehensive documentation clarifying that redemption mechanism is a per-user mapping (not FIFO queue), completion order is discretionary by solver |
| 23    | user can spam create and cancel redemption request                                      | Documented that spam is possible but costs gas                                                                                                             |
| 24    | `_completeRedemption()` doesn't re-check collateral                                     | Added pre-check for sufficient collateral before state changes                                                                                             |
| 25    | Queued redemptions not validated against updated `minRedeemAmount`                      | Documented as intentional (grandfathered)                                                                                                                  |
| 26    | user can cancel request at any time                                                     | Documented as by design - users can cancel at any time, including right before completion                                                                  |
| 27    | Queued redemptions can become non-completable if asset removed                          | Added comprehensive documentation and warnings                                                                                                             |

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

## NaraUSDComposer Contract

| #   | Issue                                                 | Fix                                                                          |
| --- | ----------------------------------------------------- | ---------------------------------------------------------------------------- |
| 41  | Local (hub) collateral sends transfer wrong token     | Added local send handling to transfer collateral ERC20 directly              |
| 42  | `addWhitelistedCollateral` allows reusing OFT         | Added check that OFT is not already mapped to different asset                |
| 43  | `addWhitelistedCollateral` doesn't verify MCT support | Added validation that asset is supported by MCT                              |
| 44  | ASSET_OFT compose flow still accepted                 | Explicitly blocked ASSET_OFT in `lzCompose()` and `_handleComposeInternal()` |
| 45  | `_refund` override is redundant                       | Removed redundant override, uses base implementation                         |

## NaraUSDOFT Contract

| #   | Issue                                   | Fix                                               |
| --- | --------------------------------------- | ------------------------------------------------- |
| 46  | Instant UUPS upgrades                   | Documented in NatSpec                             |
| 47  | Blacklist doesn't restrict `msg.sender` | Added `msg.sender` blacklist check in `_update()` |

## StakingRewardsDistributor

| #   | Issue                                | Fix                                                  |
| --- | ------------------------------------ | ---------------------------------------------------- |
| 48  | `initialize()` couldn't set operator | Set operator directly instead of via `setOperator()` |

## MCT

| #     | Issue                       | Fix                                          |
| ----- | --------------------------- | -------------------------------------------- |
| 50    | Missing interface           | Implemented `IMultiCollateralToken`          |
| 51    | Unused error                | Removed `InvalidToken`                       |
| 53/55 | Admin role can be renounced | Added `renounceRole` override blocking admin |
| 54    | Generic error for duplicate | Added `AssetAlreadySupported` error          |
| 49,52 | Governance considerations   | Added NatSpec noting privileged role powers  |

## Tests

`test/unit/AuditFixes.t.sol` - 14 tests covering all fixes.

```bash
forge test --match-path "test/unit/AuditFixes.t.sol" -v
```
