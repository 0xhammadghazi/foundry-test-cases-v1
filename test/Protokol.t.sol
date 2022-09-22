pragma solidity 0.8.4;

import "forge-std/Test.sol";

import {protoKol as MockProtokol, iProtoKol} from "../src/protoKol.sol";
import {MockPresale} from "./Mock/MockPresale.sol";
import {MockUSDT} from "./Mock/MockUSDT.sol";
import {MockKol} from "./Mock/MockKol.sol";

import "forge-std/Vm.sol";
import "forge-std/console.sol";

contract ProtokolTest is Test {
    MockPresale private presale;
    MockUSDT private usdt;
    MockKol private kol;
    MockProtokol private protokol;

    iProtoKol.CampaignDetails private campaignDetails;
    iProtoKol.VestingDetails private vestingDetails;
    iProtoKol.Signature private signature;

    // Admin private key
    uint256 private admin_pk = 0x99;

    // Public address associated with admin's private key
    address private admin = vm.addr(0x99);

    // Staking contract address
    address private staking = vm.addr(0x999);

    // Campaign owners
    address private owner1 = vm.addr(1);
    address private owner2 = vm.addr(2);

    // Investors
    address private investor1 = vm.addr(3);
    address private investor2 = vm.addr(4);
    address private investor3 = vm.addr(5);

    address private USDT;
    uint256 private campaignStartDate = block.timestamp; // Storing campaign start date so we don't get invalid sig error when skipping time in a test case
    uint256 private tgeDate = campaignStartDate + 25 days;

    function setUp() external {
        vm.startPrank(admin);

        // Creating contract instances
        presale = new MockPresale();
        usdt = new MockUSDT();
        kol = new MockKol();
        protokol = new MockProtokol(
            admin, // admin of protokol contract
            address(kol),
            address(usdt),
            staking, // staking contract
            address(0),
            address(0)
        );

        USDT = address(usdt);

        // Transferring USDT to investors
        usdt.transfer(investor1, 5000e6); // 5k
        usdt.transfer(investor2, 5000e6); // 5k
        usdt.transfer(investor3, 5000e6); // 5k

        // Transferring presale and usdt to campaign owner
        presale.transfer(owner1, 5000e18); // 5k
        usdt.transfer(owner1, 5000e6); // 5k

        // Investors giving approval of USDT to protokol contract

        changePrank(investor1);
        usdt.approve(address(protokol), usdt.balanceOf(investor1));

        changePrank(investor2);
        usdt.approve(address(protokol), usdt.balanceOf(investor2));

        changePrank(investor3);
        usdt.approve(address(protokol), usdt.balanceOf(investor3));

        // Labelling addresses
        vm.label(investor1, "Alice");
        vm.label(investor2, "Bob");
        vm.label(investor3, "Zack");
        vm.label(admin, "Admin");
        vm.label(owner1, "John");
        vm.label(owner2, "Jack");
    }

    function test_ClaimFullShare_Blacklist_ClaimAgain_FullTGE() external {
        uint256 campaignId = 0;
        uint16 tgePercentage = 10000; // 100%
        uint256 progress = 10000; // 100%
        uint256 investmentAmount = 500 ether; // 49.75% share (after transaction fee)

        vestingDetails = getNonVestingDetails();

        changePrank(owner1);

        createCampaign(tgePercentage, vestingDetails);

        // Approving presale tokens
        presale.approve(address(protokol), presale.balanceOf(owner1));

        // Generating TGE
        protokol.generateTGE(0);

        // INVESTOR

        (uint8 v, bytes32 r, bytes32 s) = signMessage(
            getInvestMessageHash(investor1, investmentAmount)
        );
        signature = iProtoKol.Signature({r: r, s: s, v: v});

        changePrank(investor1);

        protokol.registerKOL("Alice");
        protokol.investInCampaign(
            campaignId,
            investmentAmount,
            USDT,
            signature
        );

        // Claiming
        (v, r, s) = signMessage(
            getClaimPresaleMessageHash(investor1, progress)
        );
        signature = iProtoKol.Signature({r: r, s: s, v: v});

        skip(50 days); //Skipping 50 days

        protokol.claimPreSaleTokens(campaignId, progress, r, s, v);

        assertEq(presale.balanceOf(address(investor1)), 472.625 ether);

        changePrank(admin);
        protokol.blackListKOL(campaignId, investor1, uint16(progress));

        changePrank(investor1);
        protokol.claimPreSaleTokens(campaignId, progress, r, s, v);

        // Shouldn't get any more tokens cause already claimed 100% share
        assertEq(presale.balanceOf(address(investor1)), 472.625 ether);
    }

    // TODO: Make this test case pass
    function testInvestAfterTimePassedAndInvestorPullsOut() external {
        // Scenario: Vesting campaign -> full investment raised -> Time passed no vesting deposit ->
        // one investor pulls out -> new investors comes in cause end date not expired ->
        // new investor will get share from tgeAmount which is wrong

        uint256 campaignId = 0;
        uint256 progress = 10000;
        uint16 tgePercentage = 5000; // 50%
        uint256 investmentAmount = 500 ether; // 49.75% share (after transaction fee)

        vestingDetails = getVestingDetails();

        changePrank(owner1);

        // Creating campaign
        createCampaign(tgePercentage, vestingDetails);

        // Approving presale tokens
        presale.approve(address(protokol), presale.balanceOf(owner1));

        // Generating TGE
        protokol.generateTGE(0);

        // INVESTOR 1

        (uint8 v, bytes32 r, bytes32 s) = signMessage(
            getInvestMessageHash(investor1, investmentAmount)
        );
        signature = iProtoKol.Signature({r: r, s: s, v: v});

        changePrank(investor1);

        protokol.registerKOL("Alice");
        protokol.investInCampaign(
            campaignId,
            investmentAmount,
            USDT,
            signature
        );

        // INVESTOR 2

        // Overwriting variables
        (v, r, s) = signMessage(
            getInvestMessageHash(investor2, investmentAmount)
        );
        signature = iProtoKol.Signature({r: r, s: s, v: v});

        changePrank(investor2);

        protokol.registerKOL("Bob");
        protokol.investInCampaign(
            campaignId,
            investmentAmount,
            USDT,
            signature
        );

        // Claiming
        (v, r, s) = signMessage(
            getClaimPresaleMessageHash(investor2, progress)
        );
        signature = iProtoKol.Signature({r: r, s: s, v: v});

        skip(50 days); //Skipping 50 days

        protokol.claimPreSaleTokens(campaignId, progress, r, s, v);

        // INVESTOR 3

        uint256 newInvestAmount = 250 ether;
        (v, r, s) = signMessage(
            getInvestMessageHash(investor3, newInvestAmount)
        );
        signature = iProtoKol.Signature({r: r, s: s, v: v});

        changePrank(investor3);

        protokol.registerKOL("Zack");
        protokol.investInCampaign(campaignId, newInvestAmount, USDT, signature);

        (v, r, s) = signMessage(
            getClaimPresaleMessageHash(investor3, progress)
        );
        signature = iProtoKol.Signature({r: r, s: s, v: v});

        // Claiming
        protokol.claimPreSaleTokens(campaignId, progress, r, s, v);

        // Should be equal to 0 but isn't cause no cycle amount was deposited
        assertEq(presale.balanceOf(address(investor3)), 0);
    }

    function test_ClaimHalfProgress_Blacklist_ClaimQtrIncProgress_FullTGE()
        external
    {
        uint256 campaignId = 0;
        uint16 tgePercentage = 10000; // 100%
        uint256 progressBeforeBlacklist = 5000; // 50%
        uint256 progressAfterBlacklist = 7500; // 75%
        uint256 investmentAmount = 500 ether; // 49.75% share (after transaction fee)

        vestingDetails = getNonVestingDetails();

        changePrank(owner1);

        createCampaign(tgePercentage, vestingDetails);

        // Approving presale tokens
        presale.approve(address(protokol), presale.balanceOf(owner1));

        // Generating TGE
        protokol.generateTGE(0);

        // INVESTOR

        (uint8 v, bytes32 r, bytes32 s) = signMessage(
            getInvestMessageHash(investor1, investmentAmount)
        );
        signature = iProtoKol.Signature({r: r, s: s, v: v});

        changePrank(investor1);

        protokol.registerKOL("Alice");
        protokol.investInCampaign(
            campaignId,
            investmentAmount,
            USDT,
            signature
        );

        // Claiming
        (v, r, s) = signMessage(
            getClaimPresaleMessageHash(investor1, progressBeforeBlacklist)
        );
        signature = iProtoKol.Signature({r: r, s: s, v: v});

        skip(50 days); //Skipping 50 days

        protokol.claimPreSaleTokens(
            campaignId,
            progressBeforeBlacklist,
            r,
            s,
            v
        );

        assertEq(presale.balanceOf(address(investor1)), 236.3125 ether); // 236.3125 (cause 50% progress)

        // Blacklisting
        changePrank(admin);
        protokol.blackListKOL(
            campaignId,
            investor1,
            uint16(progressAfterBlacklist)
        );

        // Claiming
        (v, r, s) = signMessage(
            getClaimPresaleMessageHash(investor1, progressAfterBlacklist)
        );
        signature = iProtoKol.Signature({r: r, s: s, v: v});

        changePrank(investor1);
        protokol.claimPreSaleTokens(
            campaignId,
            progressAfterBlacklist,
            r,
            s,
            v
        );

        assertEq(presale.balanceOf(address(investor1)), 354.46875 ether); // 354.46875 (cause 75% progress)
        assertEq(usdt.balanceOf(address(investor1)), 4624.375e6); // got 124.375 usdt back - 25% of invested amount (497.5)
    }

    function test_ClaimHalfProgress_BlacklistBeforeCycleDeposit_ClaimAgain()
        external
    {
        // Scenario: Vesting campaign -> Investor with 49.75% share claims presale at 50% progress ->
        // Got blacklisted before cycle deposit -> Claims presale after 1 cycle deposited
        uint256 campaignId = 0;
        uint256 progress = 5000; //50%
        uint16 tgePercentage = 5000; // 50%
        uint256 investmentAmount = 500 ether; // 49.75% share (after transaction fee)

        vestingDetails = getVestingDetails();

        changePrank(owner1);

        // Creating campaign
        createCampaign(tgePercentage, vestingDetails);

        // Approving presale tokens
        presale.approve(address(protokol), presale.balanceOf(owner1));

        // Generating TGE
        protokol.generateTGE(0);

        // INVESTOR

        (uint8 v, bytes32 r, bytes32 s) = signMessage(
            getInvestMessageHash(investor1, investmentAmount)
        );
        signature = iProtoKol.Signature({r: r, s: s, v: v});

        changePrank(investor1);

        protokol.registerKOL("Alice");
        protokol.investInCampaign(
            campaignId,
            investmentAmount,
            USDT,
            signature
        );

        // Claiming
        (v, r, s) = signMessage(
            getClaimPresaleMessageHash(investor1, progress)
        );
        signature = iProtoKol.Signature({r: r, s: s, v: v});

        skip(tgeDate); //Skipping till tge date

        protokol.claimPreSaleTokens(campaignId, progress, r, s, v);
        // 236.3125 (50% of my total eligible reward)
        assertEq(presale.balanceOf(address(investor1)), 236.3125 ether);

        changePrank(admin);

        // Blacklisting before cycle deposit
        protokol.blackListKOL(campaignId, investor1, uint16(progress));

        changePrank(owner1);
        uint256 vestingCycleAmount = 237.5 ether;
        protokol.depositPreSaleTokens(campaignId, vestingCycleAmount);

        // Claiming again
        (v, r, s) = signMessage(
            getClaimPresaleMessageHash(investor1, progress)
        );
        signature = iProtoKol.Signature({r: r, s: s, v: v});

        changePrank(investor1);
        protokol.claimPreSaleTokens(campaignId, progress, r, s, v);

        // Shouldn't change cause I got blacklisted at 50% progress and before cycle deposit
        assertEq(presale.balanceOf(address(investor1)), 236.3125 ether);

        // 248.75 (50% investment back in usdt);
        assertEq(usdt.balanceOf(address(investor1)), 4748.75e6);
    }

    function test_ClaimHalfProgress_BlacklistAtQtrIncProgress_BeforeCycleDeposit_ClaimAgain()
        external
    {
        // Scenario: Vesting campaign -> Investor with 49.75% share claims presale at 50% progress ->
        // Got blacklisted when progress was 75% ->  Cycle deposited after investor got blacklisted ->
        // Claims presale

        uint256 campaignId = 0;
        uint256 progressBeforeBlacklist = 5000; //50%
        uint256 progressAfterBlacklist = 7500; // 75%
        uint16 tgePercentage = 5000; // 50%
        uint256 investmentAmount = 500 ether; // 49.75% share (after transaction fee)

        vestingDetails = getVestingDetails();

        changePrank(owner1);

        // Creating campaign
        createCampaign(tgePercentage, vestingDetails);

        // Approving presale tokens
        presale.approve(address(protokol), presale.balanceOf(owner1));

        // Generating TGE
        protokol.generateTGE(0);

        // INVESTOR

        (uint8 v, bytes32 r, bytes32 s) = signMessage(
            getInvestMessageHash(investor1, investmentAmount)
        );
        signature = iProtoKol.Signature({r: r, s: s, v: v});

        changePrank(investor1);

        protokol.registerKOL("Alice");
        protokol.investInCampaign(
            campaignId,
            investmentAmount,
            USDT,
            signature
        );

        // Claiming
        (v, r, s) = signMessage(
            getClaimPresaleMessageHash(investor1, progressBeforeBlacklist)
        );
        signature = iProtoKol.Signature({r: r, s: s, v: v});

        skip(tgeDate); //Skipping till tge date

        protokol.claimPreSaleTokens(
            campaignId,
            progressBeforeBlacklist,
            r,
            s,
            v
        );
        // 236.3125 (50% of my total eligible reward)
        assertEq(presale.balanceOf(address(investor1)), 236.3125 ether);

        changePrank(admin);

        // Blacklisting before cycle deposit
        protokol.blackListKOL(
            campaignId,
            investor1,
            uint16(progressAfterBlacklist)
        );

        changePrank(owner1);
        uint256 vestingCycleAmount = 237.5 ether;
        protokol.depositPreSaleTokens(campaignId, vestingCycleAmount);

        // Claiming again
        (v, r, s) = signMessage(
            getClaimPresaleMessageHash(investor1, progressAfterBlacklist)
        );
        signature = iProtoKol.Signature({r: r, s: s, v: v});

        changePrank(investor1);
        protokol.claimPreSaleTokens(
            campaignId,
            progressAfterBlacklist,
            r,
            s,
            v
        );

        // Balance didn't change even though my eligible reward according to my progress was increased
        // but contract didnt have enough funds because I was blacklisted with just tge deposit
        // and my tge share was already given to my in last claim txn
        assertEq(presale.balanceOf(address(investor1)), 236.3125 ether);

        // 248.75 (50% investment back in usdt);
        assertEq(usdt.balanceOf(address(investor1)), 4748.75e6);
    }

    function test_Claim_CycDep_ClaimIncProg_TimePass_IncProgressClaim()
        external
    {
        // Scenario: Vesting campaign -> Investor with 49.75% share claims presale at 50% progress ->
        // One Cycle deposited -> Claims again after doing 75% progress ->  Time passed ->
        // Claims presale after doing 90% progress

        uint256 campaignId = 0;
        uint256 progressFirstClaim = 5000; //50%
        uint256 progressSecondClaim = 7500; // 75%
        uint256 progressThirdClaim = 9000; // 90%

        uint16 tgePercentage = 5000; // 50%
        uint256 investmentAmount = 500 ether; // 49.75% share (after transaction fee)

        vestingDetails = getVestingDetails();

        changePrank(owner1);

        // Creating campaign
        createCampaign(tgePercentage, vestingDetails);

        // Approving presale tokens
        presale.approve(address(protokol), presale.balanceOf(owner1));

        // Generating TGE
        protokol.generateTGE(0);

        // INVESTOR

        (uint8 v, bytes32 r, bytes32 s) = signMessage(
            getInvestMessageHash(investor1, investmentAmount)
        );
        signature = iProtoKol.Signature({r: r, s: s, v: v});

        changePrank(investor1);

        protokol.registerKOL("Alice");
        protokol.investInCampaign(
            campaignId,
            investmentAmount,
            USDT,
            signature
        );

        // Claiming
        (v, r, s) = signMessage(
            getClaimPresaleMessageHash(investor1, progressFirstClaim)
        );
        signature = iProtoKol.Signature({r: r, s: s, v: v});

        skip(tgeDate); //Skipping till tge date

        protokol.claimPreSaleTokens(campaignId, progressFirstClaim, r, s, v);

        // 236.3125 (50% of my total eligible reward)
        assertEq(presale.balanceOf(address(investor1)), 236.3125 ether);

        // Depositing one cycle
        changePrank(owner1);
        uint256 vestingCycleAmount = 237.5 ether;
        protokol.depositPreSaleTokens(campaignId, vestingCycleAmount);

        // Claiming again
        (v, r, s) = signMessage(
            getClaimPresaleMessageHash(investor1, progressSecondClaim)
        );
        signature = iProtoKol.Signature({r: r, s: s, v: v});

        // Adding 2 more days in current timestamp so when we call claim presale one cycle duration is expired
        skip(2 days);

        changePrank(investor1);
        protokol.claimPreSaleTokens(campaignId, progressSecondClaim, r, s, v);

        // 354.46875 (75% of total eligible reward)
        assertEq(presale.balanceOf(address(investor1)), 354.46875 ether);

        skip(tgeDate + 10 days);

        // Claiming again
        (v, r, s) = signMessage(
            getClaimPresaleMessageHash(investor1, progressThirdClaim)
        );
        signature = iProtoKol.Signature({r: r, s: s, v: v});

        changePrank(investor1);
        protokol.claimPreSaleTokens(campaignId, progressThirdClaim, r, s, v);

        // Balance didn't change even though my eligible reward according to my progress was increased
        // but contract didn't have enough funds because I was already rewarded with my presale share of
        // tge and one deposited cycle in my last claim txn
        assertEq(presale.balanceOf(address(investor1)), 354.46875 ether); // 354.46875 (75% of total eligible reward)

        // 124.375 (25% investment back in usdt);
        assertEq(usdt.balanceOf(address(investor1)), 4624375000);
    }

    function test_OneCycleDeposited_BothInvestorsClaim() external {
        // Scenario: Vesting campaign -> 2x investors invested 0.4975% each -> One cycle deposited ->
        // Both investors claim one after the other (both should game same reward) and
        // contract should have 0.5% deposited presale tokens left after both claims

        uint256 campaignId = 0;
        uint256 progress = 10000;
        uint16 tgePercentage = 5000; // 50%
        uint256 investmentAmount = 500 ether; // 49.75% share (after transaction fee)

        vestingDetails = getVestingDetails();

        changePrank(owner1);

        // Creating campaign
        createCampaign(tgePercentage, vestingDetails);

        // Approving presale tokens
        presale.approve(address(protokol), presale.balanceOf(owner1));

        // Generating TGE
        protokol.generateTGE(0);

        // Depositing one cycle
        uint256 vestingCycleAmount = 237.5 ether;
        protokol.depositPreSaleTokens(campaignId, vestingCycleAmount);

        // Skipping time so that first cycle duration is expired when claiming
        skip(tgeDate + 2 days);

        // INVESTOR 1

        (uint8 v, bytes32 r, bytes32 s) = signMessage(
            getInvestMessageHash(investor1, investmentAmount)
        );
        signature = iProtoKol.Signature({r: r, s: s, v: v});

        changePrank(investor1);

        protokol.registerKOL("Alice");
        protokol.investInCampaign(
            campaignId,
            investmentAmount,
            USDT,
            signature
        );

        // Claiming
        (v, r, s) = signMessage(
            getClaimPresaleMessageHash(investor1, progress)
        );
        signature = iProtoKol.Signature({r: r, s: s, v: v});

        protokol.claimPreSaleTokens(campaignId, progress, r, s, v);

        // INVESTOR 2

        // Overwriting variables
        (v, r, s) = signMessage(
            getInvestMessageHash(investor2, investmentAmount)
        );
        signature = iProtoKol.Signature({r: r, s: s, v: v});

        changePrank(investor2);

        protokol.registerKOL("Bob");
        protokol.investInCampaign(
            campaignId,
            investmentAmount,
            USDT,
            signature
        );

        // Claiming
        (v, r, s) = signMessage(
            getClaimPresaleMessageHash(investor2, progress)
        );
        signature = iProtoKol.Signature({r: r, s: s, v: v});

        protokol.claimPreSaleTokens(campaignId, progress, r, s, v);

        // Although both investors were eligible to receive 472.625 tokens but contract could
        // only pay 354.468785 tokens as contract has received presale tokens of one cycle
        assertEq(presale.balanceOf(address(investor1)), 354.46875 ether); // 354.46875
        assertEq(presale.balanceOf(address(investor2)), 354.46875 ether); // 354.46875

        // Total investment raised was 99.5% so contract should have 0.5% presale balance left after both claims
        assertEq(presale.balanceOf(address(protokol)), 3.5625 ether); // 3.5625
    }

    function testCannot_ClaimAfterInvestingAfterTimepassedIfFirstInvestorGetsAllTgeAmount()
        external
    {
        // Scenario: Investor invests 100% -> Claims back investment after time pass with no cycle deposit ->
        // 1/2 Cycle deposited -> New investor invests remaining investment ->
        // Tries to claim his vesting cycle share -> Underflow because contract does not have enough presale tokens
        // because when contract is calculating reward of second investor, it also calculate his share from
        // deposited tgeAmount even though all the tgeAmount has already been given to the first investor and now
        // contract should only give the new investor his share from deposited vesting cycle

        uint256 campaignId = 0;
        uint256 progress = 10000; // 100%
        uint16 tgePercentage = 5000; // 50%
        uint256 investmentAmount = 1000 ether; // almost 99.5% share (after transaction fee)

        vestingDetails = getVestingDetails();

        changePrank(owner1);

        // Creating campaign
        createCampaign(tgePercentage, vestingDetails);

        // Approving presale tokens
        presale.approve(address(protokol), presale.balanceOf(owner1));

        // Generating TGE
        protokol.generateTGE(0);

        // INVESTOR 1

        (uint8 v, bytes32 r, bytes32 s) = signMessage(
            getInvestMessageHash(investor1, investmentAmount)
        );
        signature = iProtoKol.Signature({r: r, s: s, v: v});

        changePrank(investor1);

        protokol.registerKOL("Alice");
        protokol.investInCampaign(
            campaignId,
            investmentAmount,
            USDT,
            signature
        );

        // Claiming
        (v, r, s) = signMessage(
            getClaimPresaleMessageHash(investor1, progress)
        );
        signature = iProtoKol.Signature({r: r, s: s, v: v});

        skip(50 days); //Skipping 50 days

        protokol.claimPreSaleTokens(campaignId, progress, r, s, v);

        // Depositing one cycle reward
        uint256 vestingCycleAmount = 237.5 ether;
        changePrank(owner1);
        protokol.depositPreSaleTokens(campaignId, vestingCycleAmount);

        // INVESTOR 2

        uint256 newInvestAmount = 500 ether;
        (v, r, s) = signMessage(
            getInvestMessageHash(investor2, newInvestAmount)
        );
        signature = iProtoKol.Signature({r: r, s: s, v: v});

        changePrank(investor2);

        protokol.registerKOL("Bob");
        protokol.investInCampaign(campaignId, newInvestAmount, USDT, signature);

        (v, r, s) = signMessage(
            getClaimPresaleMessageHash(investor2, progress)
        );
        signature = iProtoKol.Signature({r: r, s: s, v: v});

        vm.expectRevert(stdError.arithmeticError);

        // Claiming
        protokol.claimPreSaleTokens(campaignId, progress, r, s, v);
    }

    function test_InvestInUsdtCampaign_GotBlacklisted_NewInvestorInvestsRemaining()
        external
    {
        // Scenario: Invest 100% in a USDT campaign ->
        // Investor got blacklised when progress is 50% ->
        // New investor invest's remaining 50% investment -> Old investor claims token
        // New investor claims token after doing 50% progress

        uint256 campaignId = 0;
        uint16 tgePercentage = 10000; // 100%
        uint256 progress = 5000; // 50%
        uint256 investmentAmount = 1000 ether; // 100% share (no txn fee cause USDT campaign)

        vestingDetails = getNonVestingDetails();

        changePrank(owner1);

        createCampaignUSDT(tgePercentage, vestingDetails);

        // Approving presale tokens (which is usdt)
        usdt.approve(address(protokol), usdt.balanceOf(owner1));

        // Generating TGE
        protokol.generateTGE(0);

        changePrank(investor1);

        // INVESTOR

        (uint8 v, bytes32 r, bytes32 s) = signMessage(
            getInvestMessageHash(investor1, investmentAmount)
        );
        signature = iProtoKol.Signature({r: r, s: s, v: v});

        protokol.registerKOL("Alice");
        protokol.investInCampaign(
            campaignId,
            investmentAmount,
            USDT,
            signature
        );

        skip(50 days); //Skipping 50 days

        // Blacklisting first investor
        changePrank(admin);
        protokol.blackListKOL(campaignId, investor1, uint16(progress));

        // INVESTOR 2

        uint256 newInvestAmount = 500 ether;
        (v, r, s) = signMessage(
            getInvestMessageHash(investor2, newInvestAmount)
        );
        signature = iProtoKol.Signature({r: r, s: s, v: v});

        changePrank(investor2);

        protokol.registerKOL("Bob");

        // Second investor investing
        protokol.investInCampaign(campaignId, newInvestAmount, USDT, signature);

        // First investor claiming
        (v, r, s) = signMessage(
            getClaimPresaleMessageHash(investor1, progress)
        );
        signature = iProtoKol.Signature({r: r, s: s, v: v});

        changePrank(investor1);
        protokol.claimPreSaleTokens(campaignId, progress, r, s, v);

        // Each investor starts with the balance of 5k usdt, after claiming investor should get
        // 475 more tokens because his progress was 50% when he got blacklisted and
        // his eligible reward was 950 tokens
        assertEq(usdt.balanceOf(address(investor1)), 5475e6);

        // Second investor claiming
        (v, r, s) = signMessage(
            getClaimPresaleMessageHash(investor2, progress)
        );
        signature = iProtoKol.Signature({r: r, s: s, v: v});

        changePrank(investor2);
        protokol.claimPreSaleTokens(campaignId, progress, r, s, v);

        // Each investor starts with the balance of 5k usdt, after claiming this investor should get
        // 237.5 more tokens because his progress was 50% when he got blacklisted and
        // total his eligible reward was 475 tokens
        assertEq(usdt.balanceOf(address(investor2)), 5237.5e6);
    }

    function testCannot_InvestMoreThanRemainingInUsdtCampaign() external {
        uint256 campaignId = 0;
        uint16 tgePercentage = 10000; // 100%
        uint256 progress = 5000; // 50%
        uint256 investmentAmount = 1000 ether; // 100% share (no txn fee cause USDT campaign)

        vestingDetails = getNonVestingDetails();

        changePrank(owner1);

        createCampaignUSDT(tgePercentage, vestingDetails);

        // Approving presale tokens (which is usdt)
        usdt.approve(address(protokol), usdt.balanceOf(owner1));

        // Generating TGE
        protokol.generateTGE(0);

        changePrank(investor1);

        // INVESTOR

        (uint8 v, bytes32 r, bytes32 s) = signMessage(
            getInvestMessageHash(investor1, investmentAmount)
        );
        signature = iProtoKol.Signature({r: r, s: s, v: v});

        protokol.registerKOL("Alice");
        protokol.investInCampaign(
            campaignId,
            investmentAmount,
            USDT,
            signature
        );

        // INVESTOR 2

        uint256 newInvestAmount = 1 ether;
        (v, r, s) = signMessage(
            getInvestMessageHash(investor2, newInvestAmount)
        );
        signature = iProtoKol.Signature({r: r, s: s, v: v});

        changePrank(investor2);

        protokol.registerKOL("Bob");

        vm.expectRevert(bytes("AGI"));

        // Second investor tries to invest
        protokol.investInCampaign(campaignId, newInvestAmount, USDT, signature);
    }

    function test_InvestInUsdtCampaign_ClaimAfterTimePassed_NewInvestorInvests()
        external
    {
        // Scenario: Invest 100% in a USDT campaign -> Investor claims after time has expired ->
        // New investor invest's remaining investment

        uint256 campaignId = 0;
        uint16 tgePercentage = 5000; // 50%
        uint256 progress = 5000; // 50%
        uint256 investmentAmount = 1000 ether; // 100% share (no txn fee cause USDT campaign)

        vestingDetails = getVestingDetails();

        changePrank(owner1);

        createCampaignUSDT(tgePercentage, vestingDetails);

        // Approving presale tokens (which is usdt)
        usdt.approve(address(protokol), usdt.balanceOf(owner1));

        // Generating TGE
        protokol.generateTGE(0);

        changePrank(investor1);

        // INVESTOR

        (uint8 v, bytes32 r, bytes32 s) = signMessage(
            getInvestMessageHash(investor1, investmentAmount)
        );
        signature = iProtoKol.Signature({r: r, s: s, v: v});

        protokol.registerKOL("Alice");
        protokol.investInCampaign(
            campaignId,
            investmentAmount,
            USDT,
            signature
        );

        skip(tgeDate + 5 days);

        // First investor claiming
        (v, r, s) = signMessage(
            getClaimPresaleMessageHash(investor1, progress)
        );
        signature = iProtoKol.Signature({r: r, s: s, v: v});

        changePrank(investor1);
        protokol.claimPreSaleTokens(campaignId, progress, r, s, v);

        // INVESTOR 2

        uint256 newInvestAmount = 500 ether;
        (v, r, s) = signMessage(
            getInvestMessageHash(investor2, newInvestAmount)
        );
        signature = iProtoKol.Signature({r: r, s: s, v: v});

        changePrank(investor2);

        protokol.registerKOL("Bob");
        // Second investor investing
        protokol.investInCampaign(campaignId, newInvestAmount, USDT, signature);

        // Because we investing in a usdt campaign
        assertEq(usdt.balanceOf(investor2), 5000e6);
    }

    // Helper functions

    function createCampaign(
        uint16 _tgePercentage,
        iProtoKol.VestingDetails memory _vestingDetails
    ) private {
        (uint8 v, bytes32 r, bytes32 s) = signMessage(getCampaignMessageHash());

        campaignDetails = getCampaignDetails();

        vestingDetails = _vestingDetails;

        protokol.createCampaign(
            campaignDetails,
            vestingDetails,
            tgeDate,
            _tgePercentage,
            r,
            s,
            v
        );
    }

    function createCampaignUSDT(
        uint16 _tgePercentage,
        iProtoKol.VestingDetails memory _vestingDetails
    ) private {
        (uint8 v, bytes32 r, bytes32 s) = signMessage(getCampaignMessageHash());

        campaignDetails = getCampaignDetails();

        // Cause presale token is USDT
        campaignDetails.preSaleToken = USDT;

        vestingDetails = _vestingDetails;

        console.log("vesting Details", vestingDetails.isVestingEnabled);

        protokol.createCampaign(
            campaignDetails,
            vestingDetails,
            tgeDate,
            _tgePercentage,
            r,
            s,
            v
        );
    }

    function signMessage(bytes32 _messageHash)
        private
        returns (
            uint8,
            bytes32,
            bytes32
        )
    {
        return vm.sign(admin_pk, _messageHash);
    }

    function getCampaignMessageHash() private view returns (bytes32) {
        uint256 marketingBudget = 1000 ether;
        return
            keccak256(
                abi.encodePacked(
                    owner1,
                    campaignStartDate,
                    marketingBudget, // required investment is same
                    marketingBudget,
                    block.chainid
                )
            );
    }

    function getInvestMessageHash(address _investor, uint256 _investmentAmount)
        private
        view
        returns (bytes32)
    {
        return
            keccak256(
                abi.encodePacked(
                    _investor,
                    campaignStartDate,
                    USDT,
                    _investmentAmount,
                    block.chainid
                )
            );
    }

    function getClaimPresaleMessageHash(address _investor, uint256 _progress)
        private
        view
        returns (bytes32)
    {
        return
            keccak256(
                abi.encodePacked(
                    _investor,
                    uint256(0), // Campaign ID
                    _progress,
                    block.chainid
                )
            );
    }

    function getCampaignDetails()
        private
        view
        returns (iProtoKol.CampaignDetails memory)
    {
        uint256 marketingBudget = 1000 ether;
        return
            iProtoKol.CampaignDetails({
                preSaleToken: address(presale),
                campaignOwner: owner1,
                secondOwner: 0x0000000000000000000000000000000000000000,
                requiredInvestment: marketingBudget,
                marketingBudget: marketingBudget,
                startDate: campaignStartDate,
                endDate: 92,
                remainingInvestment: 0,
                stakingAmount: 0,
                enteredInvestmentAgainstMarketingBudget: 0,
                investmentClaimed: 0,
                presaleAmount: 0,
                presaleWithdrawn: 0
            });
    }

    function getNonVestingDetails()
        private
        view
        returns (iProtoKol.VestingDetails memory)
    {
        return
            iProtoKol.VestingDetails({
                isVestingEnabled: false,
                NumberOfvestings: 0,
                vestingCycleDuration: 0,
                vestingAmtPerCycle: 0
            });
    }

    function getVestingDetails()
        private
        view
        returns (iProtoKol.VestingDetails memory)
    {
        return
            iProtoKol.VestingDetails({
                isVestingEnabled: true,
                NumberOfvestings: 2,
                vestingCycleDuration: 2,
                vestingAmtPerCycle: 0
            });
    }
}
