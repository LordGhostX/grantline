// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC1822Proxiable} from "@openzeppelin/contracts/interfaces/draft-IERC1822.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ComponentTypes} from "./ComponentTypes.sol";
import {IVault, IVaultFactory} from "./Interfaces.sol";
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

    address public grantline;
    address public executor;
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
        address executorAddress
    ) external initializer {
        if (grantlineAddress == address(0)) revert InvalidAddress();
        if (executorAddress == address(0) || executorAddress.code.length == 0) {
            revert InvalidAddress();
        }
        if (vaultImplementationAddress == address(0)) revert InvalidImplementation(vaultImplementationAddress);
        _requireVaultImplementation(vaultImplementationAddress, implementationVersion);
        grantline = grantlineAddress;
        executor = executorAddress;
        vaultImplementation = vaultImplementationAddress;
        vaultImplementationVersion = implementationVersion;
        __Ownable_init(grantlineAddress);
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
        bytes memory initializationData = abi.encodeCall(IVault.initialize, (grantline, executor));
        vault = address(new ERC1967Proxy(vaultImplementation, initializationData));
        isVault[vault] = true;
        _vaults.push(vault);
        emit VaultCreated(vault, controller, vaultImplementation, vaultImplementationVersion);
    }

    function setVaultImplementation(address implementation, uint64 implementationVersion) external override {
        _onlyGrantline();
        if (implementation == address(0)) revert InvalidImplementation(implementation);
        _requireVaultImplementation(implementation, implementationVersion);
        address previousImplementation = vaultImplementation;
        vaultImplementation = implementation;
        vaultImplementationVersion = implementationVersion;
        emit VaultImplementationUpdated(previousImplementation, implementation, implementationVersion);
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

    function _requireVaultImplementation(address implementation, uint64 expectedVersion) private view {
        if (implementation == address(0)) revert InvalidImplementation(implementation);
        _requireUUPSImplementation(implementation);
        try IVault(implementation).componentType() returns (bytes32 actualType) {
            if (actualType != ComponentTypes.VAULT) revert InvalidImplementation(implementation);
        } catch {
            revert InvalidImplementation(implementation);
        }
        _requireImplementationVersion(implementation, expectedVersion);
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
