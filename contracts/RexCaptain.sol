// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.11;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "./tellor/ITellor.sol";
import {SuperAppBase} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperAppBase.sol";
import {IConstantFlowAgreementV1} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";
import {ISuperfluid, ISuperToken, ISuperApp, ISuperAgreement, SuperAppDefinitions} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

import {RexCaptainStorage} from "./RexCaptainStorage.sol";

contract REXCaptain is AccessControlEnumerable, SuperAppBase {

    using SafeERC20 for IERC20;
    // using RexCaptainStorage for REXCaptain;

    // using RexCaptainStorage for RexCaptainStorage.Vote;
    // using RexCaptainStorage for RexCaptainStorage.Captain;

    // Events
    event CaptainApplied(string name, string email);
    event VotingStarted(address addr, uint8 kind, uint256 start);
    event VotingEnded(address addr, uint8 kind, bool approved, uint256 end);
    // TODO use single event and have bool for honourable
    event HonoarablyResignedCaptain(string name, string email, address addr);
    event DishonoarablyResignedCaptain(string name, string email, address addr);
    event VoteCast(address captainAddress, uint8 kind, bool vote);

    //
    //
    // ------------ State variables start ------------
    //
    //

    mapping(address => uint256) public addressToCaptain;
    mapping(uint256 => RexCaptainStorage.Vote) public voteIdToVote;
    // mapping(uint256 => VoterTally) private voteIdToTally;

    RexCaptainStorage.Captain[] public captains;
    
    uint256 public nextVoteId;

    // Contract variables
    IERC20 public ricAddress;
    ISuperfluid internal host; // Superfluid host contract
    IConstantFlowAgreementV1 internal cfa; // The stored constant flow agreement class address

    // TODO - Add function to modify this for admin
    uint256 public votingDuration = 14 days;

    uint256 public captainAmountToStake = (10 ** 18) * 10000;

    // TODO: Never modify this as we are not storing how much REX is staked for dispute
    uint256 public disputeAmountToStake = (10 ** 18) * 1000;

    uint256 public totalStakedAmount = 0;

    //
    //
    // ------------ State variables end ------------
    //
    //

    constructor(
        IERC20 ricAddressParam,
        string memory name,
        string memory email,
        ISuperfluid _host,
        IConstantFlowAgreementV1 _cfa,
        string memory _registrationKey
    ) {
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(CAPTAIN_ROLE, msg.sender);
        captains.push(Captain("Genesis", false, address(0), "genisis@genesis", new uint256[](0), false, 0));
        // Deployer is the first captain (auto-approved)
        captains.push(Captain(name, true, msg.sender, email, new uint256[](0), false, 0));
        addressToCaptain[msg.sender] = captains.length - 1;
        ricAddress = ricAddressParam;
        nextVoteId = 1;

        // SuperApp set up
        host = _host;
        cfa = _cfa;

        uint256 _configWord = SuperAppDefinitions.APP_LEVEL_FINAL |
            SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP |
            SuperAppDefinitions.AFTER_AGREEMENT_CREATED_NOOP |
            SuperAppDefinitions.AFTER_AGREEMENT_UPDATED_NOOP |
            SuperAppDefinitions.AFTER_AGREEMENT_TERMINATED_NOOP;

        if (bytes(_registrationKey).length > 0) {
            host.registerAppWithKey(_configWord, _registrationKey);
        } else {
            host.registerApp(_configWord);
        }
    }

    // Modifiers
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

    /// @dev Add a captain to the REXForce
    function _addCaptain(string memory name, string memory email, address addr) internal {
        captains.push(Captain(name, false, addr, email, new uint256[](0), false, captainAmountToStake));
        addressToCaptain[addr] = captains.length - 1;
    }

    /// @dev Create vote
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

    function _getCurrentVote(address captainAddress) internal view returns (Vote storage vote) {
        Captain storage captain = _getCaptain(captainAddress);
        return voteIdToVote[captain.votes.length - 1];
    }

    function _isVotePassed(Vote storage currentVote) internal view returns (bool) {
        uint256 qMul = captains.length * 2;
        uint256 quorum = (qMul / 3);
        // If quorum is not a whole number, take its ceiling
        if (qMul % 3 > 0) {
            quorum += 1;
        }

        require(currentVote.forSum + currentVote.againstSum >= quorum, "Not enough votes");

        if (currentVote.forSum > currentVote.againstSum)
            return true;

        return false;
    }

    // Apply for captain
    function applyForCaptain(string memory name, string memory email) public {
        // Dishonorable or already applied
        require(addressToCaptain[msg.sender] == 0, "Already applied or can't apply");

        // Transfer RIC from sender
        ricAddress.safeTransferFrom(
            msg.sender,
            address(this),
            captainAmountToStake // RIC transfer for stake
        );
        totalStakedAmount += captainAmountToStake;

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

        bool passed = _isVotePassed(currentVote);

        if (passed) {
            // if vote passed - increase activeCaptains and start RIC stream.
            _grantRole(CAPTAIN_ROLE, captainAddress);
            captain.approved = true;
            // startRicStream(captainAddress); // TODO: Start RIC stream, tansfer NFT
        } else {
            // if vote failed - transfer back RIC
            ricAddress.safeTransfer(
                captainAddress,
                captainAmountToStake // Staked RIC return
            );
            addressToCaptain[captainAddress] = 0;
            totalStakedAmount -= captainAmountToStake;
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

        bool passed = _isVotePassed(currentVote);

        if (passed) {
            // TODO - move this to a function
            ricAddress.safeTransfer(
                captainAddress,
                captain.stakedAmount // 10k RIC transfer
            );

            addressToCaptain[captainAddress] = 0; // If failed and approved != 0 means dishonorable resignation
        }

        totalStakedAmount -= captain.stakedAmount;

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
            disputeAmountToStake // 1k RIC transfer
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

        bool passed = _isVotePassed(currentVote);

        if (passed) {
            // send 1k RIC to disputer
            ricAddress.safeTransferFrom(
                msg.sender,
                currentVote.proposer,
                disputeAmountToStake
            );
            // TODO - function
            _revokeRole(CAPTAIN_ROLE, captainAddress);
            captain.approved = false;
            // stopRicStream(captainAddress); // TODO: Stop RIC stream, revoke NFT
        }

        _stopVote(captainAddress);

        emit VotingEnded(captainAddress, VOTE_KIND_DISPUTE, passed, time);
    }

}