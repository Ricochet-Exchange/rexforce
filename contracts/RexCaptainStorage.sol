// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.11;

library RexCaptainStorage {

    // Events
    event CaptainApplied(string name, string email);
    event VotingStarted(address addr, uint8 kind, uint256 start);
    event VotingEnded(address addr, uint8 kind, bool approved, uint256 end);
    // TODO use single event and have bool for honourable
    event HonoarablyResignedCaptain(string name, string email, address addr);
    event DishonoarablyResignedCaptain(string name, string email, address addr);
    event VoteCast(address captainAddress, uint8 kind, bool vote);

    // Roles
    bytes32 public constant CAPTAIN_ROLE = keccak256("CAPTAIN_ROLE");

    // Vote constants
    uint8 public constant VOTE_KIND_NONE = 0;
    uint8 public constant VOTE_KIND_ONBOARDING = 1;
    uint8 public constant VOTE_KIND_RESIGN = 2;
    uint8 public constant VOTE_KIND_DISPUTE = 3;

    struct VoterTally {
        int voteId;
        mapping(address => bool) voted;
    }

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
        uint256 stakedAmount; // Amount of REX staked by the captain
    }
}