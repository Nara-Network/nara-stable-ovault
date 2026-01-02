# Audit Fixes

This document tracks all security fixes and improvements implemented across the Nara Stable OVault codebase.

## Global

| #   | Issue                | Fix                                        |
| --- | -------------------- | ------------------------------------------ |
| 02  | Missing storage gaps | Added `__gap` to all upgradeable contracts |
| 03  | No-op setter updates | Added same-value revert checks             |

## NaraUSD Contract

| #     | Issue                                                                                   | Fix                                                                                                      |
| ----- | --------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| 04    | Privileged roles have too much powers                                                   | Added NatSpec noting privileged role powers                                                              |
| 05    | `redistributeLockedAmount` incomplete                                                   | Extended to handle both wallet and escrowed balances                                                     |
| 07    | `updateRedemptionRequest()` missing blacklist/Keyring checks                            | Added blacklist and Keyring checks in "still insufficient collateral" branch                             |
| 08    | `mintWithCollateralFor` pulls from beneficiary                                          | Removed `mintWithCollateralFor` and whole delegation feature, added `mintWithoutCollateralFor` for admin |
| 09    | `cancelRedeem()` can be invoked while paused                                            | Added `whenNotPaused` modifier                                                                           |
| 10    | `minMintAmount` checked before fees                                                     | Moved check to after fee deduction, compares against actual minted amount                                |
| 06,11 | `mintedPerBlock` tracks pre-fee amount and uses wrong decimals in `_mintWithCollateral` | Updated to track actual minted amount (post-fee)                                                         |
| 12    | misleading `ERC4626` implementation                                                     | PENDING ACTION                                                                                           |
| 13    | Blacklisted `msg.sender` can call `transferFrom`                                        | Added `msg.sender` blacklist check in `_update()`                                                        |
| 14    | NaraUSD does not implement INaraUSD                                                     | Added `INaraUSD` interface implementation, removed duplicate errors/events                               |
| 15    | Unused `InvalidToken` error                                                             | Removed unused error definition                                                                          |
| 16    | User can self complete redemption via `updateRedemptionRequest`                         | PENDING ACTION                                                                                           |
| 17    | `setMinMintFeeAmount` can exceed `minMintAmount`                                        | Added validation to ensure min fee < min amount                                                          |
| 18    | Missing `address(0)` validation                                                         | Added `ZeroAddressException` checks to all admin setters                                                 |
| 19    | Named return variables inconsistency                                                    | Changed to explicit returns for clarity                                                                  |
| 20    | Redundant fee/normalization calculations                                                | Simplified `_mintWithCollateral` logic                                                                   |
| 21    | `previewWithdraw()` uses floor rounding                                                 | Updated to use parent's implementation, e.g. `super.previewWithdraw()`                                   |
| 22    | redemption queue is not ordered queue                                                   | PENDING ACTION                                                                                           |
| 23    | user can spam create and cancel redemption request                                      | PENDING ACTION                                                                                           |
| 24    | `_completeRedemption()` doesn't re-check collateral                                     | Added pre-check for sufficient collateral before state changes                                           |
| 25    | Queued redemptions not validated against updated `minRedeemAmount`                      | Documented as intentional (grandfathered)                                                                |
| 26    | user can cancel request at any time                                                     | PENDING ACTION                                                                                           |
| 27    | Queued redemptions can become non-completable if asset removed                          | Added comprehensive documentation and warnings                                                           |

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
