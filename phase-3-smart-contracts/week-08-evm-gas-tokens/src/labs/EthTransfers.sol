// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title EthTransfers: why `transfer` and push-payments are dangerous
contract EthSender {
    error CallFailed();

    receive() external payable {}

    /// @dev Forwards only 2300 gas. Breaks for smart-contract wallets that do work on receipt.
    function payWithTransfer(address payable to, uint256 amount) external {
        to.transfer(amount);
    }

    /// @dev Forwards all remaining gas. Return value MUST be checked.
    function payWithCall(address payable to, uint256 amount) external {
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert CallFailed();
    }
}

/// @notice A "smart wallet" that logs every deposit. Uses more than 2300 gas on receipt.
contract LoggingWallet {
    uint256 public deposits;

    receive() external payable {
        deposits += 1; // an SSTORE costs far more than 2300 gas
    }
}

/// @notice A recipient that refuses ETH: think of a contract with no receive().
contract Refuser {
    receive() external payable {
        revert("no thanks");
    }
}

/// @notice PUSH refunds: one bad recipient blocks EVERYONE (denial of service).
contract PushRefunder {
    address payable[] public bidders;

    function bid() external payable {
        bidders.push(payable(msg.sender));
    }

    function refundAll(uint256 amountEach) external {
        for (uint256 i; i < bidders.length; ++i) {
            (bool ok,) = bidders[i].call{value: amountEach}("");
            require(ok, "refund failed"); // one Refuser reverts the whole loop
        }
    }
}

/// @notice PULL refunds: each user withdraws their own. One bad recipient hurts only itself.
contract PullRefunder {
    error NothingOwed();
    error CallFailed();

    mapping(address => uint256) public owed;

    function bid() external payable {
        owed[msg.sender] += msg.value;
    }

    function withdraw() external {
        uint256 amount = owed[msg.sender];
        if (amount == 0) revert NothingOwed();
        owed[msg.sender] = 0; // EFFECT before INTERACTION (re-entrancy safe)
        (bool ok,) = payable(msg.sender).call{value: amount}("");
        if (!ok) revert CallFailed();
    }
}
