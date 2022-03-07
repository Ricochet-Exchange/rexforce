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


## Protocol Specifications

### Structures
* `Member` - used to track information about team members
  * `address addr` - address of the team member
  * `uint role` - 0 for no role, 1 for captain, 2 for specialist
  * `bool active` - 1 if active and in good standing, 0 otherwise
  * `uint dischargedAt` - the time a discharge was started
  * `uint marks` - a counter used to track +1 and -1 marks from the Captain upon discharge

* `Captain`
* `Specialist`
* `Milestone`
* `Bounty`

### Parameters
`mapping (address => Member)`

### Methods

#### `startJoin(uint role)`
* Parameters
  * `uint role` - 1 for captian, 2 for speicalist
* Pre-conditions
  * Approved the contract to spend 10K/1K for captain/specialist bond
  * Have 10K/1K tokens depending on which role your joining under

#### `finishJoin(address member)`
* Parameters
  * `address member` the address of the team member to end the join process
* Pre-conditions
  *


#### `mark(address member, bool positively)`
* Parameters
  * `address member` - the address of the team member to mark
  * `bool positively` - true if this is a positive mark, false if its a negative mark
* Pre-conditions
  * The team member's dischargedAt is less than two weeks old (actively being discharge)  

#### `startDischarge(address member)`
* Parameters
  * `address member` - the address of the team member to discharge
* Pre-conditions
  * `member` is a valid team member
  * `dischargedAt` is not set
* Post-conditions
  * `dischargedAt` is set to the current time

#### `finishDischarge(address member)`
* Parameters
  * `address member` - the address of the team member to discharge
* Pre-conditions
  * `dischargedAt` is more than 2 weeks ago
* Post-conditions
  * If `marks` > 0, then the team members 10k token stake is returned
  * Member is marked as inactive (0)
  * Member role is set to 0
