// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../src/DexalotRouter.sol";
import "../src/interfaces/IDexalotRFQ.sol";

contract MockRFQ is IDexalotRFQ {
    function partialSwap(Order calldata, bytes calldata, uint256) external payable returns (bytes memory) {
        return abi.encode("partialSwap");
    }
    function simpleSwap(Order calldata, bytes calldata) external payable returns (bytes memory) {
        return abi.encode("simpleSwap");
    }
}

contract DexalotRouterTest is Test {
    DexalotRouter router;
    MockRFQ mockRFQ;
    address owner = address(1);
    address user = address(2);

    function setUp() public {
        vm.startPrank(owner);
        router = new DexalotRouter();
        router.initialize(owner);
        mockRFQ = new MockRFQ();
        router.setAllowedRFQ(address(mockRFQ), true);
        vm.stopPrank();
    }

    function test_AllowedRFQUpdate() public {
        vm.prank(owner);
        router.setAllowedRFQ(address(3), true);
        assertTrue(router.isAllowedRFQ(address(3)), "RFQ not added");
    }

    function test_FallbackRevertOnInvalidSelector() public {
        vm.prank(user);
        vm.expectRevert("DR-FSNW-01");
        (bool success, ) = address(router).call(hex"12345678");
        assertFalse(success);
    }

    function test_FallbackRevertOnInvalidRFQ() public {
        vm.prank(user);
        vm.expectRevert("DR-IRMA-01");
        (bool success, ) = address(router).call(abi.encodeWithSelector(bytes4(0x944bda00), IDexalotRFQ.Order(0), "", 0));
        assertFalse(success);
    }
}