import { ethers } from "hardhat";

async function main() {
    const ricAddress = "0x0000000000000000000000000000000000000000";
    const name = "Mike";
    const email = "";
    const tellor = "";
    const host = "0x0000000000000000000000000000000000000000";
    const cfa = "0x0000000000000000000000000000000000000000";
    const registrationKeyCaptain = "0x0000000000000000000000000000000000000000";
    const registrationKeyBounty = "0x0000000000000000000000000000000000000000";

    const Captain = await ethers.getContractFactory("RexCaptain");
    const captain = await Captain.deploy(ricAddress, name, email, host, cfa, registrationKeyCaptain);

    await captain.deployed();

    console.log("RexCaptain deployed to:", captain.address);

    const Bounty = await ethers.getContractFactory("RexBounty");
    const bounty = await Bounty.deploy(captain.address, ricAddress, tellor, host, cfa, registrationKeyBounty);

    await bounty.deployed();

    console.log("RexBounty deployed to:", bounty.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
