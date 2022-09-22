pragma solidity 0.8.4;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract MockUSDT is ERC20 {
    uint256 public constant ONE_MILLION = 1000000e6;

    constructor() ERC20("MockUSDT", "MUSDT") {
        _mint(msg.sender, ONE_MILLION);
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    function mint(uint256 amount) external {
        _mint(msg.sender, amount);
    }
}
