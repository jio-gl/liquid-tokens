var LiquidToken = artifacts.require("./LiquidToken.sol");

module.exports = function(deployer) {
  deployer.deploy(LiquidToken);
};
