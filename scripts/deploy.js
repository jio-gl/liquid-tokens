const hre = require("hardhat");

async function main() {
  console.log("Deploying LiquidToken contract...");
  
  const LiquidToken = await hre.ethers.getContractFactory("LiquidToken");
  const liquidToken = await LiquidToken.deploy();
  
  await liquidToken.waitForDeployment();
  
  const address = await liquidToken.getAddress();
  console.log(`LiquidToken deployed to: ${address}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 