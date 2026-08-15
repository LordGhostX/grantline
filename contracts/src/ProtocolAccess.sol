// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

/// @dev Grantline uses OpenZeppelin's upgradeable ownership implementation but
/// deliberately does not expose a protocol-admin renunciation path.
abstract contract GrantlineOwnable2StepUpgradeable is Ownable2StepUpgradeable {
    error OwnershipRenunciationDisabled();

    function renounceOwnership() public pure override {
        revert OwnershipRenunciationDisabled();
    }
}
