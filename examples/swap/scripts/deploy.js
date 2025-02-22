// scripts/deploy.js
const { ethers, upgrades } = require("hardhat");
const minimist = require("minimist");

async function main() {
  // Parse CLI arguments
  const args = minimist(process.argv.slice(2));
  const gatewayAddress = args.gateway;
  const uniswapRouterAddress = args["uniswap-router"];
  if (!gatewayAddress || !uniswapRouterAddress) {
    console.error("Missing required parameters: --gateway and --uniswap-router");
    process.exit(1);
  }

  // Set parameters
  const gasLimit = 300000; // Adjust as needed
  const feeBasisPoints = 50; // 50 basis points = 0.5%
  const feeCollector = (await ethers.getSigners())[0].address;

  // Deployer will be the owner
  const [deployer] = await ethers.getSigners();

  console.log("Deploying EnhancedSwap with the following parameters:");
  console.log("  Gateway Address:", gatewayAddress);
  console.log("  Uniswap Router Address:", uniswapRouterAddress);
  console.log("  Gas Limit:", gasLimit);
  console.log("  Owner:", deployer.address);
  console.log("  Fee (basis points):", feeBasisPoints);
  console.log("  Fee Collector:", feeCollector);

  // Deploy the SwapStats contract first
  const SwapStats = await ethers.getContractFactory("SwapStats");
  const swapStats = await SwapStats.deploy(deployer.address);
  await swapStats.deployed();
  console.log("SwapStats deployed at:", swapStats.address);

  // Deploy EnhancedSwap via UUPS proxy
  const EnhancedSwap = await ethers.getContractFactory("EnhancedSwap");
  const enhancedSwap = await upgrades.deployProxy(
    EnhancedSwap,
    [
      gatewayAddress,
      uniswapRouterAddress,
      gasLimit,
      deployer.address,
      swapStats.address,
      feeBasisPoints,
      feeCollector
    ],
    { kind: "uups" }
  );
  await enhancedSwap.deployed();
  console.log("EnhancedSwap deployed at:", enhancedSwap.address);

  // Link the SwapStats contract with the EnhancedSwap contract
  const tx = await swapStats.setSwapContract(enhancedSwap.address);
  await tx.wait();
  console.log("SwapStats now linked to EnhancedSwap");
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
