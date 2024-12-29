// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract CuStableCoin is ERC20Burnable, Ownable {
    uint256 constant MAX_SUPPLY = 1000000 * 10 ** 18;
    // Custom errors for gas efficiency

    error CuCoin_BurnAmountIsMoreThanBalance();
    error CuCoin__ZeroAddressDetected();
    error CuCoin__AmountMustBeMoreThanZero();
    error CuCoin__ExceedsMaxSupply();

    // Events for traceability
    event TokensMinted(address indexed to, uint256 amount);
    event TokensBurned(address indexed from, uint256 amount);

    // Constructor to initialize the token and set the owner
    constructor(address initialOwner) ERC20("CuCoin", "Cu") Ownable(initialOwner) {}

    // Mint function restricted to the owner
    function mint(address _to, uint256 _amount) external onlyOwner {
        if (_to == address(0)) {
            revert CuCoin__ZeroAddressDetected();
        }
        if (_amount == 0) {
            revert CuCoin__AmountMustBeMoreThanZero();
        }
        if (totalSupply() > MAX_SUPPLY) {
            revert CuCoin__ExceedsMaxSupply();
        }
        _mint(_to, _amount);
        emit TokensMinted(_to, _amount);
    }

    // Burn function restricted to the owner
    function burn(uint256 _amount) public override onlyOwner {
        if (_amount == 0) {
            revert CuCoin__AmountMustBeMoreThanZero();
        }
        //use the parent class(burnable ERC2O contract) burn function
        super.burn(_amount);
        emit TokensBurned(msg.sender, _amount);
    }
}
