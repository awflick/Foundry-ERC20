// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

contract ManualToken {

    mapping(address => uint256) private s_balance;

    function name() public pure returns (string memory) {
        return "ManualToken";
    }

    function totalSupply() public pure returns (uint256) {
        return 100 ether;
    }

    function decimals() public pure returns (uint8) {
        return 18;
    }

    function balanceOf(address owner) public view returns (uint256 balance) {
        return s_balance[owner];
    }

    function transfer(address _to, uint256 _amount) public {
        uint256 previousBalance = balanceOf(msg.sender) + balanceOf(_to);
        s_balance[msg.sender] -= _amount;
        s_balance[_to] += _amount;
        require(balanceOf(msg.sender) + balanceOf(_to) == previousBalance);
    }


}

