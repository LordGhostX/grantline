// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC1822Proxiable} from "@openzeppelin/contracts/interfaces/draft-IERC1822.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ComponentTypes} from "./ComponentTypes.sol";
import {IOwnable2Step, IVault, IVaultFactory} from "./Interfaces.sol";
import {GrantlineOwnable2StepUpgradeable} from "./ProtocolAccess.sol";

contract VaultFactory is Initializable, GrantlineOwnable2StepUpgradeable, UUPSUpgradeable, IVaultFactory {
    error InvalidAddress();
    error InvalidImplementation(address implementation);
    error NotGrantline(address caller);

    event VaultCreated(
        address indexed vault, address indexed controller, address indexed implementation, uint64 implementationVersion
    );
    event VaultImplementationUpdated(
        address indexed previousImplementation, address indexed newImplementation, uint64 implementationVersion
    );
    event UpgradeAuthorityUpdated(address indexed previousAuthority, address indexed newAuthority);

    address public grantline;
    address public executor;
    address public override upgradeAuthority;
    address public override vaultImplementation;
    uint64 public override vaultImplementationVersion;
    mapping(address => bool) public override isVault;
    address[] private _vaults;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address grantlineAddress,
        address vaultImplementationAddress,
        uint64 implementationVersion,
        address executorAddress,
        address moduleOwnerAddress,
        address upgradeAuthorityAddress
    ) external initializer {
        if (grantlineAddress == address(0)) revert InvalidAddress();
        if (executorAddress == address(0) || executorAddress.code.length == 0) {
            revert InvalidAddress();
        }
        if (moduleOwnerAddress == address(0) || moduleOwnerAddress.code.length == 0) revert InvalidAddress();
        if (upgradeAuthorityAddress == address(0) || upgradeAuthorityAddress.code.length == 0) revert InvalidAddress();
        if (vaultImplementationAddress == address(0)) revert InvalidImplementation(vaultImplementationAddress);
        _validateVaultImplementation(
            vaultImplementationAddress,
            implementationVersion,
            grantlineAddress,
            executorAddress,
            upgradeAuthorityAddress
        );
        grantline = grantlineAddress;
        executor = executorAddress;
        upgradeAuthority = upgradeAuthorityAddress;
        vaultImplementation = vaultImplementationAddress;
        vaultImplementationVersion = implementationVersion;
        __Ownable_init(moduleOwnerAddress);
        __Ownable2Step_init();
    }

    function version() external pure override returns (uint64) {
        return 1;
    }

    function componentType() external pure override returns (bytes32) {
        return ComponentTypes.VAULT_FACTORY;
    }

    function createVault(address controller) external override returns (address vault) {
        _onlyGrantline();
        if (controller == address(0)) revert InvalidAddress();
        bytes memory initializationData = abi.encodeCall(IVault.initialize, (grantline, executor, upgradeAuthority));
        vault = address(new ERC1967Proxy(vaultImplementation, initializationData));
        isVault[vault] = true;
        _vaults.push(vault);
        emit VaultCreated(vault, controller, vaultImplementation, vaultImplementationVersion);
    }

    function validateVaultImplementation(address implementation, uint64 implementationVersion) external override {
        _checkOwner();
        _validateVaultImplementation(implementation, implementationVersion, grantline, executor, upgradeAuthority);
    }

    function setVaultImplementation(address implementation, uint64 implementationVersion) external override {
        _checkOwner();
        if (implementation == address(0)) revert InvalidImplementation(implementation);
        _validateVaultImplementation(implementation, implementationVersion, grantline, executor, upgradeAuthority);
        address previousImplementation = vaultImplementation;
        vaultImplementation = implementation;
        vaultImplementationVersion = implementationVersion;
        emit VaultImplementationUpdated(previousImplementation, implementation, implementationVersion);
    }

    function setUpgradeAuthority(address newUpgradeAuthority) external override {
        _checkOwner();
        if (newUpgradeAuthority == address(0) || newUpgradeAuthority.code.length == 0) revert InvalidAddress();
        address previousAuthority = upgradeAuthority;
        upgradeAuthority = newUpgradeAuthority;
        emit UpgradeAuthorityUpdated(previousAuthority, newUpgradeAuthority);
    }

    function vaultCount() external view override returns (uint256) {
        return _vaults.length;
    }

    function vaultAt(uint256 index) external view override returns (address) {
        return _vaults[index];
    }

    function _requireUUPSImplementation(address implementation) private view {
        if (implementation == address(0) || implementation.code.length == 0) {
            revert InvalidImplementation(implementation);
        }
        try IERC1822Proxiable(implementation).proxiableUUID() returns (bytes32 slot) {
            if (slot != ERC1967Utils.IMPLEMENTATION_SLOT) {
                revert InvalidImplementation(implementation);
            }
        } catch {
            revert InvalidImplementation(implementation);
        }
    }

    function _validateVaultImplementation(
        address implementation,
        uint64 expectedVersion,
        address grantlineAddress,
        address executorAddress,
        address upgradeAuthorityAddress
    ) private {
        if (implementation == address(0)) revert InvalidImplementation(implementation);
        _requireUUPSImplementation(implementation);
        try IVault(implementation).componentType() returns (bytes32 actualType) {
            if (actualType != ComponentTypes.VAULT) revert InvalidImplementation(implementation);
        } catch {
            revert InvalidImplementation(implementation);
        }
        try IVault(implementation).pauseInterfaceVersion() returns (uint64 interfaceVersion) {
            if (interfaceVersion != 1) revert InvalidImplementation(implementation);
        } catch {
            revert InvalidImplementation(implementation);
        }
        try IVault(implementation).paused() returns (bool implementationPaused) {
            if (implementationPaused) revert InvalidImplementation(implementation);
        } catch {
            revert InvalidImplementation(implementation);
        }
        if (
            !_hasSelector(implementation, IVault.pause.selector)
                || !_hasSelector(implementation, IVault.unpause.selector)
                || !_hasSelector(implementation, IVault.executeSwap.selector)
                || !_hasSelector(implementation, IVault.receiveNativeFromSwapAdapter.selector)
        ) {
            revert InvalidImplementation(implementation);
        }
        _requireImplementationVersion(implementation, expectedVersion);

        address probe = address(
            new ERC1967Proxy(
                implementation,
                abi.encodeCall(IVault.initialize, (grantlineAddress, executorAddress, upgradeAuthorityAddress))
            )
        );
        if (
            IVault(probe).componentType() != ComponentTypes.VAULT || IVault(probe).version() != expectedVersion
                || IVault(probe).owner() != grantlineAddress || IVault(probe).authority() != executorAddress
                || IVault(probe).upgradeAuthority() != upgradeAuthorityAddress || IVault(probe).paused()
                || IOwnable2Step(probe).pendingOwner() != address(0)
        ) {
            revert InvalidImplementation(implementation);
        }
    }

    function _hasSelector(address target, bytes4 selector) private view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(target)
        }
        bytes memory code = new bytes(size);
        assembly {
            extcodecopy(target, add(code, 32), 0, size)
        }
        for (uint256 index; index + 4 <= size; index++) {
            bytes4 candidate;
            assembly {
                candidate := mload(add(add(code, 32), index))
            }
            if (candidate == selector) return true;
        }
        return false;
    }

    function _requireImplementationVersion(address implementation, uint64 expectedVersion) private pure {
        try IVault(implementation).version() returns (uint64 actualVersion) {
            if (actualVersion != expectedVersion) {
                revert InvalidImplementation(implementation);
            }
        } catch {
            revert InvalidImplementation(implementation);
        }
    }

    function _onlyGrantline() private view {
        if (msg.sender != grantline) revert NotGrantline(msg.sender);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
