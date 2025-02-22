async function main() {
    const executorAddress = "0xa35338035e83BFcba35f8f713388d45c94A106a4";
    const executor = await ethers.getContractAt("DelayedSwapExecutor", executorAddress);
  
    await network.provider.send("evm_increaseTime", [31]);
    await network.provider.send("evm_mine");
  
    // Execute the scheduled swap with order ID 0
    const tx = await executor.executeSwap(0);
    await tx.wait();
    console.log("Executed swap for order 0");
  }
  
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
  