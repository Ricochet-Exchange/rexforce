// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

contract REXForce is AccessControlEnumerable {
    // REX Force Contract
    //
    // Responsibilities:
    // - Onboard new captains
    // - Manage referrals and referred customers

    struct Captain {
        string name; // Full name of the captain
        bool approved; // Whether the captain is enabled or not
        address addr; // Address of the captain
        string email; // Email address of captain ???? (Ask if we need this)
        uint256 voteEndTimestamp;
        bool voteStarted; // Starts vote for the captain status
        bool resignVoteStarted; // Starts vote for resigning captain status
        uint votes;
    }

    mapping(address => uint256) public addressToCaptain;
    mapping(string => uint256) public emailToCaptain;
    Captain[] public captains;

    uint activeCaptains;

    // Events
    event CaptainApplied(string name, string email);
    event CaptainVotingStarted(address addr, string voteEndTimestamp);

    // Roles
    bytes32 public constant CAPTAIN_ROLE = keccak256("CAPTAIN_ROLE");

    constructor(string memory ricAddress) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setRoleAdmin(CAPTAIN_ROLE, DEFAULT_ADMIN_ROLE);
        _grantRole(CAPTAIN_ROLE, msg.sender);
        captains.push(Captain("Genesis", true, address(0), "genisis", 0, false, false, 0));
        ricAddress = ricAddress;
    }

    /// @dev Restrict calls to only from a applied captain address
    modifier appliedCaptainAddress(address addr) {
        require(addressToCaptain[addr] > 0, "Not a valid captain");
        _;
    }

    /// @dev Restricts calls to valid addresses
    modifier notZero(address addr) {
        require(addr != address(0), "Address cannot be 0");
        _;
    }

    /// @dev Restricts calls to captain role
    modifier onlyCaptain() {
        _checkRole(CAPTAIN_ROLE, msg.sender);
        _;
    }

    /// @dev Restricts calls to captain role
    modifier isCaptain(address _addr) {
        _checkRole(CAPTAIN_ROLE, _addr);
        _;
    }

    // Apply for captain
    function applyForCaptain(string memory name, string memory email) public {
        require(addressToCaptain[msg.sender] == 0, "Already applied");

        // Transfer RIC from sender
        TransferHelper.safeTransferFrom(
            address(ricAddress),
            msg.sender,
            address(this),
            (10 ** 18) * 10000 // 10k RIC transfer
        );

        Captain memory captain = Captain(name, false, msg.sender, email, block.timestamp, false, false, 0);
        appliedCaptains.push(captain);
        addressToCaptain[msg.sender] = captains.length - 1;
        emailToCaptain[email] = captains.length - 1;
        emit CaptainApplied(name, email);
    }

    function startCaptainVote(address captainAddress) public onlyCaptain appliedCaptainAddress(captainAddress) notZero(captainAddress) {
        uint memory captainIndex = addressToCaptain[captainAddress];
        require(captains[captainIndex].voteStarted == false, "Vote already started");

        // Here an idea the vote automatically ends after 14 days
        captains[captainIndex].voteEndTimestamp = block.timestamp + 14 days;
        captains[captainIndex].voteStarted = true;
        emit CaptainVotingStarted(captainAddress, block.timestamp + 14 days);
    }

    function endCaptainVote(address captainAddress) public onlyCaptain appliedCaptainAddress(captainAddress) notZero(captainAddress) {
        uint memory captainIndex = addressToCaptain[captainAddress];
        require(captains[captainIndex].voteEndTimestamp < block.timestamp, "In voting period");

        // TODO: Check quorum 2/3 of all active captains
        // TODO: Think about voting

        // if vote failed - transfer back RIC
        TransferHelper.safeTransferFrom(
            address(ricAddress),
            address(this),
            msg.sender,
            (10 ** 18) * 10000 // 10k RIC transfer
        );

        // if vote passed - increase activeCaptains and start RIC stream.
        // TODO: Start RIC stream, Transfer NFT
        activeCaptains++;
    }

    // need only 1 function for resignation which only captains can call.
    function resignCaptain(address _captainAddr) public onlyCaptain isCaptain(_captainAddr) notZero(captainAddress) {
        uint memory captainIndex = addressToCaptain[_captainAddr];
        require(captains[captainIndex].resignVoteStarted == false, "Already in voting period");

        

    }

    function endResignVote(address _captainAddr) public onlyCaptain isCaptain(_captainAddr) notZero(captainAddress) {
        uint memory captainIndex = addressToCaptain[captainAddress];
        require(captains[captainIndex].voteEndTimestamp < block.timestamp, "In voting period");

        // check the number of votes in struct

        // if passed - transfer back RIC
         TransferHelper.safeTransferFrom(
            address(ricAddress),
            address(this),
            msg.sender,
            (10 ** 18) * 10000 // 10k RIC transfer
        );

        captains[captainIndex].approved = false;
        _revokeRole(CAPTAIN_ROLE, _captainAddr);

    }

}