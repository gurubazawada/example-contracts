// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

contract StatTracker {
    struct TokenSwapRecord {
        address sender;
        bytes recipient;
        address inputToken;
        address targetToken;
        uint256 inputAmount;
        uint256 outputAmount;
        uint256 timestamp;
    }
    
    struct MultiHopSwapRecord {
        address sender;
        address inputToken;
        address outputToken;
        uint256 inputAmount;
        uint256 outputAmount;
        uint256 feeCollected;
        uint256 timestamp;
    }
    
    TokenSwapRecord[] public tokenSwapRecords;
    MultiHopSwapRecord[] public multiHopSwapRecords;
    
    event TokenSwapLogged(
        address indexed sender,
        bytes recipient,
        address indexed inputToken,
        address indexed targetToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 timestamp
    );
    
    event MultiHopSwapLogged(
        address indexed sender,
        address indexed inputToken,
        address indexed outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 feeCollected,
        uint256 timestamp
    );
    
    /**
     * @notice Records a standard token swap.
     */
    function recordTokenSwap(
        address sender,
        bytes calldata recipient,
        address inputToken,
        address targetToken,
        uint256 inputAmount,
        uint256 outputAmount
    ) external {
        TokenSwapRecord memory record = TokenSwapRecord({
            sender: sender,
            recipient: recipient,
            inputToken: inputToken,
            targetToken: targetToken,
            inputAmount: inputAmount,
            outputAmount: outputAmount,
            timestamp: block.timestamp
        });
        tokenSwapRecords.push(record);
        emit TokenSwapLogged(sender, recipient, inputToken, targetToken, inputAmount, outputAmount, block.timestamp);
    }
    
    /**
     * @notice Records a multi-hop swap.
     */
    function recordMultiHopSwap(
        address sender,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 feeCollected
    ) external {
        MultiHopSwapRecord memory record = MultiHopSwapRecord({
            sender: sender,
            inputToken: inputToken,
            outputToken: outputToken,
            inputAmount: inputAmount,
            outputAmount: outputAmount,
            feeCollected: feeCollected,
            timestamp: block.timestamp
        });
        multiHopSwapRecords.push(record);
        emit MultiHopSwapLogged(sender, inputToken, outputToken, inputAmount, outputAmount, feeCollected, block.timestamp);
    }
}
