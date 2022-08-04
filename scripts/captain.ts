import { ethers } from "hardhat";

async function main() {
    const ricAddress = "0x0000000000000000000000000000000000000000";
    const name = "Mike";
    const email = "";
    const _host = "0x0000000000000000000000000000000000000000";
    const _cfa = "0x0000000000000000000000000000000000000000";
    const _registrationKey = "0x0000000000000000000000000000000000000000";

    const Captain = await ethers.getContractFactory("RexCaptain");
    const captain = await Captain.deploy(ricAddress, name, email, _host, _cfa, _registrationKey);

    await captain.deployed();

    console.log("RexCaptain deployed to:", captain.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
