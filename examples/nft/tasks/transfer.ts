import { task, types } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import ZRC20ABI from "@zetachain/protocol-contracts/abi/ZRC20.sol/ZRC20.json";

const main = async (args: any, hre: HardhatRuntimeEnvironment) => {
  const { ethers } = hre;
  const [signer] = await ethers.getSigners();
  const nftContract = await ethers.getContractAt("IERC721", args.contract);
  const approveTx = await nftContract
    .connect(signer)
    .approve(args.contract, args.tokenId);
  await approveTx.wait();

  const contract = await ethers.getContractAt(args.name, args.contract);
  const revertOptions = {
    abortAddress: "0x0000000000000000000000000000000000000000",
    callOnRevert: args.callOnRevert,
    onRevertGasLimit: args.onRevertGasLimit,
    revertAddress: args.revertAddress,
    revertMessage: ethers.utils.hexlify(
      ethers.utils.toUtf8Bytes(args.revertMessage)
    ),
  };
  const txOptions = {
    gasPrice: args.txOptionsGasPrice,
    gasLimit: args.txOptionsGasLimit,
  };
  let tx;

  let fromZetaChain = false;
  try {
    fromZetaChain = await (contract as any).isUniversal();
  } catch (e) {}

  if (fromZetaChain) {
    const callOptions = {
      gasLimit: args.txOptionsGasLimit,
      isArbitraryCall: args.isArbitraryCall,
    };

    const gasLimit = hre.ethers.BigNumber.from(args.txOptionsGasLimit);
    const zrc20 = new ethers.Contract(args.destination, ZRC20ABI.abi, signer);
    const [, gasFee] = await zrc20.withdrawGasFeeWithGasLimit(gasLimit);
    const zrc20TransferTx = await zrc20.approve(
      args.contract,
      gasFee,
      txOptions
    );

    await zrc20TransferTx.wait();

    tx = await (contract as any).transferCrossChain(
      args.tokenId,
      args.receiver,
      args.destination,
      callOptions,
      revertOptions,
      txOptions
    );

    await tx.wait();
  } else {
    const value = ethers.utils.parseUnits(args.amount, 18);

    tx = await (contract as any).transferCrossChain(
      args.tokenId,
      args.receiver,
      args.destination,
      revertOptions,
      { ...txOptions, value }
    );

    await tx.wait();
  }
  if (args.json) {
    console.log(
      JSON.stringify({
        contractAddress: args.contract,
        transferTransactionHash: tx.hash,
        sender: signer.address,
        tokenId: args.tokenId,
      })
    );
  } else {
    console.log(`🚀 Successfully transferred NFT to the contract.
📜 Contract address: ${args.contract}
🖼 NFT Contract address: ${args.nftContract}
🆔 Token ID: ${args.tokenId}
🔗 Transaction hash: ${tx.hash}`);
  }
};

task("transfer", "Transfer and lock an NFT", main)
  .addParam("contract", "The address of the Universal contract")
  .addParam("tokenId", "The ID of the NFT to transfer")
  .addOptionalParam("name", "The contract name to interact with", "Universal")
  .addOptionalParam(
    "txOptionsGasPrice",
    "The gas price for the transaction",
    10000000000,
    types.int
  )
  .addOptionalParam(
    "txOptionsGasLimit",
    "The gas limit for the transaction",
    7000000,
    types.int
  )
  .addFlag("callOnRevert", "Whether to call on revert")
  .addOptionalParam(
    "revertAddress",
    "The address to call on revert",
    "0x0000000000000000000000000000000000000000"
  )
  .addOptionalParam("revertMessage", "The message to send on revert", "0x")
  .addOptionalParam(
    "onRevertGasLimit",
    "The gas limit for the revert transaction",
    7000000,
    types.int
  )
  .addFlag("isArbitraryCall", "Whether the call is arbitrary")
  .addFlag("json", "Output the result in JSON format")
  .addOptionalParam(
    "destination",
    "ZRC-20 of the gas token of the destination chain",
    "0x0000000000000000000000000000000000000000"
  )
  .addParam("amount", "The amount of gas to transfer", "0")
  .addParam(
    "receiver",
    "The address of the receiver contract on a connected chain"
  );
