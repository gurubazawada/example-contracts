// scripts/deploy-stat-tracker.js
async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying StatTracker with the account:", deployer.address);
  
    const StatTracker = await ethers.getContractFactory("StatTracker");
    const statTracker = await StatTracker.deploy();
  
    await statTracker.deployed();
    console.log("StatTracker deployed to:", statTracker.address);
  }
  
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
// 0x5eB3243B7a6fB418568F3EAd5D5dFB2C16179937
// swap address: 0x9064a8Ea81be16f5f83271Bb2e46A9E43c5A4ED4