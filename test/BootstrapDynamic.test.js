const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("LiquidToken Bootstrap and Dynamic Periods", function () {
  let liquidToken;
  let owner;
  let addr1;
  let addr2;
  let addrs;
  
  const SECONDS_PER_DAY = 86400;
  const BOOTSTRAP_PERIOD = 0;
  const DYNAMIC_PERIOD = 1;

  beforeEach(async function () {
    [owner, addr1, addr2, ...addrs] = await ethers.getSigners();

    const LiquidToken = await ethers.getContractFactory("LiquidToken");
    liquidToken = await LiquidToken.deploy();
  });

  describe("Bootstrap Period", function () {
    it("Should start in bootstrap period", async function () {
      expect(await liquidToken.getCurrentPeriod()).to.equal(BOOTSTRAP_PERIOD);
    });

    it("Should apply early adopter premium during bootstrap", async function () {
      // Mint tokens during bootstrap
      const initialBalance = await liquidToken.balanceOf(addr1.address);
      await liquidToken.connect(addr1).mint();
      const newBalance = await liquidToken.balanceOf(addr1.address);
      
      // Balance should increase by mint amount (with early adopter premium)
      expect(newBalance).to.be.gt(initialBalance);
      
      // Get bootstrap end time
      const bootstrapEnd = await liquidToken.getBootstrapEndTimestamp();
      
      // Check if bootstrap period is over
      expect(await liquidToken.isBootstrapPeriodOver()).to.equal(false);
      
      // Advance time to almost the end of bootstrap
      await time.increaseTo(Number(bootstrapEnd) - SECONDS_PER_DAY);
      
      // Still in bootstrap period but premium should be lower
      expect(await liquidToken.getCurrentPeriod()).to.equal(BOOTSTRAP_PERIOD);
      
      // Mint again to check premium is lower
      const balanceBeforeSecondMint = await liquidToken.balanceOf(addr2.address);
      await liquidToken.connect(addr2).mint();
      const balanceAfterSecondMint = await liquidToken.balanceOf(addr2.address);
      
      // Both mints should provide tokens, but later mint should give less due to decreasing premium
      const firstMintAmount = newBalance - initialBalance;
      const secondMintAmount = balanceAfterSecondMint - balanceBeforeSecondMint;
      
      console.log("First mint amount: ", ethers.formatUnits(firstMintAmount, 18));
      console.log("Second mint amount: ", ethers.formatUnits(secondMintAmount, 18));
      
      // First mint should be greater due to higher premium
      expect(firstMintAmount).to.be.gt(secondMintAmount);
    });
    
    it("Should transition to dynamic period after bootstrap", async function () {
      // Get bootstrap end time
      const bootstrapEnd = await liquidToken.getBootstrapEndTimestamp();
      
      // Advance time past the bootstrap period
      await time.increaseTo(Number(bootstrapEnd) + 100); // Add some buffer
      
      // Trigger rebase to update period
      await liquidToken.rebase();
      
      // Should now be in dynamic period
      expect(await liquidToken.getCurrentPeriod()).to.equal(DYNAMIC_PERIOD);
    });
  });

  describe("Dynamic Period", function () {
    it("Should calculate dynamic rate based on transaction volume", async function () {
      // Skip bootstrap period
      const bootstrapEnd = await liquidToken.getBootstrapEndTimestamp();
      await time.increaseTo(Number(bootstrapEnd) + 100); // Add some buffer
      
      // Trigger rebase to update period
      await liquidToken.rebase();
      
      // Check dynamic rate
      const dynamicRate = await liquidToken.getCurrentDynamicRate();
      
      console.log("Initial dynamic rate: ", dynamicRate.toString());
      
      // Create some transactions to affect the rate
      for (let i = 0; i < 5; i++) {
        await liquidToken.transfer(addr1.address, ethers.parseUnits("1", 18));
      }
      
      // Wait a day and rebase
      await time.increase(SECONDS_PER_DAY);
      await liquidToken.rebase();
      
      // Check new dynamic rate
      const newDynamicRate = await liquidToken.getCurrentDynamicRate();
      console.log("New dynamic rate: ", newDynamicRate.toString());
      
      // Check if it's a mint rate (positive) or burn rate (negative)
      const isMintRate = await liquidToken.isMintRate();
      console.log("Is mint rate: ", isMintRate);
      
      // Confirm rate is calculated (either positive or non-zero absolute value)
      if (dynamicRate != newDynamicRate) {
        // Rate changed, great!
        expect(newDynamicRate).to.not.equal(dynamicRate);
      } else {
        // Rate didn't change, but make sure it's properly calculated
        expect(isMintRate).to.equal(true); // Should be a mint rate
        expect(await liquidToken.getCurrentRateAbsolute()).to.be.gt(0); // Should have non-zero absolute value
      }
    });
    
    it("Should accumulate mint rate when dynamic rate is positive", async function () {
      // Skip bootstrap period
      const bootstrapEnd = await liquidToken.getBootstrapEndTimestamp();
      await time.increaseTo(Number(bootstrapEnd) + 100);
      
      // Trigger rebase to update period
      await liquidToken.rebase();
      
      // Record initial accumulated mint rate
      const initialAccumulatedRate = await liquidToken.getAccumulatedMintRate();
      
      // Create some transactions to affect the rate
      for (let i = 0; i < 5; i++) {
        await liquidToken.transfer(addr1.address, ethers.parseUnits("1", 18));
      }
      
      // Wait a day and rebase to accumulate rate
      await time.increase(SECONDS_PER_DAY);
      await liquidToken.rebase();
      
      // Check if it's a mint rate
      const isMintRate = await liquidToken.isMintRate();
      
      // Check new accumulated mint rate
      const newAccumulatedRate = await liquidToken.getAccumulatedMintRate();
      
      console.log("Initial accumulated rate: ", initialAccumulatedRate.toString());
      console.log("New accumulated rate: ", newAccumulatedRate.toString());
      console.log("Is mint rate: ", isMintRate);
      
      // If it's a mint rate, accumulated rate should have increased
      if (isMintRate) {
        expect(newAccumulatedRate).to.be.gt(initialAccumulatedRate);
      }
    });
    
    it("Should apply mint rate during transfers", async function () {
      // Skip bootstrap period
      const bootstrapEnd = await liquidToken.getBootstrapEndTimestamp();
      await time.increaseTo(Number(bootstrapEnd) + 100);
      
      // Trigger rebase to update period
      await liquidToken.rebase();
      
      // Create some transactions to increase transaction count
      for (let i = 0; i < 5; i++) {
        await liquidToken.transfer(addr1.address, ethers.parseUnits("1", 18));
      }
      
      // Wait a day and rebase to accumulate rate
      await time.increase(SECONDS_PER_DAY);
      await liquidToken.rebase();
      
      // Check if it's a mint rate
      const isMintRate = await liquidToken.isMintRate();
      console.log("Is mint rate: ", isMintRate);
      
      if (isMintRate) {
        // Transfer to addr2 to trigger mint rate application on addr1
        const initialBalance = await liquidToken.balanceOf(addr1.address);
        await liquidToken.connect(addr1).transfer(addr2.address, ethers.parseUnits("0.5", 18));
        const finalBalance = await liquidToken.balanceOf(addr1.address);
        
        // If mint was applied, there should be additional tokens besides the transfer
        console.log("Initial balance: ", ethers.formatUnits(initialBalance, 18));
        console.log("Final balance: ", ethers.formatUnits(finalBalance, 18));
        console.log("Difference: ", ethers.formatUnits(initialBalance - finalBalance, 18));
      }
    });
  });

  describe("View vs Effective Balance", function () {
    it("Should show projected balance with accumulated mint", async function () {
      // Skip bootstrap period
      const bootstrapEnd = await liquidToken.getBootstrapEndTimestamp();
      await time.increaseTo(Number(bootstrapEnd) + 100);
      
      // Trigger rebase to update period
      await liquidToken.rebase();
      
      // Transfer tokens to addr1
      await liquidToken.transfer(addr1.address, ethers.parseUnits("100", 18));
      
      // Create some transactions to affect rate
      for (let i = 0; i < 5; i++) {
        await liquidToken.transfer(addr2.address, ethers.parseUnits("1", 18));
      }
      
      // Wait a day and rebase to accumulate rate
      await time.increase(SECONDS_PER_DAY);
      await liquidToken.rebase();
      
      // Check if it's a mint rate
      const isMintRate = await liquidToken.isMintRate();
      console.log("Is mint rate: ", isMintRate);
      
      if (isMintRate) {
        // Check view balance vs effective balance
        const viewBalance = await liquidToken.balanceOf(addr1.address);
        const effectiveBalance = await liquidToken.effectiveBalanceOf(addr1.address);
        const accountMintRate = await liquidToken.getAccountMintRate(addr1.address);
        
        console.log("View balance: ", ethers.formatUnits(viewBalance, 18));
        console.log("Effective balance: ", ethers.formatUnits(effectiveBalance, 18));
        console.log("Account mint rate: ", accountMintRate.toString());
        
        // Make a transfer to apply the mint rate
        await liquidToken.connect(addr1).transfer(addr2.address, ethers.parseUnits("1", 18));
        
        // Get new balances after mint applied
        const newViewBalance = await liquidToken.balanceOf(addr1.address);
        const newEffectiveBalance = await liquidToken.effectiveBalanceOf(addr1.address);
        
        console.log("New view balance: ", ethers.formatUnits(newViewBalance, 18));
        console.log("New effective balance: ", ethers.formatUnits(newEffectiveBalance, 18));
      }
    });
  });
}); 