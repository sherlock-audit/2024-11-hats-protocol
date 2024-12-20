// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity >=0.7.0 <0.9.0;

import { Enum } from "../../lib/safe-interfaces/ISafe.sol";
import { IAvatar } from "../../../lib/zodiac/contracts/interfaces/IAvatar.sol";

/// @title ModifierUnowned - A contract that sits between a Module and an Avatar and enforces some additional logic.
/// @author Gnosis Guild
/// @dev Modified from Zodiac's Modifier to enable inheriting contracts to use their preferred owner logic
/// and to simplify the moduleOnly modifier.
/// https://github.com/gnosisguild/zodiac/blob/5165ce2f377c291d4bfe71d21948d9df0fdf6224/contracts/core/Modifier.sol
/// Modifications:
/// - Removed Module, SignatureChecker, and ExecutionTracker inheritance
/// - Removed owner logic
/// - Simplified moduleOnly modifier
abstract contract ModifierUnowned is IAvatar {
  address internal constant SENTINEL_MODULES = address(0x1);
  /// Mapping of modules.
  mapping(address => address) internal modules;

  /// `sender` is not an authorized module.
  /// @param sender The address of the sender.
  error NotAuthorized(address sender);

  /// `module` is invalid.
  error InvalidModule(address module);

  /// `pageSize` is invalid.
  error InvalidPageSize();

  /// `module` is already disabled.
  error AlreadyDisabledModule(address module);

  /// `module` is already enabled.
  error AlreadyEnabledModule(address module);

  /// @dev `setModules()` was already called.
  error SetupModulesAlreadyCalled();

  /*
    --------------------------------------------------
    You must override both of the following virtual functions,
    execTransactionFromModule() and execTransactionFromModuleReturnData().
    It is recommended that implementations of both functions make use the 
    onlyModule modifier.
    */

  /// @dev Passes a transaction to the modifier.
  /// @notice Can only be called by enabled modules.
  /// @param to Destination address of module transaction.
  /// @param value Ether value of module transaction.
  /// @param data Data payload of module transaction.
  /// @param operation Operation type of module transaction.
  function execTransactionFromModule(address to, uint256 value, bytes calldata data, Enum.Operation operation)
    public
    virtual
    returns (bool success);

  /// @dev Passes a transaction to the modifier, expects return data.
  /// @notice Can only be called by enabled modules.
  /// @param to Destination address of module transaction.
  /// @param value Ether value of module transaction.
  /// @param data Data payload of module transaction.
  /// @param operation Operation type of module transaction.
  function execTransactionFromModuleReturnData(address to, uint256 value, bytes calldata data, Enum.Operation operation)
    public
    virtual
    returns (bool success, bytes memory returnData);

  /*
    --------------------------------------------------
    */

  /// @dev Simplified version of the moduleOnly modifier from Zodiac
  modifier moduleOnly() {
    if (modules[msg.sender] == address(0)) revert NotAuthorized(msg.sender);
    _;
  }

  /// @notice Disables a module on the modifier.
  /// @dev Should be overridden to restrict access, such as to an owner
  /// @param prevModule Module that pointed to the module to be removed in the linked list.
  /// @param module Module to be removed.
  function disableModule(address prevModule, address module) public virtual {
    if (module == address(0) || module == SENTINEL_MODULES) {
      revert InvalidModule(module);
    }
    if (modules[prevModule] != module) revert AlreadyDisabledModule(module);
    modules[prevModule] = modules[module];
    modules[module] = address(0);
    emit DisabledModule(module);
  }

  /// @notice Enables a module that can add transactions to the queue
  /// @dev Should be overridden to restrict access, such as to an owner
  /// @param module Address of the module to be enabled
  function _enableModule(address module) internal virtual {
    if (module == address(0) || module == SENTINEL_MODULES) {
      revert InvalidModule(module);
    }
    if (modules[module] != address(0)) revert AlreadyEnabledModule(module);
    modules[module] = modules[SENTINEL_MODULES];
    modules[SENTINEL_MODULES] = module;
    emit EnabledModule(module);
  }

  /// @dev Returns if an module is enabled
  /// @return True if the module is enabled
  function isModuleEnabled(address _module) public view returns (bool) {
    return SENTINEL_MODULES != _module && modules[_module] != address(0);
  }

  /// @dev Returns array of modules.
  ///      If all entries fit into a single page, the next pointer will be 0x1.
  ///      If another page is present, next will be the last element of the returned array.
  /// @param start Start of the page. Has to be a module or start pointer (0x1 address)
  /// @param pageSize Maximum number of modules that should be returned. Has to be > 0
  /// @return array Array of modules.
  /// @return next Start of the next page.
  function getModulesPaginated(address start, uint256 pageSize)
    external
    view
    returns (address[] memory array, address next)
  {
    if (start != SENTINEL_MODULES && !isModuleEnabled(start)) {
      revert InvalidModule(start);
    }
    if (pageSize == 0) {
      revert InvalidPageSize();
    }

    // Init array with max page size
    array = new address[](pageSize);

    // Populate return array
    uint256 moduleCount = 0;
    next = modules[start];
    while (next != address(0) && next != SENTINEL_MODULES && moduleCount < pageSize) {
      array[moduleCount] = next;
      next = modules[next];
      moduleCount++;
    }

    // Because of the argument validation we can assume that
    // the `currentModule` will always be either a module address
    // or sentinel address (aka the end). If we haven't reached the end
    // inside the loop, we need to set the next pointer to the last element
    // because it skipped over to the next module which is neither included
    // in the current page nor won't be included in the next one
    // if you pass it as a start.
    if (next != SENTINEL_MODULES) {
      next = array[moduleCount - 1];
    }
    // Set correct size of returned array
    // solhint-disable-next-line no-inline-assembly
    assembly {
      mstore(array, moduleCount)
    }
  }

  /// @dev Initializes the modules linked list.
  /// @notice Should be called as part of the `setUp` / initializing function and can only be called once.
  function setupModules() internal {
    if (modules[SENTINEL_MODULES] != address(0)) {
      revert SetupModulesAlreadyCalled();
    }
    modules[SENTINEL_MODULES] = SENTINEL_MODULES;
  }
}
