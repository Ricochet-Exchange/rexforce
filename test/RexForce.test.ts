
let { toWad } = require("@decentral.ee/web3-helpers");
let { Framework } = require("@superfluid-finance/sdk-core");
let { assert } = require("chai");
let { ethers, web3 } = require("hardhat");
let daiABI = require("./abis/fDAIABI");
import traveler from "ganache-time-traveler";
import { REXForce  } from "../typechain";
const TEST_TRAVEL_TIME = 3600 * 2; // 1 hours


let deployFramework = require("@superfluid-finance/ethereum-contracts/scripts/deploy-framework");
let deployTestToken = require("@superfluid-finance/ethereum-contracts/scripts/deploy-test-token");
let deploySuperToken = require("@superfluid-finance/ethereum-contracts/scripts/deploy-super-token");

let provider = web3;

let accounts: any[]

let sf: InstanceType<typeof Framework>;;
let dai: InstanceType<typeof daiABI>;
let daix: InstanceType<typeof daiABI>;
let superSigner: InstanceType<typeof sf.createSigner>;
let rexForce: InstanceType<typeof REXForce>;

let errorHandler = (err: any) => {
  if (err) throw err;
};

before(async function () {
  //get accounts from hardhat
  accounts = await ethers.getSigners();

  //deploy the framework
  await deployFramework(errorHandler, {
    web3,
    from: accounts[0].address,
  });

  //deploy a fake erc20 token
  let fDAIAddress = await deployTestToken(errorHandler, [":", "fDAI"], {
    web3,
    from: accounts[0].address,
  });

  //deploy a fake erc20 wrapper super token around the fDAI token
  let fDAIxAddress = await deploySuperToken(errorHandler, [":", "fDAI"], {
    web3,
    from: accounts[0].address,
  });

  console.log("fDAIxAddress: ", fDAIxAddress);
  console.log("fDAIAddress: ", fDAIAddress);

  //initialize the superfluid framework...put custom and web3 only bc we are using hardhat locally
  sf = await Framework.create({
    networkName: "custom",
    provider,
    dataMode: "WEB3_ONLY",
    resolverAddress: process.env.RESOLVER_ADDRESS, //this is how you get the resolver address
    protocolReleaseVersion: "test",
  });

  superSigner = await sf.createSigner({
    signer: accounts[0],
    provider: provider
  });

  //use the framework to get the super token
  daix = await sf.loadSuperToken("fDAIx");

  //get the contract object for the erc20 token
  let daiAddress = daix.underlyingToken.address;
  dai = new ethers.Contract(daiAddress, daiABI, accounts[0]);

  let App = await ethers.getContractFactory("REXForce", accounts[0]);

  //deploy the contract
  rexForce = await App.deploy(
    daix.address,
    "Alice",
    "alice@alice.com",
    sf.settings.config.hostAddress,
    sf.settings.config.hostAddress,
    sf.settings.config.cfaV1Address,
    ""
  );

  const appInitialBalance = await daix.balanceOf({
    account: rexForce.address,
    providerOrSigner: accounts[0]
  });

  console.log("appInitialBalance: ", appInitialBalance); // initial balance of the app is 0

  await dai.mint(
    accounts[0].address, ethers.utils.parseEther("1000")
  );

  await dai.approve(daix.address, ethers.utils.parseEther("1000"));

  const daixUpgradeOperation = daix.upgrade({
    amount: ethers.utils.parseEther("1000")
  });

  await daixUpgradeOperation.exec(accounts[0]);

  const daiBal = await daix.balanceOf({
    account: accounts[0].address,
    providerOrSigner: accounts[0]
  });
  console.log('daix bal for acct 0: ', daiBal);

  // add flow to contract
  const createFlowOperation = await sf.cfaV1.createFlow({
    receiver: rexForce.address,
    superToken: daix.address,
    flowRate: toWad(0.01).toString(),
  })

  const txn = await createFlowOperation.exec(accounts[0]);
  const receipt = await txn.wait();

  console.log("go forward in time");
  await traveler.advanceTimeAndBlock(TEST_TRAVEL_TIME);

  const balance = await daix.balanceOf({ account: rexForce.address, providerOrSigner: accounts[0] });
  console.log('daix bal after flow: ', balance);
});

beforeEach(async function () {
  let alice = accounts[1];

  await dai.connect(alice).mint(
    alice.address, ethers.utils.parseEther("1000")
  );

  await dai.connect(alice).approve(
    daix.address, ethers.utils.parseEther("1000")
  );

  const daixUpgradeOperation = daix.upgrade({
    amount: ethers.utils.parseEther("1000")
  });

  await daixUpgradeOperation.exec(alice);

  const daiBal = await daix.balanceOf({ account: alice.address, providerOrSigner: accounts[0] });
  console.log('daix bal for acct alice: ', daiBal);
});

async function netFlowRate(user: any) {
  const flow = await sf.cfaV1.getNetFlow({
    superToken: daix.address,
    account: user.address,
    providerOrSigner: superSigner
  });
  return flow;
}


describe("REXForce", async function () {
  it("#1 - deploys with correct parameters", async () => {
    // TODO
  });
})
