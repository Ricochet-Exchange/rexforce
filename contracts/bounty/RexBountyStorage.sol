// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.14;

library RexBountyStorage {

    struct Bounty {
        uint256 id; // ID of the bounty - (NFT reference)
        address creator; // Address of the creator of the bounty
        address approver; // Address of the approver of the bounty
        uint256 amount; // Amount of USD amount to be awarded - no decimals
        uint256 start; // Start time of the bounty
        address payee; // Address of the payee of the bounty
        bool payoutComplete; // Is payout complete?
        string ipfsHashURI; // Description of the bounty
        address[] approvals; // Number of votes for the bounty
    }

}
