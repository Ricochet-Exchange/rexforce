// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.14;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../tellor/ITellor.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

import { SuperAppBase } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperAppBase.sol";
import { IConstantFlowAgreementV1 } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";
import { ISuperfluid, ISuperToken, ISuperApp, ISuperAgreement, SuperAppDefinitions } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

import { IREXCaptain } from "../captain/IRexCaptain.sol";
import { RexBountyStorage } from "./RexBountyStorage.sol";

contract REXBounty is Ownable, SuperAppBase, ERC721URIStorage {

    using SafeERC20 for IERC20;
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    RexBountyStorage.Bounty[] public bounties;

    // Events
    event BountyCreated(uint256 bountyId, address creator, string ipfsHash);
    event BountyApproved(uint256 bountyId, address approver);
    event BountyPayoutApproved(uint256 bountyId, address payee, bool payoutComplete);
    event BountyPayoutReset(uint256 bountyId, address captain);

    // Contract variables
    IERC20 public ricAddress;
    IREXCaptain public captainHost;
    ISuperfluid internal host; // Superfluid host contract
    IConstantFlowAgreementV1 internal cfa; // The stored constant flow agreement class address
    ITellor internal oracle; // Address of deployed simple oracle for input/output tokens

    constructor(
        IREXCaptain _captainHost,
        IERC20 ricAddressParam,
        ITellor _tellor,
        ISuperfluid _host,
        IConstantFlowAgreementV1 _cfa,
        string memory _registrationKey
    ) ERC721("GameItem", "ITM") {

        ricAddress = ricAddressParam;
        captainHost = _captainHost;
        oracle = _tellor;

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

    modifier onlyApprovedBounty(uint256 bountyId) {
        require(bounties[bountyId].approver != address(0), "Bounty not approved");
        _;
    }

    modifier onlyCaptain() {
        captainHost.isCaptain(msg.sender);
        _;
    }

    // Adds RIC to contract
    // Be generous and donate a lot of RIC to the contract
    function fundContractWithRIC(uint256 amount) public {
        ricAddress.safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
    }

    function createNFT(address payee, string memory ipfsHashURI)
        private
        returns (uint256)
    {
        uint256 newItemId = _tokenIds.current();
        _mint(payee, newItemId);
        _setTokenURI(newItemId, ipfsHashURI);

        _tokenIds.increment();
        return newItemId;
    }

    function createBounty(uint256 bountyAmount, string memory ipfsHashURI) public onlyCaptain {
        uint256 time = block.timestamp;
        uint256 bountyId = bounties.length;
        RexBountyStorage.Bounty memory bounty = RexBountyStorage.Bounty(bountyId, msg.sender, address(0), bountyAmount, time, address(0), false, ipfsHashURI, new address[](0));
        bounties.push(bounty);

        emit BountyCreated(bountyId, msg.sender, ipfsHashURI);
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
        require(captainHost.isCaptainDisputed(msg.sender) == false, "Disputed captain");

        RexBountyStorage.Bounty storage bounty = bounties[bountyId];

        require(bounty.payoutComplete == false, "Payout already completed");
        require(bounty.payee == address(0) || bounty.payee == payee, "Payee does not match");
        require(bounty.approvals.length == 0 || bounty.approvals[0] != msg.sender, "Already approved");

        // If we already have 1 approval, we can pay out and mint bountyNFT
        if (bounty.approvals.length == 1) {
            uint256 ricValue = getTokenPrice();
            // TODO: Check decimals for ricValue and fix
            ricAddress.safeTransfer(payee, ((bounty.amount * (10 ** 6)) / ricValue) * 10 ** 18);

            createNFT(payee, bounty.ipfsHashURI);
            bounty.payoutComplete = true;
        }

        bounty.approvals.push(msg.sender);
        bounty.payee = payee;

        emit BountyPayoutApproved(bountyId, payee, bounty.payoutComplete);
    }

    function resetBountyPayee(uint256 bountyId) public onlyCaptain onlyApprovedBounty(bountyId) {
        require(bountyId < bounties.length, "Bounty does not exist");
        RexBountyStorage.Bounty storage bounty = bounties[bountyId];

        require(bounty.payoutComplete == false, "Payout already completed");

        bounty.payee = address(0);
        delete bounty.approvals;

        emit BountyPayoutReset(bountyId, msg.sender);
    }

    function getTokenPrice() public view returns(uint256) {
        (
            bool _ifRetrieve,
            uint256 _value,
            uint256 _timestampRetrieved
        ) = getCurrentValue(77); // richochet: 77

        require(_ifRetrieve, "!getCurrentValue");
        require(_timestampRetrieved >= block.timestamp - 3600, "!currentValue");

        return _value;
    }

    function getCurrentValue(uint256 _requestId)
        public
        view
        returns (
            bool _ifRetrieve,
            uint256 _value,
            uint256 _timestampRetrieved
        )
    {
        uint256 _count = oracle.getNewValueCountbyRequestId(_requestId);
        _timestampRetrieved = oracle.getTimestampbyRequestIDandIndex(
            _requestId,
            _count - 1
        );
        _value = oracle.retrieveData(_requestId, _timestampRetrieved);

        if (_value > 0) return (true, _value, _timestampRetrieved);
        return (false, 0, _timestampRetrieved);
    }
}
