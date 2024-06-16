// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@zetachain/protocol-contracts/contracts/zevm/SystemContract.sol";
import "@zetachain/protocol-contracts/contracts/zevm/interfaces/zContract.sol";
import "@zetachain/toolkit/contracts/SwapHelperLib.sol";
import "@zetachain/toolkit/contracts/BytesHelperLib.sol";
import "@zetachain/protocol-contracts/contracts/zevm/interfaces/IWZETA.sol";
import "@zetachain/toolkit/contracts/OnlySystem.sol";

contract SwapToZeta is zContract, OnlySystem {
    SystemContract public systemContract;

    uint256 constant BITCOIN = 18332;

    constructor(address systemContractAddress) {
        systemContract = SystemContract(systemContractAddress);
    }

    struct Params {
        address target;
        bytes to;
        bool withdraw;
    }

    function onCrossChainCall(
        zContext calldata context,
        address zrc20,
        uint256 amount,
        bytes calldata message
    ) external virtual override onlySystem(systemContract) {
        Params memory params = Params({
            target: address(0),
            to: bytes(""),
            withdraw: true
        });

        if (context.chainID == BITCOIN) {
            params.target = BytesHelperLib.bytesToAddress(message, 0);
            params.to = abi.encodePacked(BytesHelperLib.bytesToAddress(message, 20));
            if (message.length >= 41) {
                params.withdraw = bytesToBool(message, 40);
            }
        } else {
            (address targetToken, bytes memory recipient, bool withdrawFlag) = abi.decode(
                message,
                (address, bytes, bool)
            );
            params.target = targetToken;
            params.to = recipient;
            params.withdraw = withdrawFlag;
        }

        uint256 inputForGas;
        address gasZRC20;
        uint256 gasFee;

        if (params.withdraw) {
            (gasZRC20, gasFee) = IZRC20(params.target).withdrawGasFee();

            inputForGas = SwapHelperLib.swapTokensForExactTokens(
                systemContract,
                zrc20,
                gasFee,
                gasZRC20,
                amount
            );
        }

        uint256 outputAmount = SwapHelperLib.swapExactTokensForTokens(
            systemContract,
            zrc20,
            params.withdraw ? amount - inputForGas : amount,
            params.target,
            0
        );

        if (!params.withdraw) {
            IWETH9(params.target).transfer(address(uint160(bytes20(params.to))), outputAmount);
        } else {
            IZRC20(gasZRC20).approve(params.target, gasFee);
            IZRC20(params.target).withdraw(params.to, outputAmount);
        }
    }

    function bytesToBool(bytes calldata data, uint256 offset)
        internal
        pure
        returns (bool)
    {
        require(offset < data.length, "Offset is out of bounds");
        return uint8(data[offset]) != 0;
    }
}
