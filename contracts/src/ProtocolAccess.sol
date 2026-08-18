// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {IGrantlineContext} from "./Interfaces.sol";

/// @dev Module privileges follow Grantline's current coordinator instead of
/// requiring ownership transfers whenever the coordinator is replaced.
abstract contract GrantlineModuleAccess {
    error NotAdminController(address caller);

    address internal _grantline;

    function grantline() public view virtual returns (address) {
        return _grantline;
    }

    modifier onlyAdminController() {
        if (msg.sender != IGrantlineContext(_grantline).adminController()) {
            revert NotAdminController(msg.sender);
        }
        _;
    }
}

/// @dev Grantline uses OpenZeppelin's upgradeable ownership implementation but
/// deliberately does not expose a protocol-admin renunciation path.
abstract contract GrantlineOwnable2StepUpgradeable is Ownable2StepUpgradeable {
    error OwnershipRenunciationDisabled();

    function renounceOwnership() public pure override {
        revert OwnershipRenunciationDisabled();
    }
}
