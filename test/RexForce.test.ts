
let { toWad } = require("@decentral.ee/web3-helpers");
let { Framework } = require("@superfluid-finance/sdk-core");
let { expect, assert } = require("chai");
let { ethers, web3 } = require("hardhat");
let ricABI = require("./abis/fDAIABI");
import traveler from "ganache-time-traveler";
import { REXForce  } from "../typechain";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

const ONE_MONTH_TRAVEL_TIME = 60 * 60 * 24 * 30; // 1 month
const CAPTAINS_FLOW_RATE = "3858024691360000";
const REXFORCE_FLOW_RATE = "38580246913600000";
const CAPTAINS_STAKE_AMOUNT = ethers.utils.parseEther("10000");

const VOTE_KIND_NONE = 0;
const VOTE_KIND_ONBOARDING = 1;
const VOTE_KIND_RESIGN = 2;
const VOTE_KIND_DISPUTE = 3;


let deployFramework = require("@superfluid-finance/ethereum-contracts/scripts/deploy-framework");
let deployTestToken = require("@superfluid-finance/ethereum-contracts/scripts/deploy-test-token");
let deploySuperToken = require("@superfluid-finance/ethereum-contracts/scripts/deploy-super-token");

let provider = web3;

let accounts: any[]

let admin: SignerWithAddress;
let firstCaptain: SignerWithAddress;
let secondCaptain: SignerWithAddress;
let thirdCaptain: SignerWithAddress;

let sf: InstanceType<typeof Framework>;;
let ric: InstanceType<typeof ricABI>;
let ricx: InstanceType<typeof ricABI>;
let superSigner: InstanceType<typeof sf.createSigner>;
let rexForce: InstanceType<typeof REXForce>;
let tellor;

let errorHandler = (err: any) => {
  if (err) throw err;
};

before(async function () {
  //get accounts from hardhat
  [admin, firstCaptain, secondCaptain, thirdCaptain] = await ethers.getSigners();

  //deploy the framework
  await deployFramework(errorHandler, {
    web3,
    from: admin.address,
  });

  //deploy a fake erc20 token
  let fDAIAddress = await deployTestToken(errorHandler, [":", "fDAI"], {
    web3,
    from: admin.address,
  });

  //deploy a fake erc20 wrapper super token around the fDAI token
  let fDAIxAddress = await deploySuperToken(errorHandler, [":", "fDAI"], {
    web3,
    from: admin.address,
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
    signer: admin,
    provider: provider
  });

  //use the framework to get the super token
  ricx = await sf.loadSuperToken("fDAIx");

  //get the contract object for the erc20 token
  let ricAddress = ricx.underlyingToken.address;
  ric = new ethers.Contract(ricAddress, ricABI, admin);
  const TellorPlayground = await ethers.getContractFactory('TellorPlayground');
  tellor = await TellorPlayground.deploy("Tributes", "TRB");
  await tellor.deployed();

  let App = await ethers.getContractFactory("REXForce", firstCaptain);

  //deploy the contract
  rexForce = await App.deploy(
    ricx.address,
    "Alice",
    "alice@alice.com",
    tellor.address,
    sf.settings.config.hostAddress,
    sf.settings.config.cfaV1Address,
    ""
  );

  await rexForce.deployed();

  // Mint some RIC for Rexforce
  await ric.mint(
    admin.address, ethers.utils.parseEther("1000000")
  );
  await ric.mint(
    firstCaptain.address, ethers.utils.parseEther("1000000")
  );
  await ric.mint(
    secondCaptain.address, ethers.utils.parseEther("1000000")
  );
  await ric.mint(
    thirdCaptain.address, ethers.utils.parseEther("1000000")
  );

  // Upgrade the RIC to RICx
  // NOTE: Couldn't figure out how to make a native supertoken
  //       so RIC and RICx were made here, RICx is Supertoken RIC
  await ric.approve(ricx.address, ethers.utils.parseEther("1000000"));
  await ric.connect(firstCaptain).approve(ricx.address, ethers.utils.parseEther("1000000"));
  await ric.connect(secondCaptain).approve(ricx.address, ethers.utils.parseEther("1000000"));
  await ric.connect(thirdCaptain).approve(ricx.address, ethers.utils.parseEther("1000000"));

  let ricxUpgradeOperation = ricx.upgrade({
    amount: ethers.utils.parseEther("1000000")
  });
  await ricxUpgradeOperation.exec(admin);
  ricxUpgradeOperation = ricx.upgrade({
    amount: ethers.utils.parseEther("1000000")
  });
  await ricxUpgradeOperation.exec(firstCaptain);
  ricxUpgradeOperation = ricx.upgrade({
    amount: ethers.utils.parseEther("1000000")
  });
  await ricxUpgradeOperation.exec(secondCaptain);
  ricxUpgradeOperation = ricx.upgrade({
    amount: ethers.utils.parseEther("1000000")
  });
  await ricxUpgradeOperation.exec(thirdCaptain);


  // Log the balances of everyone
  let ricBal = await ricx.balanceOf({
    account: admin.address,
    providerOrSigner: admin
  });
  console.log('ricx bal for admin: ', ricBal);
  ricBal = await ricx.balanceOf({
    account: firstCaptain.address,
    providerOrSigner: admin
  });
  console.log('ricx bal for firstCaptain: ', ricBal);
  ricBal = await ricx.balanceOf({
    account: secondCaptain.address,
    providerOrSigner: admin
  });
  console.log('ricx bal for secondCaptain: ', ricBal);
  ricBal = await ricx.balanceOf({
    account: thirdCaptain.address,
    providerOrSigner: admin
  });
  console.log('ricx bal for thirdCaptain: ', ricBal);

  // Start a stream from admin to rexForce contract (i.e. treasury funds rexforce)
  const createFlowOperation = await sf.cfaV1.createFlow({
    receiver: rexForce.address,
    superToken: ricx.address,
    flowRate: CAPTAINS_FLOW_RATE
  })

  const txn = await createFlowOperation.exec(admin);
  const receipt = await txn.wait();

  // Fast forward 1 month to fund the contract with enough RIC to pay rexforce
  console.log("go forward in time");
  await traveler.advanceTimeAndBlock(ONE_MONTH_TRAVEL_TIME);

});

