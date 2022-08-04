import { ethers } from "hardhat";

async function main() {
    const captainContractAddress = "0x0000000000000000000000000000000000000000";
    const ricAddress = "0x0000000000000000000000000000000000000000";
    const tellor = "";
    const host = "0x0000000000000000000000000000000000000000";
    const cfa = "0x0000000000000000000000000000000000000000";
    const registrationKey = "0x0000000000000000000000000000000000000000";

    const Bounty = await ethers.getContractFactory("RexBounty");
    const bounty = await Bounty.deploy(captainContractAddress, ricAddress, tellor, host, cfa, registrationKey);

    await bounty.deployed();

    console.log("RexCaptain deployed to:", bounty.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
