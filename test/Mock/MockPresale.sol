pragma solidity 0.8.4;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract MockPresale is ERC20 {
    uint256 public constant ONE_MILLION = 1000000e18;

    constructor() ERC20("MockPresale", "MPS") {
        _mint(msg.sender, ONE_MILLION);
    }

    function mint(uint256 amount) external {
        _mint(msg.sender, amount);
    }
}
