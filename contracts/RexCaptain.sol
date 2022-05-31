// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.14;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "./tellor/ITellor.sol";
import { SuperAppBase } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperAppBase.sol";
import { IConstantFlowAgreementV1 } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";
import { ISuperfluid, ISuperToken, SuperAppDefinitions } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { CFAv1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/CFAv1Library.sol";

import { RexCaptainStorage } from "./RexCaptainStorage.sol";

contract REXCaptain is AccessControlEnumerable, SuperAppBase {

    using CFAv1Library for CFAv1Library.InitData;
    using SafeERC20 for ISuperToken;

    CFAv1Library.InitData public cfaV1;

    // Events
    event CaptainApplied(string name, string email);
    event VotingStarted(address addr, uint8 kind);
    event VotingEnded(address addr, uint8 kind, bool approved);
    event VoteCast(address captainAddress, uint8 kind, bool vote);
    event CaptainUpdatedStake(uint256 oldAmount, uint256 newAmount);
    event CaptainStakeChanged(uint256 oldAmount, uint256 newAmount);
    event DisputeStakeChanged(uint256 oldAmount, uint256 newAmount);
    event VotingDurationChanged(uint256 oldDuration, uint256 newDuration);

    mapping(address => uint256) public addressToCaptain;
    mapping(uint256 => RexCaptainStorage.Vote) public voteIdToVote;

    RexCaptainStorage.Captain[] public captains;

    uint256 public nextVoteId;

    // Contract variables
    ISuperToken public ricAddress;
    ISuperfluid internal host; // Superfluid host contract
    IConstantFlowAgreementV1 internal cfa; // The stored constant flow agreement class address

    uint256 public votingDuration = 14 days;

    uint256 public captainAmountToStake = (10 ** 18) * 10000;

    uint256 public disputeAmountToStake = (10 ** 18) * 1000;

    uint256 public totalStakedAmount = 0;

    // Vote constants
    uint8 public constant VOTE_KIND_NONE = 0;
    uint8 public constant VOTE_KIND_ONBOARDING = 1;
    uint8 public constant VOTE_KIND_RESIGN = 2;
    uint8 public constant VOTE_KIND_DISPUTE = 3;

    // Flow constants
    uint8 public constant FLOW_CREATE = 0;
    uint8 public constant FLOW_TERMINATE = 1;
    uint8 public constant FLOW_UPDATE = 2;

    // Constants
    uint32 private constant SECONDS_IN_YEAR = 60 * 60 * 24 * 365;

    // Roles
    bytes32 public constant CAPTAIN_ROLE = keccak256("CAPTAIN_ROLE");

    constructor(
        ISuperToken ricAddressParam,
        string memory name,
        string memory email,
        ISuperfluid _host,
        IConstantFlowAgreementV1 _cfa,
        string memory _registrationKey
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender); // ask blue guy (if we want this)
        _grantRole(CAPTAIN_ROLE, msg.sender);

        captains.push(RexCaptainStorage.Captain("Genesis", false, address(0), "genisis@genesis", 0, false, 0, 0));
        // Deployer is the first captain (auto-approved): If creator wants the RIC stream,
        // they can call modifyCaptainStake after deployment
        captains.push(RexCaptainStorage.Captain(name, true, msg.sender, email, 0, false, 0, 0));
        addressToCaptain[msg.sender] = captains.length - 1;
        ricAddress = ricAddressParam;
        nextVoteId = 1;

        // SuperApp set up
        host = _host;
        cfa = _cfa;
        // initialize InitData struct, and set equal to cfaV1
        cfaV1 = CFAv1Library.InitData(
            host,
            cfa
        );

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
        RexCaptainStorage.Captain memory captain = _getCaptainMemory(addr);
        require(captain.voteInProgress == false, "A vote is already in progress");
        _;
    }

    modifier voteInProgress(address addr) {
        RexCaptainStorage.Captain memory captain = _getCaptainMemory(addr);
        require(captain.voteInProgress, "No vote in progress");
        _;
    }

    // Internal functions
    /// @dev Validate a captain
    modifier validCaptain(address addr) {
        require(addr != address(0), "Address cannot be 0");
        uint256 captainId = addressToCaptain[addr];
        require(captainId > 0, "Not a valid captain");
        _;
    }

    /// @dev Add a captain to the REXForce
    function _addCaptain(string memory name, string memory email, address addr) internal {
        captains.push(RexCaptainStorage.Captain(name, false, addr, email, 0, false, captainAmountToStake, 0));
        addressToCaptain[addr] = captains.length - 1;
    }

    function _getCaptain(address captainAddress) internal view returns (RexCaptainStorage.Captain storage captain) {
        uint256 captainId = addressToCaptain[captainAddress];
        captain = captains[captainId];
        return captain;
    }

    function _getCaptainMemory(address captainAddress) internal view returns (RexCaptainStorage.Captain memory captain) {
        uint256 captainId = addressToCaptain[captainAddress];
        captain = captains[captainId];
        return captain;
    }

    /// @dev Create a vote for a captain
    function _createVote(address captainAddress, uint8 kind, uint256 time) internal {
        // Create the vote
        RexCaptainStorage.Vote storage vote = voteIdToVote[nextVoteId];
        vote.id = nextVoteId;
        vote.kind = kind;
        vote.proposer = captainAddress;
        vote.start = time;
        vote.againstSum = 0;
        vote.forSum = 0;

        // Set the vote for the captain
        RexCaptainStorage.Captain storage captain = _getCaptain(captainAddress);
        captain.currentVote = nextVoteId;
        captain.voteInProgress = true;

        nextVoteId += 1;
    }

    /// @dev Stop the current vote for a captain
    function _stopVote(address captainAddress) internal {
        RexCaptainStorage.Captain storage captain = _getCaptain(captainAddress);
        captain.voteInProgress = false;
    }

    /// @dev Get the current vote for a captain
    function _getCurrentVote(address captainAddress) internal view returns (RexCaptainStorage.Vote storage vote) {
        RexCaptainStorage.Captain memory captain = _getCaptain(captainAddress);
        return voteIdToVote[captain.currentVote];
    }

    /// @dev Check if a vote has passed. Quorum is required, and more than half of the votes must be 'for'.
    function _isVotePassed(RexCaptainStorage.Vote storage currentVote) internal view returns (bool) {

        // TODO: Double check this, quorum should be 33% fo the captains
        uint256 quorum = captains.length / 3;
        console.log(quorum);

        require(currentVote.forSum + currentVote.againstSum >= quorum, "Not enough votes");

        if (currentVote.forSum > currentVote.againstSum)
            return true;

        return false;
    }

    /// @dev Cast a uint to int96 (for Superfluid purposes).
    function _safeCastToInt96(uint256 _value) internal pure returns (int96) {
        require(_value < 2 ** 96, "int96 overflow");
        return int96(int(_value));
    }

    /// @dev Create, terminate, or update the RIC flow to a captain.
    function _manageCaptainStream(address captainAddress, uint8 action) internal {
        RexCaptainStorage.Captain memory captain = _getCaptainMemory(captainAddress);

        if (action == FLOW_CREATE) { // Create a new flow
            cfaV1.createFlow(captainAddress, ISuperToken(address(ricAddress)), _safeCastToInt96(captain.stakedAmount / SECONDS_IN_YEAR));
        } else if (action == FLOW_TERMINATE) { // Terminate a flow
            cfaV1.deleteFlow(address(this), captainAddress, ricAddress);
        } else if (action == FLOW_UPDATE) { // Update a existing flow
            cfaV1.updateFlow(captainAddress, ricAddress, _safeCastToInt96(captain.stakedAmount / SECONDS_IN_YEAR));
        } else {
            revert("Invalid action");
        }
    }

    // Public and external functions

    /// @notice Modify the voting duration for RexCaptain votes.
	/// @param newDuration Name of the captain
    function modifyVotingDuration(uint256 newDuration) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newDuration > 0, "Duration must be greater than 0");
        emit VotingDurationChanged(votingDuration, newDuration);
        votingDuration = newDuration;
    }

    /// @notice Modify the stake amount required for captains.
	/// Existing captains must call modifyCaptainStake to update their stake and stream.
	/// @param amount New stake amount for captains
    function modifyCaptainAmountToStake(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit CaptainStakeChanged(captainAmountToStake, amount);
        captainAmountToStake = amount;
    }

    /// @notice Modify the stake amount required for dispute.
	/// @param amount New stake amount for dispute
    function modifyDisputeAmount(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit DisputeStakeChanged(disputeAmountToStake, amount);
        disputeAmountToStake = amount;
    }

	/// @notice Apply for captain with given details.
	/// The required stake amount is transferred from the candidate's address.
	/// @param name Name of the captain
	/// @param email Email of the captain
	/// @dev Emits `VotingStarted`
    function applyForCaptain(string memory name, string memory email) external {
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

        emit CaptainApplied(name, email);
        emit VotingStarted(msg.sender, VOTE_KIND_ONBOARDING);
    }

    /// @notice End the captain onboarding vote.
	/// @param captainAddress Address of the captain
	/// @dev Emits `VotingEnded`
    function endCaptainOnboardingVote(address captainAddress)
        external
        validCaptain(captainAddress)
        voteInProgress(captainAddress) {
        RexCaptainStorage.Captain storage captain = _getCaptain(captainAddress);
        RexCaptainStorage.Vote storage currentVote = _getCurrentVote(captainAddress);

        uint256 time = block.timestamp;
        require(currentVote.kind == VOTE_KIND_ONBOARDING, "Invalid vote kind");
        require(currentVote.start + votingDuration < time, "Voting duration not expired");

        bool passed = _isVotePassed(currentVote);

        if (passed) {
            // if vote passed - increase activeCaptains and start RIC stream.
            _grantRole(CAPTAIN_ROLE, captainAddress);
            captain.approved = true;
            _manageCaptainStream(captainAddress, FLOW_CREATE);
        } else {
            // if vote failed - transfer back RIC
            ricAddress.safeTransfer(
                captainAddress,
                captain.stakedAmount // Staked RIC return
            );
            addressToCaptain[captainAddress] = 0;
            totalStakedAmount -= captainAmountToStake;
        }
        _stopVote(captainAddress);

        emit VotingEnded(captainAddress, VOTE_KIND_ONBOARDING, passed);
    }

    /// @notice Start a vote to resign from the captain position.
	/// This starts a vote that must pass for the captain to get their stake back.
    /// @dev Emits `VotingStarted`
    function resignCaptain() external onlyCaptain noVoteInProgress(msg.sender) {

        uint256 time = block.timestamp;
        _createVote(msg.sender, VOTE_KIND_RESIGN, time);

        emit VotingStarted(msg.sender, VOTE_KIND_RESIGN);
    }

    /// @notice End a captain resignation vote.
	/// @param captainAddress Address of the captain
	/// @dev Emits `VotingEnded`
    function endCaptainResignVote(address captainAddress) external onlyCaptain isCaptain(captainAddress) voteInProgress(captainAddress) {
        RexCaptainStorage.Captain storage captain = _getCaptain(captainAddress);
        RexCaptainStorage.Vote storage currentVote = _getCurrentVote(captainAddress);
        uint256 time = block.timestamp;
        require(currentVote.kind == VOTE_KIND_RESIGN, "Invalid vote kind");
        require(currentVote.start + votingDuration < time, "Voting duration not expired");

        bool passed = _isVotePassed(currentVote);

        if (passed) {
            ricAddress.safeTransfer(
                captainAddress,
                captain.stakedAmount
            );

            addressToCaptain[captainAddress] = 0; // If failed and approved != 0 means dishonorable resignation
        }

        totalStakedAmount -= captain.stakedAmount;

        _revokeRole(CAPTAIN_ROLE, captainAddress);
        captain.approved = false;
        _manageCaptainStream(captainAddress, FLOW_TERMINATE);

        _stopVote(captainAddress);

        emit VotingEnded(captainAddress, VOTE_KIND_RESIGN, passed);
    }

    /// @notice Start a vote to dispute a captain.
	/// @param captainAddress Address of the captain
	/// @dev Emits `VotingStarted`
    function disputeCaptain(address captainAddress) external onlyCaptain isCaptain(captainAddress) noVoteInProgress(captainAddress) {
        // Transfer RIC from disputer to contract
        ricAddress.safeTransferFrom(
            msg.sender,
            address(this),
            disputeAmountToStake // 1k RIC transfer
        );

        RexCaptainStorage.Captain storage captain = _getCaptain(captainAddress);
        captain.disputeStakedAmount = disputeAmountToStake;
        uint256 time = block.timestamp;
        _createVote(captainAddress, VOTE_KIND_DISPUTE, time);

        emit VotingStarted(msg.sender, VOTE_KIND_DISPUTE);
    }

    /// @notice End dispute captain vote.
	/// @param captainAddress Address of the captain
	/// @dev Emits `VotingEnded`
    function endCaptainDisputeVote(address captainAddress) external onlyCaptain isCaptain(captainAddress) voteInProgress(captainAddress) {
        RexCaptainStorage.Captain storage captain = _getCaptain(captainAddress);
        RexCaptainStorage.Vote storage currentVote = _getCurrentVote(captainAddress);
        uint256 time = block.timestamp;
        require(currentVote.kind == VOTE_KIND_DISPUTE, "Invalid vote kind");
        require(currentVote.start + votingDuration < time, "Voting duration not expired");

        bool passed = _isVotePassed(currentVote);

        if (passed) {
            // send RIC back to disputer
            ricAddress.safeTransferFrom(
                msg.sender,
                currentVote.proposer,
                captain.disputeStakedAmount
            );

            captain.disputeStakedAmount = 0;
            _revokeRole(CAPTAIN_ROLE, captainAddress);
            captain.approved = false;
            _manageCaptainStream(captainAddress, FLOW_TERMINATE);
        }

        _stopVote(captainAddress);

        emit VotingEnded(captainAddress, VOTE_KIND_DISPUTE, passed);
    }

    /// @notice Cast vote for a vote in progress.
	/// @param captainAddress Address of the captain
	/// @param vote Vote. false: against, true: for
	/// @dev Emits `VoteCast`
    function castVote(address captainAddress, bool vote)
        external
        onlyCaptain
        validCaptain(captainAddress)
        voteInProgress(captainAddress)
    {
        RexCaptainStorage.Vote storage currentVote = _getCurrentVote(captainAddress);
        // TODO: Require vote exsits?
        require(currentVote.voted[msg.sender] == false, "Already voted");

        if (vote) {
            currentVote.forSum += 1;
        } else {
            currentVote.againstSum += 1;
        }

        currentVote.voted[msg.sender] = true;

        emit VoteCast(captainAddress, currentVote.kind, vote);
    }

    /// @notice Modify the stake for a captain and update the stream.
    /// Flow rate is changed according to the new stake amount.
	/// @dev Emits `CaptainUpdatedStake`
    function modifyCaptainStake()
        external
        onlyCaptain
    {
        RexCaptainStorage.Captain storage captain = _getCaptain(msg.sender);

        require(captainAmountToStake != captain.stakedAmount, "No change needed");
        uint256 difference;

        if (captainAmountToStake > captain.stakedAmount) {
            difference = captainAmountToStake - captain.stakedAmount;
            ricAddress.safeTransferFrom(msg.sender, address(this), difference);
            totalStakedAmount += difference;
        } else {
            difference = captain.stakedAmount - captainAmountToStake;
            ricAddress.safeTransfer(msg.sender, difference);
            totalStakedAmount -= difference;
        }

        emit CaptainUpdatedStake(captain.stakedAmount, captainAmountToStake);

        captain.stakedAmount = captainAmountToStake; // TEST: verify that this gets updated when calling function

        (,int96 streamerFlowRate,,) = cfa.getFlow(ISuperToken(address(ricAddress)), address(this), msg.sender);
        if(streamerFlowRate == 0) {
          _manageCaptainStream(msg.sender, FLOW_CREATE);
        } else {
          _manageCaptainStream(msg.sender, FLOW_UPDATE);
        }
    }

    /// @notice Emergency use only: withdraw all funds from contract.
    function emergencyFundsWithdrawal() external onlyRole(DEFAULT_ADMIN_ROLE) {
        ricAddress.safeTransfer(msg.sender, ricAddress.balanceOf(address(this)));
    }

}
