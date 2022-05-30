// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.11;

library RexCaptainStorage {

    struct Vote {
        uint256 id;
        uint8 kind; // The vote kind. See VOTE_KIND constants in RexCaptain
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
        uint currentVote; // Vode id of the current vote
        bool voteInProgress; // Whether a vote is in progress
        uint256 stakedAmount; // Amount of REX staked by the captain
        uint256 disputeStakedAmount; // Amount of REX staked for an ongoing dispute
    }
}