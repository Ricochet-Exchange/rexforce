// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.14;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { IREXCaptain } from "../captain/IRexCaptain.sol";
import { RexBountyStorage } from "./RexBountyStorage.sol";

contract REXBounty is Ownable, ERC721URIStorage {

    using SafeERC20 for ISuperToken;
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    RexBountyStorage.Bounty[] public bounties;

    // Events
    event BountyCreated(uint256 bountyId, address creator, string ipfsHash);
    event BountyApproved(uint256 bountyId, address approver);
    event BountyPayoutApproved(uint256 bountyId, address payee, bool payoutComplete);
    event BountyPayoutReset(uint256 bountyId, address captain);

    // Contract variables
    ISuperToken public ric;
    IREXCaptain public captainHost;

    constructor(
        IREXCaptain _captainHost,
        ISuperToken ricAddress
    ) ERC721("RexForce Token", "RFT") {

        ric = ricAddress;
        captainHost = _captainHost;

    }

    modifier onlyApprovedBounty(uint256 bountyId) {
        require(bountyId < bounties.length, "Bounty does not exist");
        require(bounties[bountyId].approvals.length > 1, "Bounty not approved");
        _;
    }

    modifier onlyCaptain() {
        captainHost.isCaptainExt(msg.sender);
        _;
    }

    function changeCaptainHost(IREXCaptain _captainHost) public onlyOwner {
        captainHost = _captainHost;
    }

    // Adds RIC to contract
    // Be generous and donate a lot of RIC to the contract
    function fundContractWithRIC(uint256 amount) public {
        ric.safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
    }

    function createNFT(address payee, string memory ipfsHashURI)
        private
        returns (uint256)
    {
        uint256 newItemId = _tokenIds.current();
        _mint(payee, newItemId);
        _setTokenURI(newItemId, ipfsHashURI);

        _tokenIds.increment();
        return newItemId;
    }

    function createBounty(uint256 bountyAmount, string memory ipfsHashURI) public onlyCaptain {
        uint256 time = block.timestamp;
        uint256 bountyId = bounties.length;
        address[] memory approvals = new address[](1);
        approvals[0] = msg.sender;
        RexBountyStorage.Bounty memory bounty = RexBountyStorage.Bounty(bountyId, msg.sender, address(0), bountyAmount, time, address(0), false, ipfsHashURI, approvals);
        bounties.push(bounty);
        emit BountyCreated(bountyId, msg.sender, ipfsHashURI);
    }

    function approveBounty(uint256 bountyId) public onlyCaptain {
        require(bountyId < bounties.length, "Bounty does not exist");
        require(bounties[bountyId].creator != msg.sender, "Cannot approve own bounty");

        // TODO: Are both reequired?
        bounties[bountyId].approvals.push(msg.sender);

        emit BountyApproved(bountyId, msg.sender);
    }

    function approvePayout(uint256 bountyId, address payee) public onlyCaptain onlyApprovedBounty(bountyId) {
        require(payee != address(0), "Address cannot be 0");
        require(captainHost.isCaptainDisputed(msg.sender) == false, "Disputed captain");

        RexBountyStorage.Bounty storage bounty = bounties[bountyId];

        require(bounty.payoutComplete == false, "Payout already completed");
        require(bounty.payee == address(0) || bounty.payee == payee, "Payee does not match");

        ric.safeTransfer(payee, bounty.amount);

        createNFT(payee, bounty.ipfsHashURI);
        bounty.payoutComplete = true;
        bounty.payee = payee;

        emit BountyPayoutApproved(bountyId, payee, bounty.payoutComplete);
    }

    function resetBountyPayee(uint256 bountyId) public onlyCaptain onlyApprovedBounty(bountyId) {
        RexBountyStorage.Bounty storage bounty = bounties[bountyId];

        require(bounty.payoutComplete == false, "Payout already completed");

        bounty.payee = address(0);
        delete bounty.approvals;

        emit BountyPayoutReset(bountyId, msg.sender);
    }
}
