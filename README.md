# REX Force
Decentralized Autonomous Workforce Management Contracts

## Overview
REX Force is an workforce management contract created by Ricochet Exchange (REX) DAO. The purpose of the contract is to:
1. Empower designated personal to exercise lawful authority
2. Manage a decentralized workforce
3. Create an incentive compatible and autonomous compensation program

## Contract Architecture

### Roles
REX Force has two formal roles:

* **Captains** - REX Force leaders that have the authority to allocate funding to milestones and bounties
* **Specialists** - REX Force contributors that work on milestones and bounties created by Captains

Specialists are onboarded by a Captain so each Specialist is associated with the Captain that onboarded them

### Milestones and Bounties
* REX Force team members are responsible for creating work for themselves (autonomously)
* Captains create _milestones_ and add _bounties_ within those milestones
* Specialists can create bounties
* Captains allocate funding to milestones and bounties
* Allocated funding is escrowed and paid out after the approval of another Captain
* Milestones must map to a Github Milestone
* Bounties must map to a Github Issue

### Bonding
Captians and Specialists put down a security deposit in exchange for a formal role within REX DAO. The bonds are:
* Captains - 10K RIC
* Specialists - 1K RIC

### Base Pay
Captains and Specialist base pay is set to 100% APY on their stake. After depositing their bond, REX Force opens a stream to the team member. The stream rates for base pay are:
* Captains - 10K / year
* Specialists - 1K / year

### Performance Pay
* Captains and Specialists work on completing bounties and milestones to earn income above the base pay
* Each bounty and milestone is allocated funding in USDC
* Two Captains can approve a milestone/bounty payout

### Discharging Team Members
* Anyone two Captains can request a team member be discharged
* Anyone can request to discharge themselves
* There is a 2 week voting window once a discharge request is made
* During the vote, Captains can vote on whether the discharge should be honorable or dishonerable
* The discharged team members stake is returned to them if the Captains vote for an honerable discharge
* The discharged team members stake is sent to the DAO if the Captains vote for a dishonerable discharge

### Business Processes
* Captains:
  * Onboarding a Captain
  * Discharging a Captain
  * Creating Milestones/Bounties
  * Approving payouts for Milestones/Bounties

* Specialists:
  * Onboarding a Specialist
  * Discharging a Specialist
  * Creating bounties

### RIC Funding for REX Force
* The REX Force contract will be funded with a stream of RIC tokens from the REX DAO Treasury
* RIC will accumulate in the contract
* Accumulated RIC in the contract will serve as the budget for base pay and milestone/bounty payouts
