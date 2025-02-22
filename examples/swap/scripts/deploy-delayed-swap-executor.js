// scripts/deploy-delayed-swap-executor.js
async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying DelayedSwapExecutor with account:", deployer.address);
  
    // Replace with your actual deployed Swap contract address.
    const swapContractAddress = "0x9064a8Ea81be16f5f83271Bb2e46A9E43c5A4ED4";
    const DelayedSwapExecutor = await ethers.getContractFactory("DelayedSwapExecutor");
    const executor = await DelayedSwapExecutor.deploy(swapContractAddress);
  
    await executor.deployed();
    console.log("DelayedSwapExecutor deployed to:", executor.address);
  }
  
  main()
    .then(() => process.exit(0))
    .catch(error => {
      console.error(error);
      process.exit(1);
    });
  // 0xa35338035e83BFcba35f8f713388d45c94A106a4

  // In the Hardhat console, run:
const executor = await ethers.getContractAt("DelayedSwapExecutor", "0xa35338035e83BFcba35f8f713388d45c94A106a4");

// Example addresses – replace these with your actual token addresses if they differ.
const inputToken = "0x4200000000000000000000000000000000000006"; // e.g., WETH on Base Sepolia
const targetToken = "0x0000000000000000000000000000000000000002"; // e.g., USDC (dummy example)
const recipient = ethers.utils.defaultAbiCoder.encode(
  ["address"],
  ["0x1234567890123456789012345678901234567890"]
);

const amount = ethers.utils.parseUnits("1", 18); // 1 token, assuming 18 decimals
const withdrawFlag = false;
const delayInSeconds = 30; // 30 seconds delay (for testing)

// Approve tokens for the executor contract.
const token = await ethers.getContractAt("IERC20", inputToken);
await token.approve(executor.address, amount);

// Schedule the swap.
await executor.scheduleSwap(inputToken, amount, targetToken, recipient, withdrawFlag, delayInSeconds);
