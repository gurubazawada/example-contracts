// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
 
import {SystemContract, IZRC20} from "@zetachain/toolkit/contracts/SystemContract.sol";
import {SwapHelperLib} from "@zetachain/toolkit/contracts/SwapHelperLib.sol";
import {BytesHelperLib} from "@zetachain/toolkit/contracts/BytesHelperLib.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
 
import {RevertContext, RevertOptions} from "@zetachain/protocol-contracts/contracts/Revert.sol";
import "@zetachain/protocol-contracts/contracts/zevm/interfaces/UniversalContract.sol";
import "@zetachain/protocol-contracts/contracts/zevm/interfaces/IGatewayZEVM.sol";
import "@zetachain/protocol-contracts/contracts/zevm/interfaces/IWZETA.sol";
import {GatewayZEVM} from "@zetachain/protocol-contracts/contracts/zevm/GatewayZEVM.sol";
 
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
 
// Interface for the StatTracker contract.
interface IStatTracker {
    function recordTokenSwap(
        address sender,
        bytes calldata recipient,
        address inputToken,
        address targetToken,
        uint256 inputAmount,
        uint256 outputAmount
    ) external;
    
    function recordMultiHopSwap(
        address sender,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 feeCollected
    ) external;
}
 
contract Swap is
    UniversalContract,
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable
{
    address public uniswapRouter;
    GatewayZEVM public gateway;
    uint256 constant BITCOIN = 8332;
    uint256 constant BITCOIN_TESTNET = 18332;
    uint256 public gasLimit;
    
    // Fee for multi-hop swaps expressed in basis points (1/100th of a percent)
    uint256 public ownerFeeBasisPoints;
    
    // Stat Tracker contract instance
    IStatTracker public statTracker;
 
    error InvalidAddress();
    error Unauthorized();
    error ApprovalFailed();
    error TransferFailed(string);
    error InsufficientAmount(string);
 
    event TokenSwap(
        address sender,
        bytes indexed recipient,
        address indexed inputToken,
        address indexed targetToken,
        uint256 inputAmount,
        uint256 outputAmount
    );
    
    event MultiHopSwap(
        address indexed sender,
        address indexed inputToken,
        address indexed outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 feeCollected
    );
 
    modifier onlyGateway() {
        if (msg.sender != address(gateway)) revert Unauthorized();
        _;
    }
 
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
 
    function initialize(
        address payable gatewayAddress,
        address uniswapRouterAddress,
        uint256 gasLimitAmount,
        address owner
    ) public initializer {
        if (gatewayAddress == address(0) || uniswapRouterAddress == address(0))
            revert InvalidAddress();
        __UUPSUpgradeable_init();
        __Ownable_init(owner);
        uniswapRouter = uniswapRouterAddress;
        gateway = GatewayZEVM(gatewayAddress);
        gasLimit = gasLimitAmount;
        ownerFeeBasisPoints = 0;
    }
 
    struct Params {
        address target;
        bytes to;
        bool withdraw;
    }
 
    /**
     * @notice Sets the address of the StatTracker contract.
     * @param tracker The address of the StatTracker contract.
     */
    function setStatTracker(address tracker) external onlyOwner {
        require(tracker != address(0), "Invalid tracker address");
        statTracker = IStatTracker(tracker);
    }
 
    /**
     * @notice Swap tokens from a connected chain to another connected chain or ZetaChain.
     */
    function onCall(
        MessageContext calldata context,
        address zrc20,
        uint256 amount,
        bytes calldata message
    ) external onlyGateway {
        Params memory params = Params({
            target: address(0),
            to: bytes(""),
            withdraw: true
        });
 
        if (context.chainID == BITCOIN_TESTNET || context.chainID == BITCOIN) {
            params.target = BytesHelperLib.bytesToAddress(message, 0);
            params.to = abi.encodePacked(
                BytesHelperLib.bytesToAddress(message, 20)
            );
            if (message.length >= 41) {
                params.withdraw = BytesHelperLib.bytesToBool(message, 40);
            }
        } else {
            (
                address targetToken,
                bytes memory recipient,
                bool withdrawFlag
            ) = abi.decode(message, (address, bytes, bool));
            params.target = targetToken;
            params.to = recipient;
            params.withdraw = withdrawFlag;
        }
 
        (uint256 out, address gasZRC20, uint256 gasFee) = handleGasAndSwap(
            zrc20,
            amount,
            params.target
        );
        emit TokenSwap(
            context.sender,
            params.to,
            zrc20,
            params.target,
            amount,
            out
        );
        // Log swap data to StatTracker if set.
        if (address(statTracker) != address(0)) {
            statTracker.recordTokenSwap(
                context.sender,
                params.to,
                zrc20,
                params.target,
                amount,
                out
            );
        }
        withdraw(params, context.sender, gasFee, gasZRC20, out, zrc20);
    }
 
    /**
     * @notice Swap tokens from ZetaChain optionally withdrawing to a connected chain.
     */
    function swap(
        address inputToken,
        uint256 amount,
        address targetToken,
        bytes memory recipient,
        bool withdrawFlag
    ) public {
        bool success = IZRC20(inputToken).transferFrom(
            msg.sender,
            address(this),
            amount
        );
        if (!success) {
            revert TransferFailed(
                "Failed to transfer ZRC-20 tokens from the sender to the contract"
            );
        }
 
        (uint256 out, address gasZRC20, uint256 gasFee) = handleGasAndSwap(
            inputToken,
            amount,
            targetToken
        );
        emit TokenSwap(
            msg.sender,
            recipient,
            inputToken,
            targetToken,
            amount,
            out
        );
        // Log swap data to StatTracker if set.
        if (address(statTracker) != address(0)) {
            statTracker.recordTokenSwap(
                msg.sender,
                recipient,
                inputToken,
                targetToken,
                amount,
                out
            );
        }
        withdraw(
            Params({
                target: targetToken,
                to: recipient,
                withdraw: withdrawFlag
            }),
            msg.sender,
            gasFee,
            gasZRC20,
            out,
            inputToken
        );
    }
 
    /**
     * @notice Swaps enough tokens to pay gas fees, then swaps the remainder to the target token.
     */
    function handleGasAndSwap(
        address inputToken,
        uint256 amount,
        address targetToken
    ) internal returns (uint256, address, uint256) {
        uint256 inputForGas;
        address gasZRC20;
        uint256 gasFee;
        uint256 swapAmount;
 
        (gasZRC20, gasFee) = IZRC20(targetToken).withdrawGasFee();
 
        uint256 minInput = quoteMinInput(inputToken, targetToken);
        if (amount < minInput) {
            revert InsufficientAmount(
                "The input amount is less than the min amount required to cover the withdraw gas fee"
            );
        }
 
        if (gasZRC20 == inputToken) {
            swapAmount = amount - gasFee;
        } else {
            inputForGas = SwapHelperLib.swapTokensForExactTokens(
                uniswapRouter,
                inputToken,
                gasFee,
                gasZRC20,
                amount
            );
            swapAmount = amount - inputForGas;
        }
 
        uint256 out = SwapHelperLib.swapExactTokensForTokens(
            uniswapRouter,
            inputToken,
            swapAmount,
            targetToken,
            0
        );
        return (out, gasZRC20, gasFee);
    }
 
    /**
     * @notice Transfers tokens to the recipient on ZetaChain or withdraws to a connected chain.
     */
    function withdraw(
        Params memory params,
        address sender,
        uint256 gasFee,
        address gasZRC20,
        uint256 out,
        address inputToken
    ) public {
        if (params.withdraw) {
            if (gasZRC20 == params.target) {
                if (!IZRC20(gasZRC20).approve(address(gateway), out + gasFee)) {
                    revert ApprovalFailed();
                }
            } else {
                if (!IZRC20(gasZRC20).approve(address(gateway), gasFee)) {
                    revert ApprovalFailed();
                }
                if (!IZRC20(params.target).approve(address(gateway), out)) {
                    revert ApprovalFailed();
                }
            }
            gateway.withdraw(
                abi.encodePacked(params.to),
                out,
                params.target,
                RevertOptions({
                    revertAddress: address(this),
                    callOnRevert: true,
                    abortAddress: address(0),
                    revertMessage: abi.encode(sender, inputToken),
                    onRevertGasLimit: gasLimit
                })
            );
        } else {
            bool success = IWETH9(params.target).transfer(
                address(uint160(bytes20(params.to))),
                out
            );
            if (!success) {
                revert TransferFailed(
                    "Failed to transfer target tokens to the recipient on ZetaChain"
                );
            }
        }
    }
 
    /**
     * @notice onRevert handles an edge-case when a swap fails because the destination recipient
     * cannot accept tokens.
     */
    function onRevert(RevertContext calldata context) external onlyGateway {
        (address sender, address zrc20) = abi.decode(
            context.revertMessage,
            (address, address)
        );
        (uint256 out, , ) = handleGasAndSwap(
            context.asset,
            context.amount,
            zrc20
        );
 
        gateway.withdraw(
            abi.encodePacked(sender),
            out,
            zrc20,
            RevertOptions({
                revertAddress: sender,
                callOnRevert: false,
                abortAddress: address(0),
                revertMessage: "",
                onRevertGasLimit: gasLimit
            })
        );
    }
 
    /**
     * @notice Returns the minimum amount of input tokens required to cover the gas fee for withdrawal.
     */
    function quoteMinInput(
        address inputToken,
        address targetToken
    ) public view returns (uint256) {
        (address gasZRC20, uint256 gasFee) = IZRC20(targetToken)
            .withdrawGasFee();
 
        if (inputToken == gasZRC20) {
            return gasFee;
        }
 
        address zeta = IUniswapV2Router02(uniswapRouter).WETH();
 
        address[] memory path;
        if (inputToken == zeta || gasZRC20 == zeta) {
            path = new address[](2);
            path[0] = inputToken;
            path[1] = gasZRC20;
        } else {
            path = new address[](3);
            path[0] = inputToken;
            path[1] = zeta;
            path[2] = gasZRC20;
        }
 
        uint256[] memory amountsIn = IUniswapV2Router02(uniswapRouter)
            .getAmountsIn(gasFee, path);
 
        return amountsIn[0];
    }
 
    /**
     * @notice Multi-hop swap that allows the user to specify an arbitrary swap path.
     *
     * A fee (in basis points) is taken from the input amount and stored for later collection by the owner.
     *
     * Requirements:
     * - The user must have approved the inputToken transfer.
     * - The swap must output at least minOut tokens.
     *
     * @param inputToken The token to swap from.
     * @param amount The total amount of inputToken provided.
     * @param path An array of token addresses representing the swap path.
     * @param minOut The minimum amount of output token expected.
     * @param deadline The Unix timestamp by which the swap must complete.
     */
    function multiHopSwap(
        address inputToken,
        uint256 amount,
        address[] calldata path,
        uint256 minOut,
        uint256 deadline
    ) external {
        require(path.length >= 2, "Invalid path length");
        
        bool success = IERC20(inputToken).transferFrom(msg.sender, address(this), amount);
        if (!success) {
            revert TransferFailed("Failed to transfer tokens from sender");
        }
        
        uint256 fee = (amount * ownerFeeBasisPoints) / 10000;
        uint256 amountForSwap = amount - fee;
        
        if (!IERC20(inputToken).approve(uniswapRouter, amountForSwap)) {
            revert ApprovalFailed();
        }
        
        uint256[] memory amounts = IUniswapV2Router02(uniswapRouter)
            .swapExactTokensForTokens(amountForSwap, minOut, path, address(this), deadline);
        
        uint256 outputAmount = amounts[amounts.length - 1];
        
        if (!IERC20(path[path.length - 1]).transfer(msg.sender, outputAmount)) {
            revert TransferFailed("Failed to transfer output tokens to sender");
        }
        
        emit MultiHopSwap(msg.sender, inputToken, path[path.length - 1], amount, outputAmount, fee);
        // Log multi-hop swap data to StatTracker if set.
        if (address(statTracker) != address(0)) {
            statTracker.recordMultiHopSwap(
                msg.sender,
                inputToken,
                path[path.length - 1],
                amount,
                outputAmount,
                fee
            );
        }
    }
 
    /**
     * @notice Allows the owner to update the fee rate (in basis points) for multi-hop swaps.
     *
     * @param _feeBasisPoints The new fee rate in basis points (e.g., 50 for 0.5%).
     */
    function setOwnerFeeBasisPoints(uint256 _feeBasisPoints) external onlyOwner {
        require(_feeBasisPoints <= 1000, "Fee too high");
        ownerFeeBasisPoints = _feeBasisPoints;
    }
 
    /**
     * @notice Allows the owner to collect accumulated fee tokens from the contract.
     *
     * @param token The address of the token to collect fees for.
     */
    function collectFees(address token) external onlyOwner {
        uint256 feeBalance = IERC20(token).balanceOf(address(this));
        require(feeBalance > 0, "No fees to collect");
        if (!IERC20(token).transfer(owner(), feeBalance)) {
            revert TransferFailed("Fee collection transfer failed");
        }
    }
 
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
