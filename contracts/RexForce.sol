// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

contract REXForce is AccessControlEnumerable {
    // REX Force Contract
    //
    // Responsibilities:
    // - Onboard new captains
    // - 

    using SafeERC20 for IERC20;

    // struct VoterTally {
    //     int voteId;
    //     mapping(address => bool) voted;
    // }

    struct Vote {
        uint256 id;
        uint8 kind; // 0: No voting progress, 1: captain onboarding
        address proposer; // address of the captain who proposed the vote
        uint256 start; // vote start time
        uint256 againstSum; // Number of against votes
        uint256 forSum; // Number of for votes
        mapping(address => bool) voted;
    }

    struct Captain {
        string name; // TODO: Full name of the captain ????? discuss with Mike
        bool approved; // Whether the captain is enabled
        address addr; // Address of the captain
        string email; // TODO: Email address of captain ???? (Ask if we need this)
        uint[] votes; // Array of votes for the captain status
        bool voteInProgress; // Whether a vote is in progress
    }

    struct Bounty {
        uint256 id; // ID of the bounty - (NFT reference)
        address creator; // Address of the creator of the bounty
        address approver; // Address of the approver of the bounty
        uint256 amount; // Amount of USD amount to be awarded - no decimals
        uint256 start; // Start time of the bounty
        address payee; // Address of the payee of the bounty
        bool payoutComplete; // Is payout complete?
        string ipfsHash; // Description of the bounty
        address[] approvals; // Number of votes for the bounty
    }

    mapping(address => uint256) public addressToCaptain;
    mapping(uint256 => Vote) public voteIdToVote;
    // mapping(uint256 => VoterTally) private voteIdToTally;

    Captain[] public captains;
    Bounty[] public bounties;

    uint256 public nextVoteId;

    // Events
    event CaptainApplied(string name, string email);
    event VotingStarted(address addr, uint8 kind, uint256 start);
    event VotingEnded(address addr, uint8 kind, bool approved, uint256 end);
    event HonoarablyResignedCaptain(string name, string email, address addr);
    event DishonoarablyResignedCaptain(string name, string email, address addr);
    event VoteCast(address addr, uint8 kind, bool vote);
    event BountyCreated(uint256 bountyId, address creator, string ipfsHash);
    event BountyApproved(uint256 bountyId, address approver);
    event BountyPayoutApproved(uint256 bountyId, address payee, bool payoutComplete);
    event BountyPayoutReset(uint256 bountyId, address captain);

    // Roles
    bytes32 public constant CAPTAIN_ROLE = keccak256("CAPTAIN_ROLE");

    // Vote constants
    uint8 public constant VOTE_KIND_NONE = 0;
    uint8 public constant VOTE_KIND_ONBOARDING = 1;
    uint8 public constant VOTE_KIND_RESIGN = 2;
    uint8 public constant VOTE_KIND_DISPUTE = 3;

    // Contract variables
    IERC20 public ricAddress;
    // TODO - Add function to modify this for admin
    uint256 public votingDuration = 14 days;

    constructor(IERC20 ricAddressParam, string memory name, string memory email) {   
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(CAPTAIN_ROLE, msg.sender);
        captains.push(Captain("Genesis", false, address(0), "genisis@genesis", new uint256[](0), false));
        // Deployer is the first captain (auto-approved) 
        captains.push(Captain(name, true, msg.sender, email, new uint256[](0), false));
        addressToCaptain[msg.sender] = captains.length - 1;
        ricAddress = ricAddressParam;
        nextVoteId = 1;
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
        uint256 captainId = addressToCaptain[addr];
        Captain memory captain = captains[captainId];
        require(captain.approved == false, "Captain is already approved");
        _;
    }
    
    modifier noVoteInProgress(address addr) {
        uint256 captainId = addressToCaptain[addr];
        Captain memory captain = captains[captainId];
        require(captain.voteInProgress == false, "A vote is already in progress");
        _;
    }

    modifier voteInProgress(address addr) {
        uint256 captainId = addressToCaptain[addr];
        Captain memory captain = captains[captainId];
        require(captain.voteInProgress, "No vote in progress");
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

    modifier onlyApprovedBounty(uint256 bountyId) {
        require(bounties[bountyId].approver != address(0), "Bounty not approved");
        _;
    }

    /// @dev Add a captain to the REXForce
    function _addCaptain(string memory name, string memory email, address addr) internal {
        captains.push(Captain(name, false, addr, email, new uint256[](0), false));
        addressToCaptain[addr] = captains.length - 1;
    }

    // Adds RIC to contract
    function fundContractWithRIC(uint256 amount) public {
        ricAddress.safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
    }



    function _createVote(address captainAddress, uint8 kind, uint256 time) internal {
        uint256 captainId = addressToCaptain[captainAddress];
        // Create the vote
        Vote storage vote = voteIdToVote[nextVoteId];
        vote.id = nextVoteId;
        vote.kind = kind;
        vote.proposer = captainAddress;
        vote.start = time;
        vote.againstSum = 0;
        vote.forSum = 0;

        // Add the vote to the captain
        Captain storage captain = captains[captainId];
        captain.votes.push(nextVoteId);
        captain.voteInProgress = true;

        nextVoteId += 1;
    }

    function _stopVote(address captainAddress) internal {
        uint256 captainId = addressToCaptain[captainAddress];
        Captain storage captain = captains[captainId];
        captain.voteInProgress = false;
    }

    function _getCaptain(address captainAddress) internal view returns (Captain storage captain) {
        uint256 captainId = addressToCaptain[captainAddress];
        captain = captains[captainId];
        return captain;
    }

    function _getCurrentVote(address captainAddress) internal returns (Vote storage vote) {
        Captain storage captain = _getCaptain(captainAddress);
        return voteIdToVote[captain.votes.length - 1];
    }

    // Apply for captain
    function applyForCaptain(string memory name, string memory email) public {
        // Dishonorable or already applied
        require(addressToCaptain[msg.sender] == 0, "Already applied or can't apply");

        // Transfer RIC from sender
        ricAddress.safeTransferFrom(
            msg.sender,
            address(this),
            (10 ** 18) * 10000 // 10k RIC transfer
        );

        _addCaptain(name, email, msg.sender);
        uint256 time = block.timestamp;
        _createVote(msg.sender, VOTE_KIND_ONBOARDING, time);
        
        emit VotingStarted(msg.sender, VOTE_KIND_ONBOARDING, time);
    }

    function endCaptainOnboardingVote(address captainAddress)
        public
        onlyCaptain
        validCaptain(captainAddress)
        forAppliedCaptain(captainAddress)
    {
        Captain storage captain = _getCaptain(captainAddress);
        Vote storage currentVote = _getCurrentVote(captainAddress);

        uint256 time = block.timestamp;
        require(currentVote.kind == VOTE_KIND_ONBOARDING, "Invalid vote kind");
        require(currentVote.start + votingDuration < time, "Voting duration not expired");

        uint256 quorum = ((captains.length * 2) / 3);
        // If quorum is not a whole number, take its ceiling
        if ((captains.length * 2) % 3 > 0) {
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
            // startRicStream(captainAddress); // TODO: Start RIC stream, tansfer NFT
            passed = true;
        } else {
            // if vote failed - transfer back RIC
            ricAddress.safeTransfer(
                captainAddress,
                (10 ** 18) * 10000 // 10k RIC transfer
            );
            addressToCaptain[captainAddress] = 0;
        }
        _stopVote(captainAddress);

        emit VotingEnded(captainAddress, VOTE_KIND_ONBOARDING, passed, time);
    }

    function castVote(address captainAddress, bool vote)
        public
        onlyCaptain
        validCaptain(captainAddress)
        voteInProgress(captainAddress)
    {
        Vote storage currentVote = _getCurrentVote(captainAddress);
        require(currentVote.voted[msg.sender] == false, "Already voted");

        if (vote) {
            currentVote.forSum += 1;
        } else {
            currentVote.againstSum += 1;
        }

        currentVote.voted[msg.sender] = true;

        emit VoteCast(captainAddress, currentVote.kind, vote);
    }

    function resignCaptain() public onlyCaptain noVoteInProgress(msg.sender) {
        
        uint256 time = block.timestamp;
        _createVote(msg.sender, VOTE_KIND_RESIGN, time);

        emit VotingStarted(msg.sender, VOTE_KIND_RESIGN, time);
    }

    function endCaptainResignVote(address captainAddress) public onlyCaptain isCaptain(captainAddress) voteInProgress(captainAddress) {
        Captain storage captain = _getCaptain(captainAddress);
        Vote storage currentVote = _getCurrentVote(captainAddress);
        uint256 time = block.timestamp;
        require(currentVote.kind == VOTE_KIND_RESIGN, "Invalid vote kind");
        require(currentVote.start + votingDuration < time, "Voting duration not expired");
        
        // TODO - move this to a function
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
            // TODO - move this to a function
            ricAddress.safeTransfer(
                captainAddress,
                (10 ** 18) * 10000 // 10k RIC transfer
            );

            addressToCaptain[captainAddress] = 0; // If failed and approved != 0 means dishonorable resignation
            passed = true;
        } else {
            passed = false;
        }

        _revokeRole(CAPTAIN_ROLE, captainAddress);
        captain.approved = false;
        // stopRicStream(captainAddress); // TODO: Stop RIC stream, revoke NFT

        _stopVote(captainAddress);

        emit VotingEnded(captainAddress, VOTE_KIND_RESIGN, passed, time);
    }

    function disputeCaptain(address captainAddress) public onlyCaptain isCaptain(captainAddress) noVoteInProgress(captainAddress) {
        // Transfer 1k RIC from disputer to contract
        // TODO - function
        ricAddress.safeTransferFrom(
            msg.sender,
            address(this),
            (10 ** 18) * 1000 // 1k RIC transfer
        );

        uint256 time = block.timestamp;
        _createVote(captainAddress, VOTE_KIND_DISPUTE, time);

        emit VotingStarted(msg.sender, VOTE_KIND_DISPUTE, time);
    }

    function endCaptainDisputeVote(address captainAddress) public onlyCaptain isCaptain(captainAddress) voteInProgress(captainAddress) {
        Captain storage captain = _getCaptain(captainAddress);
        Vote storage currentVote = _getCurrentVote(captainAddress);
        uint256 time = block.timestamp;
        require(currentVote.kind == VOTE_KIND_DISPUTE, "Invalid vote kind");
        require(currentVote.start + votingDuration < time, "Voting duration not expired");

        // TODO - function
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
            // send 1k RIC to disputer
            ricAddress.safeTransferFrom(
                msg.sender,
                currentVote.proposer,
                (10 ** 18) * 1000
            );
            // TODO - function
            _revokeRole(CAPTAIN_ROLE, captainAddress);
            captain.approved = false;
            // stopRicStream(captainAddress); // TODO: Stop RIC stream, revoke NFT
            passed = true;
        } else {
            passed = false;
        }

        _stopVote(captainAddress);

        emit VotingEnded(captainAddress, VOTE_KIND_DISPUTE, passed, time);
    }

    function createBounty(uint256 bountyAmount, string memory ipfsHash) public onlyCaptain {
        uint256 time = block.timestamp;
        uint256 bountyId = bounties.length;
        Bounty memory bounty = Bounty(bountyId, msg.sender, address(0), bountyAmount, time, address(0), false, ipfsHash, new address[](0));
        bounties.push(bounty);

        emit BountyCreated(bountyId, msg.sender, ipfsHash);
    }

    function approveBounty(uint256 bountyId) public onlyCaptain {
        require(bountyId < bounties.length, "Bounty does not exist");
        require(bounties[bountyId].approver == address(0), "Bounty already approved");
        require(bounties[bountyId].creator != msg.sender, "Cannot approve own bounty");

        bounties[bountyId].approver = msg.sender;

        emit BountyApproved(bountyId, msg.sender);
    }
    
    function approvePayout(uint256 bountyId, address payee) public onlyCaptain onlyApprovedBounty(bountyId) {
        require(payee != address(0), "Address cannot be 0");
        require(bountyId < bounties.length, "Bounty does not exist");
        
        Bounty storage bounty = bounties[bountyId];

        require(bounty.payoutComplete == false, "Payout already completed");
        require(bounty.payee == address(0) || bounty.payee == payee, "Payee does not match");
        require(bounty.approvals.length == 0 || bounty.approvals[0] != msg.sender, "Already approved");
        
        // If we already have 1 approval, we can pay out and mint bountyNFT
        if (bounty.approvals.length == 1) {
            // TODO: Transfer USD valued RIC to payee
            bounty.payoutComplete = true;
        }

        bounty.approvals.push(msg.sender);
        bounty.payee = payee;

        emit BountyPayoutApproved(bountyId, payee, bounty.payoutComplete);
    }

    function resetBountyPayee(uint256 bountyId) public onlyCaptain onlyApprovedBounty(bountyId) {
        require(bountyId < bounties.length, "Bounty does not exist");
        Bounty storage bounty = bounties[bountyId];

        require(bounty.payoutComplete == false, "Payout already completed");

        bounty.payee = address(0);
        delete bounty.approvals;

        emit BountyPayoutReset(bountyId, msg.sender);
    }
}
