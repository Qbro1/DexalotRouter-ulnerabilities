// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import "@openzeppelin-v5/utils/structs/EnumerableSet.sol";
import "@openzeppelin-v5/token/ERC20/IERC20.sol";
import "@openzeppelin-v5/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-v5/utils/ReentrancyGuardTransient.sol";
import "@openzeppelin-upgradeable-v5/access/extensions/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin-upgradeable-v5/proxy/utils/UUPSUpgradeable.sol";

import "./interfaces/IDexalotRFQ.sol";

contract DexalotRouter is AccessControlEnumerableUpgradeable, UUPSUpgradeable, ReentrancyGuardTransient {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    bytes4 private constant PARTIAL_SWAP_SELECTOR = 0x944bda00;
    bytes4 private constant SIMPLE_SWAP_SELECTOR = 0x6c75d6f5;
    uint256 private constant TAKER_ASSET_OFFSET = 4 + 32 * 3;
    uint256 private constant MAKER_OFFSET = 4 + 32 * 4;
    uint256 private constant TAKER_AMOUNT_OFFSET = 4 + 32 * 7;
    uint256 private constant TAKER_PARTIAL_AMOUNT_OFFSET = 4 + 32 * 8 + 32;

    bytes32 public constant VERSION = bytes32("1.1.1");
    EnumerableSet.AddressSet private allowedRFQs;

    uint256[50] private __gap;

    event AllowedRFQUpdated(address indexed rfq, bool allowed);

    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner) public initializer {
        require(_owner != address(0), "DR-SAZ-01");
        __AccessControlEnumerable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
    }

    function multiPartialSwap(
        IDexalotRFQ.Order calldata _orderA,
        bytes calldata _signatureA,
        uint256 _takerAmountA,
        IDexalotRFQ.Order calldata _orderB,
        bytes calldata _signatureB
    ) external payable nonReentrant {
        require(_orderA.maker != address(0) && allowedRFQs.contains(_orderA.maker), "DR-IRMA-01");
        require(_orderB.maker != address(0) && allowedRFQs.contains(_orderB.maker), "DR-IRMB-01");
        require(_orderA.makerAsset == _orderB.takerAsset, "DR-ASMTA-01");
        address destTraderA = address(uint160(_orderA.nonceAndMeta >> 96));
        require(destTraderA == msg.sender, "DR-DTIT-01"); // Изменено на msg.sender
        uint256 preBal = _orderA.makerAsset == address(0)
            ? address(this).balance
            : IERC20(_orderA.makerAsset).balanceOf(address(this));

        if (_orderA.takerAsset != address(0)) {
            require(msg.value == 0, "DR-NFES-01");
            IERC20(_orderA.takerAsset).safeTransferFrom(msg.sender, _orderA.maker, _takerAmountA);
        }

        bytes memory callDataA = abi.encodeWithSelector(PARTIAL_SWAP_SELECTOR, _orderA, _signatureA, _takerAmountA);
        callDataA = abi.encodePacked(callDataA, msg.sender);
        (bool success, bytes memory returnData) = payable(_orderA.maker).call{value: msg.value, gas: gasleft()}(callDataA);
        if (!success) _bubbleRevert(returnData, "DR-PSA-01");

        uint256 takerAmountB;
        bool isHopNative = (_orderA.makerAsset == address(0));

        if (!isHopNative) {
            IERC20 bInputAsset = IERC20(_orderA.makerAsset);
            takerAmountB = bInputAsset.balanceOf(address(this)) - preBal;
            bInputAsset.safeTransfer(_orderB.maker, takerAmountB);
        } else {
            takerAmountB = address(this).balance + msg.value - preBal;
        }

        bytes memory callDataB = abi.encodeWithSelector(PARTIAL_SWAP_SELECTOR, _orderB, _signatureB, takerAmountB);
        callDataB = abi.encodePacked(callDataB, msg.sender);
        (success, returnData) = payable(_orderB.maker).call{value: isHopNative ? takerAmountB : 0, gas: gasleft()}(callDataB);
        if (!success) _bubbleRevert(returnData, "DR-PSB-01");
    }

    function setAllowedRFQ(address _mainnetRFQ, bool _allowed) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_mainnetRFQ != address(0), "DR-SAZ-01");
        if (_allowed) {
            require(!allowedRFQs.contains(_mainnetRFQ), "DR-RFQA-01"); // Проверка на дубликат
            allowedRFQs.add(_mainnetRFQ);
        } else {
            allowedRFQs.remove(_mainnetRFQ);
        }
        emit AllowedRFQUpdated(_mainnetRFQ, _allowed);
    }

    function retrieveToken(address _token, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_token == address(0)) {
            (bool success, ) = msg.sender.call{value: _amount}("");
            require(success, "DR-TF-01");
            return;
        }
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

    function isAllowedRFQ(address _mainnetRFQ) external view returns (bool) {
        return allowedRFQs.contains(_mainnetRFQ);
    }

    function getAllowedRFQs() external view returns (address[] memory) {
        return allowedRFQs.values();
    }

    function getAllowedRFQsPaginated(uint256 _startIndex, uint256 _pageSize) external view returns (address[] memory) {
        uint256 length = _pageSize;
        uint256 total = allowedRFQs.length();
        if (_startIndex + _pageSize > total) {
            length = total - _startIndex;
        }
        address[] memory page = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            page[i] = allowedRFQs.at(_startIndex + i);
        }
        return page;
    }

    function numberOfAllowedRFQs() external view returns (uint256) {
        return allowedRFQs.length();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function _bubbleRevert(bytes memory _returnData, string memory _defaultMsg) internal pure {
        if (_returnData.length > 0) {
            assembly {
                let size := mload(_returnData)
                revert(add(32, _returnData), size)
            }
        } else {
            revert(_defaultMsg);
        }
    }

    fallback() external payable {
        bytes4 selector = msg.sig;
        if (selector != PARTIAL_SWAP_SELECTOR && selector != SIMPLE_SWAP_SELECTOR) {
            revert("DR-FSNW-01");
        }

        address payable targetImplementation;
        assembly {
            targetImplementation := calldataload(MAKER_OFFSET)
        }

        require(targetImplementation != address(0) && allowedRFQs.contains(targetImplementation), "DR-IRMA-01");

        address takerAsset;
        uint256 amount;
        uint256 amountOffset = selector == PARTIAL_SWAP_SELECTOR ? TAKER_PARTIAL_AMOUNT_OFFSET : TAKER_AMOUNT_OFFSET;
        assembly {
            takerAsset := calldataload(TAKER_ASSET_OFFSET)
            amount := calldataload(amountOffset)
        }

        if (takerAsset != address(0)) {
            require(msg.value == 0, "DR-NFES-01");
            IERC20(takerAsset).safeTransferFrom(msg.sender, targetImplementation, amount);
        } else if (msg.value > 0) {
            // Для native ETH в fallback()
            (bool success, ) = targetImplementation.call{value: msg.value, gas: gasleft()}(msg.data);
            if (!success) {
                assembly {
                    let returndata_size := returndatasize()
                    returndatacopy(0, 0, returndata_size)
                    revert(0, returndata_size)
                }
            }
            assembly {
                let returndata_size := returndatasize()
                returndatacopy(0, 0, returndata_size)
                return(0, returndata_size)
            }
        }

        bytes memory newCallData = abi.encodePacked(msg.data, msg.sender);
        (bool success, ) = targetImplementation.call{value: msg.value, gas: gasleft()}(newCallData);
        if (!success) {
            assembly {
                let returndata_size := returndatasize()
                returndatacopy(0, 0, returndata_size)
                revert(0, returndata_size)
            }
        }

        assembly {
            let returndata_size := returndatasize()
            returndatacopy(0, 0, returndata_size)
            return(0, returndata_size)
        }
    }

    receive() external payable {
        require(allowedRFQs.contains(msg.sender), "DR-IRMA-01");
    }
}