// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { CuStableCoin } from "../../src/CuStableCoin.sol";
import { Test, console } from "forge-std/Test.sol";
import { StdCheats } from "forge-std/StdCheats.sol";

contract DecentralizedStablecoinTest is StdCheats, Test {
    CuStableCoin cu;
    address owner = address(1);

    function setUp() public {
        cu = new CuStableCoin(owner);
    }

    function testMustMintMoreThanZero() public {
        vm.prank(cu.owner());
        vm.expectRevert();
        cu.mint(address(this), 0);
    }

    function testMustBurnMoreThanZero() public {
        vm.startPrank(cu.owner());
        cu.mint(address(this), 100);
        vm.expectRevert();
        cu.burn(0);
        vm.stopPrank();
    }

    function testCantBurnMoreThanYouHave() public {
        vm.startPrank(cu.owner());
        cu.mint(address(this), 100);
        vm.expectRevert();
        cu.burn(101);
        vm.stopPrank();
    }

    function testCantMintToZeroAddress() public {
        vm.startPrank(cu.owner());
        vm.expectRevert();
        cu.mint(address(0), 100);
        vm.stopPrank();
    }
}