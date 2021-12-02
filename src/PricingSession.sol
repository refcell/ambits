// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import {ReentrancyGuard} from "./helpers/ReentrancyGuard.sol";
import {IABCTreasury} from "./interfaces/IABCTreasury.sol";
import {SafeMath} from "./libraries/SafeMath.sol";
import {sqrtLibrary} from "./libraries/sqrtLibrary.sol";
import {PostSessionLibrary} from "./libraries/PostSessionLibrary.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {ABCTreasury} from "./ABCTreasury.sol";

/// @author Medici
/// @title Pricing session contract for Abacus
contract PricingSession is ReentrancyGuard {

    using SafeMath for uint;

    /* ======== ADDRESS ======== */

    address public ABCToken;
    ABCTreasury public Treasury;
    address public admin;
    address auction;

    /* ======== BOOL ======== */

    bool auctionStatus;
    bool tokenStatus;
    
    /* ======== MAPPINGS ======== */

    /// @notice maps each user to their total points earned
    mapping(address => uint) public points;

    /// @notice maps each user to their total profit earned
    mapping(address => uint) public profitStored;

    /// @notice maps each user to their principal stored
    mapping(address => uint) public principalStored;

    /// @notice maps each NFT to its current nonce value
    mapping(address => mapping (uint => uint)) public nftNonce; 

    mapping(uint => mapping(address => mapping(uint => VotingSessionMapping))) NftSessionMap;

    /// @notice maps each NFT pricing session (nonce dependent) to its necessary session checks (i.e. checking session progression)
    /// @dev nonce => tokenAddress => tokenId => session metadata
    mapping(uint => mapping(address => mapping(uint => VotingSessionChecks))) public NftSessionCheck;

    /// @notice maps each NFT pricing session (nonce dependent) to its necessary session core values (i.e. total participants, total stake, etc...)
    mapping(uint => mapping(address => mapping(uint => VotingSessionCore))) public NftSessionCore;

    /// @notice maps each NFT pricing session (nonce dependent) to its final appraisal value output
    mapping(uint => mapping(address => mapping(uint => uint))) public finalAppraisalValue;
    
    /* ======== STRUCTS ======== */

    /// @notice tracks all of the mappings necessary to operate a session
    struct VotingSessionMapping {

        mapping (address => uint) voterCheck;
        mapping (address => uint) winnerPoints;
        mapping (address => uint) amountHarvested;
        mapping (address => Voter) nftVotes;
    }

    /// @notice track necessary session checks (i.e. whether its time to weigh votes or harvest)
    struct VotingSessionChecks {

        uint sessionProgression;
        uint calls;
        uint correct;
        uint incorrect;
        uint timeFinalAppraisalSet;
    }

    /// @notice track the core values of a session (max appraisal value, total session stake, etc...)
    struct VotingSessionCore {

        uint endTime;
        uint bounty;
        uint lowestStake;
        uint maxAppraisal;
        uint totalAppraisalValue;
        uint totalSessionStake;
        uint totalProfit;
        uint totalWinnerPoints;
        uint totalVotes;
        uint uniqueVoters;
        uint votingTime;
    }

    /// @notice track voter information
    struct Voter {

        bytes32 concealedAppraisal;
        uint base;
        uint appraisal;
        uint stake;
    }

    /* ======== EVENTS ======== */

    event PricingSessionCreated(address creator_, uint nonce, address nftAddress_, uint tokenid_, uint initialAppraisal_, uint bounty_);
    event newAppraisalAdded(address voter_, uint nonce, address nftAddress_, uint tokenid_, uint stake_, bytes32 userHash_);
    event bountyIncreased(address sender_, uint nonce, address nftAddress_, uint tokenid_, uint amount_);
    event appraisalIncreased(address sender_, uint nonce, address nftAddress_, uint tokenid_, uint amount_);
    event voteWeighed(address user_, uint nonce, address nftAddress_, uint tokenid_, uint appraisal);
    event finalAppraisalDetermined(uint nonce, address nftAddress_, uint tokenid_, uint finalAppraisal, uint amountOfParticipants, uint totalStake);
    event userHarvested(address user_, uint nonce, address nftAddress_, uint tokenid_, uint harvested);
    event ethClaimedByUser(address user_, uint ethClaimed);
    event ethToABCExchange(address user_, uint ethExchanged, uint ppSent);
    event sessionEnded(address nftAddress, uint tokenid, uint nonce);

    /* ======== CONSTRUCTOR ======== */

    constructor(address _treasury, address _auction) {
        Treasury = ABCTreasury(payable(_treasury));
        auction = _auction;
        admin = msg.sender;
        auctionStatus = true;
        tokenStatus = false;
    }

    /// @notice set the auction address to be referenced throughout the contract
    /// @param _auction desired auction address to be stored and referenced in contract
    function setAuction(address _auction) external {
        require(msg.sender == admin);
        auction = _auction;
    }

    /// @notice set the auction status based on the active/inactive status of the bounty auction
    /// @param status desired auction status to be stored and referenced in contract
    function setAuctionStatus(bool status) external {
        require(msg.sender == admin); 
        auctionStatus = status;
    }

    function setABCToken(address _token) external {
        ABCToken = _token;
        tokenStatus = true;
    }

    /// @notice Allow user to create new session and attach initial bounty
    /**
    @dev NFT sessions are indexed using a nonce per specific nft.
    The mapping is done by mapping a nonce to an NFT address to the 
    NFT token id. 
    */ 
    /// @param nftAddress NFT contract address of desired NFT to be priced
    /// @param tokenid NFT token id of desired NFT to be priced 
    /// @param _initialAppraisal appraisal value for max value to be instantiated against
    /// @param _votingTime voting window duration
    function createNewSession(
        address nftAddress,
        uint tokenid,
        uint _initialAppraisal,
        uint _votingTime
    ) stopOverwrite(nftAddress, tokenid) external payable {
        require(_votingTime <= 1 days && (!auctionStatus || msg.sender == auction));
        VotingSessionCore storage sessionCore = NftSessionCore[nftNonce[nftAddress][tokenid]][nftAddress][tokenid];
        if(msg.sender == auction) {}
        else {
            uint abcCost = 0.005 ether *(ethToAbc());
            (bool abcSent) = IERC20(ABCToken).transferFrom(msg.sender, address(Treasury), abcCost);
            require(abcSent);
        }
        if(nftNonce[nftAddress][tokenid] == 0 || getStatus(nftAddress, tokenid) == 5) {}
        else if(block.timestamp > sessionCore.endTime + sessionCore.votingTime * 3) {
            _executeEnd(nftAddress, tokenid);
        }
        nftNonce[nftAddress][tokenid]++;
        VotingSessionCore storage sessionCoreNew = NftSessionCore[nftNonce[nftAddress][tokenid]][nftAddress][tokenid];
        sessionCoreNew.votingTime = _votingTime;
        sessionCoreNew.maxAppraisal = 69420 * _initialAppraisal / 1000;
        sessionCoreNew.lowestStake = 100000 ether;
        sessionCoreNew.endTime = block.timestamp + _votingTime;
        sessionCoreNew.bounty = msg.value;
        emit PricingSessionCreated(msg.sender, nftNonce[nftAddress][tokenid], nftAddress, tokenid, _initialAppraisal, msg.value);
    }

    function depositPrincipal() nonReentrant payable external {
        principalStored[msg.sender] += msg.value;
    }

    /// @notice allows user to reclaim principalUsed in batches
    function claimPrincipalUsed(uint _amount) nonReentrant external {
        require(_amount <= principalStored[msg.sender]);
        principalStored[msg.sender] -= _amount;
        (bool sent, ) = msg.sender.call{value: _amount}("");
        require(sent);
    }

    /// @notice allows user to claim batched earnings
    /// @param trigger denotes whether the user desires it in ETH (1) or ABC (2)
    function claimProfitsEarned(uint trigger, uint _amount) nonReentrant external {
        require(trigger == 1 || trigger == 2);
        if(trigger == 2) {
            require(tokenStatus);
        }
        require(profitStored[msg.sender] >= _amount);
        if(trigger == 1) {
            (bool sent1, ) = msg.sender.call{value: _amount}("");
            require(sent1);
            profitStored[msg.sender] -= _amount;
            emit ethClaimedByUser(msg.sender, _amount);
        }
        else if(trigger == 2) {
            uint abcAmount = _amount / (0.00005 ether + 0.000015 ether * Treasury.tokensClaimed()/(1000000*1e18));
            uint abcPayout = ((_amount / (0.00005 ether + 0.000015 ether * Treasury.tokensClaimed()/(1000000*1e18))) + (_amount / (0.00005 ether + 0.000015 ether * Treasury.tokensClaimed() + abcAmount) / (1000000*1e18)) / 2);
            (bool sent3, ) = payable(Treasury).call{value: _amount}("");
            require(sent3);
            profitStored[msg.sender] -= _amount;
            Treasury.sendABCToken(msg.sender, abcPayout * 1e18);
            emit ethToABCExchange(msg.sender, _amount, abcPayout);
        }
    } 

    /* ======== USER VOTE FUNCTIONS ======== */
    
    /// @notice Allows user to set vote in party 
    /** 
    @dev Users appraisal is hashed so users can't track final appraisal and submit vote right before session ends.
    Therefore, users must remember their appraisal in order to reveal their appraisal in the next function.
    */
    /// @param nftAddress NFT contract address of NFT being appraised
    /// @param tokenid NFT tokenid of NFT being appraised
    /// @param concealedAppraisal concealed bid that is a hash of the appraisooooors appraisal value, wallet address, and seed number
    function setVote(
        address nftAddress,
        uint tokenid,
        uint stake,
        bytes32 concealedAppraisal
    ) properVote(nftAddress, tokenid, stake) external {
        uint nonce = nftNonce[nftAddress][tokenid];
        VotingSessionCore storage sessionCore = NftSessionCore[nonce][nftAddress][tokenid];
        VotingSessionMapping storage sessionMap = NftSessionMap[nonce][nftAddress][tokenid];
        require(sessionCore.endTime > block.timestamp && stake <= principalStored[msg.sender]);
        sessionMap.voterCheck[msg.sender] = 1;
        principalStored[msg.sender] -= stake;
        if (stake < sessionCore.lowestStake) {
            sessionCore.lowestStake = stake;
        }
        sessionCore.uniqueVoters++;
        sessionCore.totalSessionStake = sessionCore.totalSessionStake.add(stake);
        sessionMap.nftVotes[msg.sender].concealedAppraisal = concealedAppraisal;
        sessionMap.nftVotes[msg.sender].stake = stake;
        emit newAppraisalAdded(msg.sender, nonce, nftAddress, tokenid, stake, concealedAppraisal);
    }

    /// @notice allow user to update value inputs of their vote while voting is still active
    /// @param nftAddress NFT contract address of NFT being appraised
    /// @param tokenid NFT tokenid of NFT being appraised
    /// @param concealedAppraisal concealed bid that is a hash of the appraisooooors new appraisal value, wallet address, and seed number
    function updateVote(
        address nftAddress,
        uint tokenid,
        bytes32 concealedAppraisal
    ) external {
        uint nonce = nftNonce[nftAddress][tokenid];
        VotingSessionCore storage sessionCore = NftSessionCore[nonce][nftAddress][tokenid];
        VotingSessionMapping storage sessionMap = NftSessionMap[nonce][nftAddress][tokenid];
        require(sessionMap.voterCheck[msg.sender] == 1);
        require(sessionCore.endTime > block.timestamp);
        sessionMap.nftVotes[msg.sender].concealedAppraisal = concealedAppraisal;
    }

    /// @notice Reveals user vote and weights based on the sessions lowest stake
    /**
    @dev calculation can be found in the weightVoteLibrary.sol file. 
    Votes are weighted as sqrt(userStake/lowestStake). Depending on a votes weight
    it is then added as multiple votes of that appraisal (i.e. if someoneone has
    voting weight of 8, 8 votes are submitted using their appraisal).
    */
    /// @param nftAddress NFT contract address of NFT being appraised
    /// @param tokenid NFT tokenid of NFT being appraised
    /// @param appraisal appraisooooor appraisal value used to unlock concealed appraisal
    /// @param seedNum appraisooooor seed number used to unlock concealed appraisal
    function weightVote(address nftAddress, uint tokenid, uint appraisal, uint seedNum) checkParticipation(nftAddress, tokenid) nonReentrant external {
        uint nonce = nftNonce[nftAddress][tokenid];
        VotingSessionCore storage sessionCore = NftSessionCore[nonce][nftAddress][tokenid];
        VotingSessionMapping storage sessionMap = NftSessionMap[nonce][nftAddress][tokenid];
        VotingSessionChecks storage sessionCheck = NftSessionCheck[nonce][nftAddress][tokenid];
        require(sessionCheck.sessionProgression < 2
                && sessionCore.endTime < block.timestamp
                && sessionMap.voterCheck[msg.sender] == 1
                && sessionMap.nftVotes[msg.sender].concealedAppraisal == keccak256(abi.encodePacked(appraisal, msg.sender, seedNum))
                && sessionCore.maxAppraisal >= appraisal
        );
        sessionMap.voterCheck[msg.sender] = 2;
        if(sessionCheck.sessionProgression == 0) {
            sessionCheck.sessionProgression = 1;
        }
        _weigh(nftAddress, tokenid, appraisal);
        emit voteWeighed(msg.sender, nonce, nftAddress, tokenid, appraisal);
        if(sessionCheck.calls == sessionCore.uniqueVoters || sessionCore.endTime + sessionCore.votingTime < block.timestamp) {
            sessionCheck.sessionProgression = 2;
            sessionCore.uniqueVoters = sessionCheck.calls;
            sessionCheck.calls = 0;
        }
    }
    
    /// @notice takes average of appraisals and outputs a final appraisal value.
    /// @param nftAddress NFT contract address of NFT being appraised
    /// @param tokenid NFT tokenid of NFT being appraised
    function setFinalAppraisal(address nftAddress, uint tokenid) public {
        uint nonce = nftNonce[nftAddress][tokenid];
        VotingSessionCore storage sessionCore = NftSessionCore[nonce][nftAddress][tokenid];
        VotingSessionChecks storage sessionCheck = NftSessionCheck[nonce][nftAddress][tokenid];
        require(
            (block.timestamp > sessionCore.endTime + sessionCore.votingTime || sessionCheck.sessionProgression == 2)
            && sessionCheck.sessionProgression <= 2
        );
        Treasury.updateNftPriced();
        if(sessionCheck.calls != 0) {
            sessionCore.uniqueVoters = sessionCheck.calls;
        }
        sessionCore.totalProfit += sessionCore.bounty;
        sessionCore.totalSessionStake += sessionCore.bounty;
        sessionCheck.calls = 0;
        sessionCheck.timeFinalAppraisalSet = block.timestamp;
        finalAppraisalValue[nonce][nftAddress][tokenid] = (sessionCore.totalAppraisalValue)/(sessionCore.totalVotes);
        sessionCheck.sessionProgression = 3;
        emit finalAppraisalDetermined(nftNonce[nftAddress][tokenid], nftAddress, tokenid, finalAppraisalValue[nftNonce[nftAddress][tokenid]][nftAddress][tokenid], sessionCore.uniqueVoters, sessionCore.totalSessionStake);
    }

    /// @notice Calculates users base and harvests their loss before returning remaining stake
    /**
    @dev A couple notes:
    1. Base is calculated based on margin of error.
        > +/- 5% = 1
        > +/- 4% = 2
        > +/- 3% = 3
        > +/- 2% = 4
        > +/- 1% = 5
        > Exact = 6
    2. winnerPoints are calculated based on --> base * stake
    3. Losses are harvested based on --> (margin of error - 5%) * stake
    */
    /// @param nftAddress NFT contract address of NFT being appraised
    /// @param tokenid NFT tokenid of NFT being appraised
    function harvest(address nftAddress, uint tokenid) checkParticipation(nftAddress, tokenid) nonReentrant external {
        uint nonce = nftNonce[nftAddress][tokenid];
        VotingSessionCore storage sessionCore = NftSessionCore[nonce][nftAddress][tokenid];
        VotingSessionChecks storage sessionCheck = NftSessionCheck[nonce][nftAddress][tokenid];
        VotingSessionMapping storage sessionMap = NftSessionMap[nonce][nftAddress][tokenid];
        require(
            sessionCheck.sessionProgression == 3
            && sessionMap.voterCheck[msg.sender] == 2
        );
        sessionCheck.calls++;
        sessionMap.voterCheck[msg.sender] = 3;
        
        _harvest(nftAddress, tokenid);

        sessionMap.nftVotes[msg.sender].stake -= sessionMap.amountHarvested[msg.sender];
        uint commission = PostSessionLibrary.setCommission(address(Treasury).balance).mul(sessionMap.amountHarvested[msg.sender]).div(10000);
        sessionCore.totalSessionStake -= commission;
        sessionMap.amountHarvested[msg.sender] -= commission;
        sessionCore.totalProfit += sessionMap.amountHarvested[msg.sender];
        Treasury.updateProfitGenerated(sessionMap.amountHarvested[msg.sender]);
        (bool sent, ) = payable(Treasury).call{value: commission}("");
        require(sent);
        emit userHarvested(msg.sender, nonce, nftAddress, tokenid, sessionMap.amountHarvested[msg.sender]);

        if(sessionCheck.calls == sessionCore.uniqueVoters) {
            sessionCheck.sessionProgression = 4;
            sessionCore.uniqueVoters = sessionCheck.calls;
            sessionCheck.calls = 0;
        }
    }

    /// @notice User claims principal stake along with any earned profits in ETH or ABC form
    /**
    @dev 
    1. Calculates user principal return value
    2. Enacts sybil defense mechanism
    3. Edits totalProfits and totalSessionStake to reflect claim
    5. Pays out principal
    6. Adds profit credit to profitStored
    */
    /// @param nftAddress NFT contract address of NFT being appraised
    /// @param tokenid NFT tokenid of NFT being appraised
    function claim(address nftAddress, uint tokenid) checkParticipation(nftAddress, tokenid) nonReentrant external returns(uint) {
        uint nonce = nftNonce[nftAddress][tokenid];
        VotingSessionCore storage sessionCore = NftSessionCore[nonce][nftAddress][tokenid];
        VotingSessionChecks storage sessionCheck = NftSessionCheck[nonce][nftAddress][tokenid];
        VotingSessionMapping storage sessionMap = NftSessionMap[nonce][nftAddress][tokenid];
        if (sessionCheck.timeFinalAppraisalSet == 0) {
            require(
            sessionCheck.sessionProgression == 4
            || block.timestamp > (sessionCore.endTime + sessionCore.votingTime * 2)
            );
        }
        else{
            require(
            (block.timestamp > sessionCheck.timeFinalAppraisalSet + sessionCore.votingTime || sessionCheck.sessionProgression == 4)
            && sessionCheck.sessionProgression <= 4
            && sessionMap.voterCheck[msg.sender] == 3
            );
        }
        uint principalReturn;
        sessionMap.voterCheck[msg.sender] = 4;
        if(sessionCheck.sessionProgression == 3) {
            sessionCore.uniqueVoters = sessionCheck.calls;
            sessionCheck.calls = 0;
            sessionCheck.sessionProgression = 4;
        }
        if(sessionCheck.correct * 100 / (sessionCheck.correct + sessionCheck.incorrect) >= 90) {
            principalReturn += sessionMap.nftVotes[msg.sender].stake + sessionMap.amountHarvested[msg.sender];
        }
        else {
            principalReturn += sessionMap.nftVotes[msg.sender].stake;
        }
        sessionCheck.calls++;
        uint payout;
        if(sessionMap.winnerPoints[msg.sender] == 0) {
            payout = 0;
        }
        else {
            payout = sessionCore.totalProfit * sessionMap.winnerPoints[msg.sender] / sessionCore.totalWinnerPoints;
        }
        profitStored[msg.sender] += payout;
        sessionCore.totalProfit -= payout;
        sessionCore.totalSessionStake -= payout + principalReturn;
        principalStored[msg.sender] += principalReturn;
        sessionCore.totalWinnerPoints -= sessionMap.winnerPoints[msg.sender];
        sessionMap.winnerPoints[msg.sender] = 0;
        if(sessionCheck.calls == sessionCore.uniqueVoters || block.timestamp > sessionCheck.timeFinalAppraisalSet + sessionCore.votingTime*2) {
            sessionCheck.sessionProgression = 5;
            _executeEnd(nftAddress, tokenid);
            return 0;
        }

        return 1;
    }
    
    /// @notice Custodial function to clear funds and remove session as child
    /// @dev Caller receives 10% of the funds that are meant to be cleared
    /// @param nftAddress NFT contract address of NFT being appraised
    /// @param tokenid NFT tokenid of NFT being appraised
    function endSession(address nftAddress, uint tokenid) public {
        uint nonce = nftNonce[nftAddress][tokenid];
        VotingSessionCore storage sessionCore = NftSessionCore[nonce][nftAddress][tokenid];
        VotingSessionChecks storage sessionCheck = NftSessionCheck[nonce][nftAddress][tokenid];
        if (sessionCheck.timeFinalAppraisalSet == 0) {
            revert();
        }
        else{
            require(
                (block.timestamp > sessionCheck.timeFinalAppraisalSet + sessionCore.votingTime * 2 || sessionCheck.sessionProgression == 5)
            );
            _executeEnd(nftAddress, tokenid);
        }
    }

    /* ======== INTERNAL FUNCTIONS ======== */

    function _weigh(address nftAddress, uint tokenid, uint appraisal) internal {
        uint nonce = nftNonce[nftAddress][tokenid];
        VotingSessionCore storage sessionCore = NftSessionCore[nonce][nftAddress][tokenid];
        VotingSessionMapping storage sessionMap = NftSessionMap[nonce][nftAddress][tokenid];
        VotingSessionChecks storage sessionCheck = NftSessionCheck[nonce][nftAddress][tokenid];
        sessionMap.nftVotes[msg.sender].appraisal = appraisal;
        uint weight = sqrtLibrary.sqrt(sessionMap.nftVotes[msg.sender].stake/sessionCore.lowestStake);
        sessionCore.totalVotes += weight;
        sessionCheck.calls++;
        
        sessionCore.totalAppraisalValue = sessionCore.totalAppraisalValue.add((weight) * appraisal);
    }

    function _harvest(address nftAddress, uint tokenid) internal {
        uint nonce = nftNonce[nftAddress][tokenid];
        VotingSessionCore storage sessionCore = NftSessionCore[nonce][nftAddress][tokenid];
        VotingSessionChecks storage sessionCheck = NftSessionCheck[nonce][nftAddress][tokenid];
        VotingSessionMapping storage sessionMap = NftSessionMap[nonce][nftAddress][tokenid];
        sessionMap.nftVotes[msg.sender].base = 
            PostSessionLibrary.calculateBase(
                finalAppraisalValue[nftNonce[nftAddress][tokenid]][nftAddress][tokenid], 
                sessionMap.nftVotes[msg.sender].appraisal
            );
        uint weight = sqrtLibrary.sqrt(sessionMap.nftVotes[msg.sender].stake/sessionCore.lowestStake);
        if(sessionMap.nftVotes[msg.sender].base > 0) {
            sessionCore.totalWinnerPoints += sessionMap.nftVotes[msg.sender].base * weight;
            sessionMap.winnerPoints[msg.sender] = sessionMap.nftVotes[msg.sender].base * weight;
            sessionCheck.correct += weight;
        }
        else {
            sessionCheck.incorrect += weight;
        }
        
       sessionMap.amountHarvested[msg.sender] = PostSessionLibrary.harvest( 
            sessionMap.nftVotes[msg.sender].stake, 
            sessionMap.nftVotes[msg.sender].appraisal,
            finalAppraisalValue[nftNonce[nftAddress][tokenid]][nftAddress][tokenid]
        );
    }

    /// @notice executes custodial actions to end a session
    /** @dev Clears session claims to funds, distributes 95% of residual funds
    to treasury and the other 5% to the caller. Then proceeds to set the total
    session stake to 0 and emit an end session event to signify session completion. 
     */
    /// @param nftAddress NFT contract address of NFT being appraised
    /// @param tokenid NFT tokenid of NFT being appraised
    function _executeEnd(address nftAddress, uint tokenid) internal {
        uint nonce = nftNonce[nftAddress][tokenid];
        VotingSessionCore storage sessionCore = NftSessionCore[nonce][nftAddress][tokenid];
        VotingSessionChecks storage sessionCheck = NftSessionCheck[nonce][nftAddress][tokenid];
        sessionCheck.sessionProgression = 5;
        uint tPayout = 97*sessionCore.totalSessionStake/100;
        uint cPayout = sessionCore.totalSessionStake - tPayout;
        (bool sent, ) = payable(Treasury).call{value: tPayout}("");
        require(sent);
        (bool sent1, ) = msg.sender.call{value: cPayout}("");
        require(sent1);
        sessionCore.totalSessionStake = 0;
        emit sessionEnded(nftAddress, tokenid, nftNonce[nftAddress][tokenid]);
    }

    /* ======== FUND INCREASE ======== */

    /// @notice allow any user to add additional bounty on session of their choice
    /// @param nftAddress NFT contract address of NFT being appraised
    /// @param tokenid NFT tokenid of NFT being appraised
    function addToBounty(address nftAddress, uint tokenid) payable external {
        VotingSessionCore storage sessionCore = NftSessionCore[nftNonce[nftAddress][tokenid]][nftAddress][tokenid];
        require(sessionCore.endTime > block.timestamp);
        sessionCore.bounty += msg.value;
        sessionCore.totalSessionStake += msg.value;
        emit bountyIncreased(msg.sender, nftNonce[nftAddress][tokenid], nftAddress, tokenid, msg.value);
    }

    /* ======== VIEW FUNCTIONS ======== */

    /// @notice returns the status of the session in question
    /// @param nftAddress NFT contract address of NFT being appraised
    /// @param tokenid NFT tokenid of NFT being appraised
    function getStatus(address nftAddress, uint tokenid) view public returns(uint) {
        return NftSessionCheck[nftNonce[nftAddress][tokenid]][nftAddress][tokenid].sessionProgression;
    }

    /// @notice returns the current spot exchange rate of ETH to ABC
    function ethToAbc() view public returns(uint) {
        return 1e18 / (0.00005 ether + 0.000015 ether * Treasury.tokensClaimed() / (1000000*1e18));
    }

    /// @notice returns the payout earned from the current session
    /// @param nftAddress NFT contract address of NFT being appraised
    /// @param tokenid NFT tokenid of NFT being appraised
    function getEthPayout(address nftAddress, uint tokenid) view external returns(uint) {
        VotingSessionCore storage sessionCore = NftSessionCore[nftNonce[nftAddress][tokenid]][nftAddress][tokenid];
        if(sessionCore.totalWinnerPoints == 0) {
            return 0;
        }
        return sessionCore.totalSessionStake * NftSessionMap[nftNonce[nftAddress][tokenid]][nftAddress][tokenid].winnerPoints[msg.sender] / sessionCore.totalWinnerPoints;
    }

    /// @notice check the users status in terms of session interaction
    /// @param nftAddress NFT contract address of NFT being appraised
    /// @param tokenid NFT tokenid of NFT being appraised
    /// @param _user appraisooooor who's session progress is of interest
    function getVoterCheck(address nftAddress, uint tokenid, address _user) view external returns(uint) {
        return NftSessionMap[nftNonce[nftAddress][tokenid]][nftAddress][tokenid].voterCheck[_user];
    }

    /* ======== FALLBACK FUNCTIONS ======== */

    receive() external payable {}
    fallback() external payable {}

    /* ======== MODIFIERS ======== */

    /// @notice stop users from being able to create multiple sessions for the same NFT at the same time
    modifier stopOverwrite(
        address nftAddress, 
        uint tokenid
    ) {
        require(
            nftNonce[nftAddress][tokenid] == 0 
            || getStatus(nftAddress, tokenid) == 5
            || block.timestamp > NftSessionCore[nftNonce[nftAddress][tokenid]][nftAddress][tokenid].endTime + NftSessionCore[nftNonce[nftAddress][tokenid]][nftAddress][tokenid].votingTime * 3
        );
        _;
    }
    
    /// @notice makes sure that a user that submits a vote satisfies the proper voting parameters
    modifier properVote(
        address nftAddress,
        uint tokenid,
        uint stake
    ) {
        require(
            NftSessionMap[nftNonce[nftAddress][tokenid]][nftAddress][tokenid].voterCheck[msg.sender] == 0
            && stake >= 0.005 ether
        );
        _;
    }
    
    /// @notice checks the participation of the msg.sender 
    modifier checkParticipation(
        address nftAddress,
        uint tokenid
    ) {
        require(NftSessionMap[nftNonce[nftAddress][tokenid]][nftAddress][tokenid].voterCheck[msg.sender] > 0);
        _;
    }
}