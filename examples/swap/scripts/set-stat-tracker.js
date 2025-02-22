// scripts/set-stat-tracker.js
async function main() {
    const [deployer] = await ethers.getSigners();
    const swapAddress = "0x9064a8Ea81be16f5f83271Bb2e46A9E43c5A4ED4"; 
    const statTrackerAddress = "0x5eB3243B7a6fB418568F3EAd5D5dFB2C16179937"; 
  
    const Swap = await ethers.getContractFactory("Swap");
    const swap = await Swap.attach(swapAddress);
  
    const tx = await swap.setStatTracker(statTrackerAddress);
    console.log("Setting StatTracker address...");
    await tx.wait();
    console.log("StatTracker address set successfully.");
  }
  
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
  