// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/access/AccessControlStatic.sol";

contract REXForce is AccessControlEnumerable {
    // REX Force Contract
    //
    // Responsibilities:
    // - Onboard new captains
    // - 

    struct Vote {
        uint8 kind; // 0: No voting progress, 1: captain onboarding
        address proposer; // address of the captain who proposed the vote
        uint256 start; // vote start time
        uint256 againstSum; // Number of against votes
        uint256 forSum; // Number of for votes
        mapping(address => bool) voted; // TODO - Do we need to maintain array of voters?
    }

    struct Captain {
        string name; // TODO: Full name of the captain ????? discuss with Mike
        bool approved; // Whether the captain is enabled
        bool resigned; // Whether the captain resigned
        address addr; // Address of the captain
        string email; // TODO: Email address of captain ???? (Ask if we need this)
        Vote[] votes; // Array of votes for the captain status
        Vote currentVote; // Current vote for the captain status
    }

    mapping(address => uint256) public addressToCaptain;
    Captain[] public captains;

    // Events
    event CaptainApplied(string name, string email);
    event VotingStarted(address addr, uint8 kind, uint256 start);
    event VotingEnded(address addr, uint8 kind, bool approved, uint256 end);
    event HonoarablyResignedCaptain(string name, string email, address addr);
    event DishonoarablyResignedCaptain(string name, string email, address addr);
    event VoteCast(address addr, uint8 kind, bool vote);

    // Roles
    bytes32 public constant CAPTAIN_ROLE = keccak256("CAPTAIN_ROLE");

    // Vote constants
    uint8 public constant VOTE_KIND_NONE = 0;
    uint8 public constant VOTE_KIND_ONBOARDING = 1;

    // Contract variables
    IERC20 public ricAddress;
    // TODO - Add function to modify this for admin
    uint256 public votingDuration = 14 days;

    constructor(IERC20 ricAddress, string memory name, string memory email) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(CAPTAIN_ROLE, msg.sender);
        Vote[] memory emptyVotes;
        Vote memory emptyVote;
        captains.push(Captain("Genesis", false, false, false, address(0), "genisis@genesis", emptyVotes, emptyVote));
        // Deployer is the first captain (auto-approved) 
        captains.push(Captain(name, true, false, false, msg.sender, email, emptyVotes, emptyVote));
        addressToCaptain[msg.sender] = captains.length - 1;
        ricAddress = ricAddress;
    }

    /// @dev Validate a captain
    modifier validCaptain(address addr) {
        require(addr != address(0), "Address cannot be 0");
        uint256 captainId = addressToCaptain[addr];
        require(captainId > 0, "Not a valid captain");
        _;
    }

    /// @dev Restrict calls to only from a applied captain address
    modifier forAppliedCaptain(address addr) {
        Captain memory captain = captains[captainId];
        require(captain.resigned == false, "Captain dishonoarably resigned");
        require(captain.approved == false, "Captain is already approved");
        _;
    }
    
    modifier noVoteInProgress(address addr) {
        uint256 captainId = addressToCaptain[addr];
        Captain memory captain = captains[captainId];
        require(captain.currentVote.kind == VOTE_KIND_NONE, "A vote is already in progress");
        _;
    }

    modifier voteInProgress(address addr) {
        uint256 captainId = addressToCaptain[addr];
        Captain memory captain = captains[captainId];
        require(captain.currentVote.kind != VOTE_KIND_NONE, "No vote in progress");
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

    /// @dev Add a captain to the REXForce
    function _addCaptain(string memory name, string memory email, address addr) internal {
        Vote[] memory emptyVotes;
        Vote memory emptyVote;
        captains.push(Captain(name, false, false, false, addr, email, emptyVotes, emptyVote));
        addressToCaptain[addr] = captains.length - 1;
    }

    function _createVote(address captainAddress, uint8 kind, uint256 time) internal {
        uint256 captainId = addressToCaptain[captainAddress];
        Captain storage captain = captains[captainId];
        captain.currentVote.kind = kind; // Vote for captain onboarding
        captain.currentVote.start = time;
        captain.currentVote.proposer = msg.sender;
        captain.currentVote.rejectSum = 0;
        captain.currentVote.approveSum = 0;
    }

    function _stopVote(address captainAddress) internal {
        uint256 captainId = addressToCaptain[captainAddress];
        Captain storage captain = captains[captainId];
        captain.currentVote.kind = VOTE_KIND_NONE;
    }

    // Apply for captain
    function applyForCaptain(string memory name, string memory email) public {
        // Dishonorable or already applied
        require(addressToCaptain[msg.sender] == 0, "Already applied or can't apply");

        // Transfer RIC from sender
        TransferHelper.safeTransferFrom(
            address(ricAddress),
            msg.sender,
            address(this),
            (10 ** 18) * 10000 // 10k RIC transfer
        );

        _addCaptain(name, email, msg.sender);
        uint256 time = block.timestamp;
        _createVote(captainAddress, VOTE_KIND_ONBOARDING, time);
        
        emit VotingStarted(msg.sender, VOTE_KIND_ONBOARDING, time);
    }

    function endCaptainOnboardingVote(address captainAddress)
        public
        onlyCaptain
        validCaptain(captainAddress)
        forAppliedCaptain(captainAddress)
    {
        uint captainIndex = addressToCaptain[captainAddress];
        Captain storage captain = captains[captainIndex];
        Vote memory currentVote = captains[captainIndex].currentVote;
        uint256 time = block.timestamp;
        require(currentVote.kind == VOTE_KIND_ONBOARDING, "Invalid vote kind");
        require(currentVote.start + votingDuration < time, "Voting duration not expired");

        uint256 qMul = captains.length * 2;
        uint256 quorum = (qMul / 3);
        // If quorum is not a whole number, take its ceiling
        if (qMul % 3 > 0) {
            quorum += 1;
        }
        uint256 approved = currentVote.forSum;
        uint256 rejected = currentVote.againstSum;
        require(approved + rejected >= quorum, "Not enough votes");

        bool passed = false;

        if (approved > rejected) {
            // if vote passed - increase activeCaptains and start RIC stream.
            _grantRole(CAPTAIN_ROLE, captainAddress);
            captain.approved = true;
            startRicStream(captainAddress); // TODO: Start RIC stream, tansfer NFT
            passed = true;
        } else {
            // if vote failed - transfer back RIC
            TransferHelper.safeTransferFrom(
                address(ricAddress),
                address(this),
                captainAddress,
                (10 ** 18) * 10000 // 10k RIC transfer
            );
            addressToCaptain[captainAddress] = 0;
        }
        captain.votes.push(captain.currentVote);
        _stopVote(captainAddress);

        emit votingEnded(captainAddress, VOTE_KIND_ONBOARDING, passed, time);
    }

    function castVote(address captainAddress, bool vote)
        public
        onlyCaptain
        validCaptain(captainAddress)
        voteInProgress(captainAddress)
    {
        uint captainIndex = addressToCaptain[captainAddress];
        Vote storage currentVote = captains[captainIndex].currentVote;
        require(currentVote.voted[msg.sender] == false, "Already voted");

        if (vote) {
            currentVote.forSum += 1;
        } else {
            currentVote.againstSum += 1;
        }

        currentVote.voted[msg.sender] = true;

        emit VoteCast(captainAddress, currentVote.kind, vote);
    }

    function resignCaptain() public onlyCaptain {
        uint memory captainIndex = addressToCaptain[msg.sender];
        require(captains[captainIndex].resignVoteStarted == false, "Already in voting period");

        // Think about starting a vote @dxdy

    }

    function endResignVote(address _captainAddr) public onlyCaptain isCaptain(_captainAddr) notZero(_captainAddr) {
        uint memory captainIndex = addressToCaptain[_captainAddr];
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

        // Revoke NFT
        // Cancel the base 10k RIC stream 

    }

    function disputeCaptain(address _captainAddr) public onlyCaptain isCaptain(_captainAddr) notZero(_captainAddr) {
        // Again think of voting @dxdy and start dispute vote

        // Transfer 1k RIC
         TransferHelper.safeTransferFrom(
            address(ricAddress),
            msg.sender,
            address(this),
            (10 ** 18) * 1000 // 1k RIC transfer
        );
    }

    function disputeCaptain(address _captainAddr) public onlyCaptain isCaptain(_captainAddr) notZero(_captainAddr) {
        // if passed send back 1k RIC to dispute calling captain, 
        // and safely revoke _captainAddr role, nft, cancel 
        
        // If failed do nothing, dispute called 1k RIC gone.
    }
}