beforeEach(async function () {
  // TODO
});

async function netFlowRate(user: any) {
  const flow = await sf.cfaV1.getNetFlow({
    superToken: ricx.address,
    account: user.address,
    providerOrSigner: superSigner
  });
  return flow;
}

describe("REXForce", async function () {

  context("#1 - Onboards a captain", async () => {

    it("#1.1 has first captain", async () => {
      assert.equal(
        (await rexForce.captains(0)).toString(),
        'Genesis,false,0x0000000000000000000000000000000000000000,genisis@genesis,false,0',
        'genisis captain does not exist'
      );
      assert.equal(
        (await rexForce.captains(1)).toString(),
        `Alice,true,${firstCaptain.address},alice@alice.com,false,0`,
        'first captain does not exist'
      );

      // TODO
      assert.equal(
        (await netFlowRate(admin)).toString(),
        CAPTAINS_FLOW_RATE,
        'first captain not paid'
      );

    });

    it.only("#1.2 applyForCaptain", async () => {

      // Try to reapply firstCaptain and revert
      await expect(
        rexForce.connect(firstCaptain).applyForCaptain("Alice", "alice@alice.com")
      ).to.be.revertedWith("Already applied or can't apply");

      console.log("Try approve", rexForce.address);

      let ricxApproveOperation = ricx.approve({
        receiver: rexForce.address,
        amount: ethers.utils.parseEther("10000")
      });
      await ricxApproveOperation.exec(secondCaptain);

      await expect(
          rexForce.connect(secondCaptain).applyForCaptain("Bob", "bob@bob.com")
        )
        .to.emit(rexForce, "VotingStarted")
        .withArgs(
          secondCaptain.address,
          VOTE_KIND_ONBOARDING,
          (await ethers.provider.getBlock("latest")).timestamp
        );


    });

    it("#1.3 castVote and endCaptainOnboardingVote with yes vote", async () => {
      // TODO
    });

    it("#1.4 castVote and endCaptainOnboardingVote with no vote", async () => {
      // TODO
    });
  });

  context("#2 - Offboards a captain", async () => {
    it("#2.1 resignCaptain", async () => {
      // TODO
    });

    it("#2.2 castVote and endCaptainResignVote with a positive vote", async () => {
      // TODO
    });

    it("#2.3 castVote and endCaptainResignVote with a negative vote", async () => {
      // TODO
    });

    it("#2.4 disputeCaptain", async () => {
      // TODO
    });

    it("#2.5 castVote and endCaptainDisputeVote with a positive vote", async () => {
      // TODO
    });

    it("#2.6 castVote and endCaptainDisputeVote with a negative vote", async () => {
      // TODO
    });
  });

  context("#3 - Manages Bounties", async () => {
    it("#3.1 create/approveBounty", async () => {
      // TODO
    });

    it("#3.2 resetBountyPayee", async () => {
      // TODO
    });

    it("#3.3 approvePayout", async () => {
      // TODO
    });
  });

});
