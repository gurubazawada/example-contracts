// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Minimal interface to interact with the Swap contract.
interface ISwap {
    function swap(
        address inputToken,
        uint256 amount,
        address targetToken,
        bytes calldata recipient,
        bool withdrawFlag
    ) external;
}

/**
 * @title DelayedSwapExecutor
 * @notice This contract allows users to schedule a swap that will be executed after a delay,
 *         and it includes additional functionality:
 *         - Cancel scheduled swaps (with token refund)
 *         - Reschedule pending swaps
 *         - Batch execution of multiple swaps
 */
contract DelayedSwapExecutor {
    // Order statuses.
    enum OrderStatus { Pending, Executed, Cancelled }
    
    // Structure to hold details of each scheduled swap.
    struct ScheduledSwap {
        address user;
        address inputToken;
        uint256 amount;
        address targetToken;
        bytes recipient;
        bool withdrawFlag;
        uint256 executeAfter; // Timestamp after which the swap can be executed.
        OrderStatus status;
    }

    uint256 public nextOrderId;
    mapping(uint256 => ScheduledSwap) public orders;

    // Address of the deployed Swap contract.
    address public swapContract;

    event SwapScheduled(
        uint256 indexed orderId,
        address indexed user,
        address inputToken,
        uint256 amount,
        address targetToken,
        uint256 executeAfter
    );
    event SwapExecuted(uint256 indexed orderId, address indexed user);
    event SwapCancelled(uint256 indexed orderId, address indexed user);
    event SwapRescheduled(uint256 indexed orderId, address indexed user, uint256 newExecuteAfter);

    /**
     * @notice Sets the Swap contract address.
     * @param _swapContract The address of the Swap contract.
     */
    constructor(address _swapContract) {
        require(_swapContract != address(0), "Invalid swap contract address");
        swapContract = _swapContract;
    }

    /**
     * @notice Schedules a swap by depositing tokens.
     * @param inputToken The token to swap from.
     * @param amount The amount of tokens to swap.
     * @param targetToken The token to swap to.
     * @param recipient The recipient (encoded as bytes) for the swap.
     * @param withdrawFlag A flag indicating if the swap should withdraw to a connected chain.
     * @param delayInSeconds The delay (in seconds) after which the swap can be executed.
     */
    function scheduleSwap(
        address inputToken,
        uint256 amount,
        address targetToken,
        bytes calldata recipient,
        bool withdrawFlag,
        uint256 delayInSeconds
    ) external {
        require(amount > 0, "Amount must be > 0");
        require(
            IERC20(inputToken).transferFrom(msg.sender, address(this), amount),
            "Token transfer failed"
        );

        uint256 executeAfter = block.timestamp + delayInSeconds;

        orders[nextOrderId] = ScheduledSwap({
            user: msg.sender,
            inputToken: inputToken,
            amount: amount,
            targetToken: targetToken,
            recipient: recipient,
            withdrawFlag: withdrawFlag,
            executeAfter: executeAfter,
            status: OrderStatus.Pending
        });

        emit SwapScheduled(nextOrderId, msg.sender, inputToken, amount, targetToken, executeAfter);
        nextOrderId++;
    }

    /**
     * @notice Executes a scheduled swap if the specified delay has passed.
     * @param orderId The id of the scheduled swap to execute.
     */
    function executeSwap(uint256 orderId) public {
        ScheduledSwap storage order = orders[orderId];
        require(order.status == OrderStatus.Pending, "Order not pending");
        require(block.timestamp >= order.executeAfter, "Swap not ready for execution");

        // Approve the Swap contract to spend the tokens held by this contract.
        require(
            IERC20(order.inputToken).approve(swapContract, order.amount),
            "Approval failed"
        );

        // Call the Swap contract.
        ISwap(swapContract).swap(
            order.inputToken,
            order.amount,
            order.targetToken,
            order.recipient,
            order.withdrawFlag
        );

        order.status = OrderStatus.Executed;
        emit SwapExecuted(orderId, order.user);
    }

    /**
     * @notice Executes multiple scheduled swaps in one transaction.
     * @param orderIds An array of order IDs to execute.
     */
    function batchExecuteSwaps(uint256[] calldata orderIds) external {
        for (uint256 i = 0; i < orderIds.length; i++) {
            // Only execute if pending and ready.
            if (orders[orderIds[i]].status == OrderStatus.Pending &&
                block.timestamp >= orders[orderIds[i]].executeAfter) {
                executeSwap(orderIds[i]);
            }
        }
    }

    /**
     * @notice Cancels a pending swap and refunds the tokens.
     * @param orderId The id of the scheduled swap to cancel.
     */
    function cancelSwap(uint256 orderId) external {
        ScheduledSwap storage order = orders[orderId];
        require(order.status == OrderStatus.Pending, "Order not pending");
        require(msg.sender == order.user, "Not order owner");

        order.status = OrderStatus.Cancelled;
        require(
            IERC20(order.inputToken).transfer(order.user, order.amount),
            "Refund failed"
        );

        emit SwapCancelled(orderId, order.user);
    }

    /**
     * @notice Reschedules a pending swap by updating its execution time.
     * @param orderId The id of the scheduled swap.
     * @param newDelayInSeconds The new delay (in seconds) from now.
     */
    function rescheduleSwap(uint256 orderId, uint256 newDelayInSeconds) external {
        ScheduledSwap storage order = orders[orderId];
        require(order.status == OrderStatus.Pending, "Order not pending");
        require(msg.sender == order.user, "Not order owner");

        uint256 newExecuteAfter = block.timestamp + newDelayInSeconds;
        order.executeAfter = newExecuteAfter;
        emit SwapRescheduled(orderId, order.user, newExecuteAfter);
    }
}
