
let { toWad } = require("@decentral.ee/web3-helpers");
let { Framework } = require("@superfluid-finance/sdk-core");
let { expect, assert } = require("chai");
let { ethers, web3 } = require("hardhat");
let ricABI = require("./abis/fDAIABI");
import traveler from "ganache-time-traveler";
import { REXCaptain } from "../typechain";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

const ONE_MONTH_TRAVEL_TIME = 60 * 60 * 24 * 30; // 1 month
const VOTING_DURATION = 60 * 60 * 24 * 14;
const CAPTAINS_FLOW_RATE = "317097919837645";
const REXFORCE_FLOW_RATE = "31709791983764500";
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
let rexForce: InstanceType<typeof REXCaptain>;
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

  let App = await ethers.getContractFactory("REXCaptain", firstCaptain);

  //deploy the contract
  console.log("CFA", sf.settings.config.cfaV1Address)
  rexForce = await App.deploy(
    ricx.address,
    "Alice",
    "alice@alice.com",
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
    flowRate: REXFORCE_FLOW_RATE
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

let totalStake = ethers.utils.parseEther("0");
let lostStake = ethers.utils.parseEther("0");

describe("REXForce", async function () {

  context.only("#1 - Onboards a captain, modifyCaptainStake", async () => {

    it("#1.1 has first captain", async () => {
      assert.equal(
        (await rexForce.captains(0)).toString(),
        'Genesis,false,0x0000000000000000000000000000000000000000,genisis@genesis,0,false,0,0',
        'genisis captain does not exist'
      );
      assert.equal(
        (await rexForce.captains(1)).toString(),
        `Alice,true,${firstCaptain.address},alice@alice.com,0,false,0,0`,
        'first captain does not exist'
      );

      let ricxApproveOperation = ricx.approve({
        receiver: rexForce.address,
        amount: CAPTAINS_STAKE_AMOUNT
      });
      await ricxApproveOperation.exec(firstCaptain);

      await rexForce.connect(firstCaptain).modifyCaptainStake();
      totalStake = totalStake.add(CAPTAINS_STAKE_AMOUNT);

      // TODO
      assert.equal(
        (await netFlowRate(firstCaptain)).toString(),
        CAPTAINS_FLOW_RATE,
        'first captain not paid'
      );

      expect((await ricx.balanceOf({
        account: firstCaptain.address,
        providerOrSigner: admin
      }))).to.equal(ethers.utils.parseEther("990000"));

    });

    it("#1.2 applyForCaptain", async () => {

      // Try to reapply firstCaptain and revert
      await expect(
        rexForce.connect(firstCaptain).applyForCaptain("Alice", "alice@alice.com")
      ).to.be.revertedWith("Already applied or can't apply");

      let ricxApproveOperation = ricx.approve({
        receiver: rexForce.address,
        amount: CAPTAINS_STAKE_AMOUNT
      });
      await ricxApproveOperation.exec(secondCaptain);

      await expect(
        rexForce.connect(secondCaptain).applyForCaptain("Bob", "bob@bob.com")
      )
        .to.emit(rexForce, "CaptainApplied")
        .withArgs(
          "Bob",
          "bob@bob.com"
        )
        .to.emit(rexForce, "VotingStarted")
        .withArgs(
          secondCaptain.address,
          VOTE_KIND_ONBOARDING
        )

      totalStake = totalStake.add(CAPTAINS_STAKE_AMOUNT);
    });

    it("#1.3 castVote and endCaptainOnboardingVote with yes vote", async () => {

      // firstCaptain votes to approve secondCaptain
      await expect(
        rexForce.connect(firstCaptain).castVote(secondCaptain.address, true)
      )
        .to.emit(rexForce, "VoteCast")
        .withArgs(
          secondCaptain.address,
          VOTE_KIND_ONBOARDING,
          true
        );

      let timestamp = (await ethers.provider.getBlock('latest')).timestamp
      let vote = await rexForce.voteIdToVote(1);
      await expect(vote[0]).to.equal(ethers.BigNumber.from(1))
      await expect(vote[1]).to.equal(VOTE_KIND_ONBOARDING)
      await expect(vote[2]).to.equal(secondCaptain.address)
      await expect(vote[3]).to.be.within(ethers.BigNumber.from(timestamp - 2), ethers.BigNumber.from(timestamp + 2))
      await expect(vote[4]).to.equal(ethers.BigNumber.from(0))
      await expect(vote[5]).to.equal(ethers.BigNumber.from(1))

      await expect(
        rexForce.connect(firstCaptain).castVote(secondCaptain.address, true)
      ).to.be.revertedWith("Already voted");

      await expect(
        rexForce.connect(firstCaptain).endCaptainOnboardingVote(secondCaptain.address)
      ).to.be.revertedWith("Voting duration not expired");

      await traveler.advanceTimeAndBlock(VOTING_DURATION);

      await expect(
        rexForce.connect(firstCaptain).endCaptainOnboardingVote(secondCaptain.address)
      )
        .to.emit(rexForce, "VotingEnded")
        .withArgs(
          secondCaptain.address,
          VOTE_KIND_ONBOARDING,
          true
        );

      let captainIndex = await rexForce.addressToCaptain(secondCaptain.address);
      await expect(captainIndex).to.not.equal(ethers.BigNumber.from(0));

      let captain = await rexForce.captains(captainIndex);
      await expect(captain[1]).to.equal(true);
      await expect(captain[6]).to.equal(CAPTAINS_STAKE_AMOUNT);

      assert.equal(
        (await netFlowRate(secondCaptain)).toString(),
        CAPTAINS_FLOW_RATE,
        'second captain not paid'
      );

      expect((await ricx.balanceOf({
        account: secondCaptain.address,
        providerOrSigner: admin
      }))).to.equal(ethers.utils.parseEther("990000"));
    });

    it("#1.4 castVote and endCaptainOnboardingVote with no vote", async () => {

      let ricxApproveOperation = ricx.approve({
        receiver: rexForce.address,
        amount: CAPTAINS_STAKE_AMOUNT
      });
      await ricxApproveOperation.exec(thirdCaptain);

      await expect(
        rexForce.connect(thirdCaptain).applyForCaptain("Carl", "carl@carl.com")
      )
        .to.emit(rexForce, "CaptainApplied")
        .withArgs(
          "Carl",
          "carl@carl.com"
        )
        .to.emit(rexForce, "VotingStarted")
        .withArgs(
          thirdCaptain.address,
          VOTE_KIND_ONBOARDING
        )

      totalStake = totalStake.add(CAPTAINS_STAKE_AMOUNT);

      await rexForce.connect(firstCaptain).castVote(thirdCaptain.address, false);

      await traveler.advanceTimeAndBlock(VOTING_DURATION);

      // Change stake amount temporarily to ensure the correct stake is returned
      await expect(
        rexForce.connect(firstCaptain).modifyCaptainAmountToStake(CAPTAINS_STAKE_AMOUNT.mul(2))
      )
        .to.emit(rexForce, "CaptainStakeChanged")
        .withArgs(
          CAPTAINS_STAKE_AMOUNT,
          CAPTAINS_STAKE_AMOUNT.mul(2)
        );

      await expect(
        rexForce.connect(firstCaptain).endCaptainOnboardingVote(thirdCaptain.address)
      )
        .to.emit(rexForce, "VotingEnded")
        .withArgs(
          thirdCaptain.address,
          VOTE_KIND_ONBOARDING,
          false
        );

      totalStake = totalStake.sub(CAPTAINS_STAKE_AMOUNT);

      console.log("totalStake = " + totalStake);
      console.log("stakedAmount from contract = " + await rexForce.totalStakedAmount())

      assert.equal(
        (await rexForce.totalStakedAmount()).toString(),
        totalStake,
        'TotalStakedAmount incorrect'
      );

      let captainIndex = await rexForce.addressToCaptain(thirdCaptain.address);
      await expect(captainIndex).to.equal(ethers.BigNumber.from(0));

      assert.equal(
        (await netFlowRate(thirdCaptain)).toString(),
        ethers.utils.parseEther("0"),
        'third captain getting paid'
      );

      expect((await ricx.balanceOf({
        account: thirdCaptain.address,
        providerOrSigner: admin
      }))).to.equal(ethers.utils.parseEther("1000000"));

      // Set the stake amount back to its original value
      rexForce.connect(firstCaptain).modifyCaptainAmountToStake(CAPTAINS_STAKE_AMOUNT);
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
