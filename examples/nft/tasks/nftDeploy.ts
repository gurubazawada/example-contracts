import { task, types } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const main = async (args: any, hre: HardhatRuntimeEnvironment) => {
  const network = hre.network.name;

  const [signer] = await hre.ethers.getSigners();
  if (signer === undefined) {
    throw new Error(
      `Wallet not found. Please, run "npx hardhat account --save" or set PRIVATE_KEY env variable (for example, in a .env file)`
    );
  }

  const factory = await hre.ethers.getContractFactory(args.name);
  const contract = await factory.deploy(args.gateway, signer.address);
  await contract.deployed();

  if (args.json) {
    console.log(
      JSON.stringify({
        contractAddress: contract.address,
        deployer: signer.address,
        network: network,
        transactionHash: contract.deployTransaction.hash,
      })
    );
  } else {
    console.log(`🚀 Successfully deployed "${args.name}" contract on ${network}.
📜 Contract address: ${contract.address}
🔗 Transaction hash: ${contract.deployTransaction.hash}`);
  }
};

task("nft-deploy", "Deploy the NFT contract", main)
  .addFlag("json", "Output the result in JSON format")
  .addOptionalParam("name", "The contract name to deploy", "Universal")
  .addOptionalParam(
    "gateway",
    "Gateway address (default: ZetaChain Gateway)",
    "0x9A676e781A523b5d0C0e43731313A708CB607508"
  );
