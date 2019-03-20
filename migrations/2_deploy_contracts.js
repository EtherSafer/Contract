var EtherSafer = artifacts.require("EtherSafer");

module.exports = function(deployer) {
  // Token Contract will be created during the creation of Ether Safer
  deployer.deploy(EtherSafer);
};