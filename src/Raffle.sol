// Contract elements should be laid out in the following order:
// Pragma statements
// Import statements
// Events
// Errors
// Interfaces
// Libraries
// Contracts

// Functions should be grouped according to their visibility and ordered:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private

// SPDX-License Identifier: MIT

pragma solidity ^0.8.19;
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title Raffle
 * @author Hackflu
 * @notice This contract is a placeholder for a raffle system.
 */
contract Raffle is VRFConsumerBaseV2Plus {
    /** Error */
    error Raffle_SendMoreToEnterRaffle();
    error Raffle_TransferFailed();
    error Raffle_RaffleNotOpen();
    error Raffle_UpkeepNotNeeded(
        uint256 currentBalance,
        uint256 numPlayers,
        uint256 raffleState
    );

    // tye declaration
    enum RaffleState {
        OPEN,
        CALCULATING
    }

    // @dev The duration of the raffle in seconds
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;
    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    uint256 private i_interval;
    uint256 private i_entranceFee;
    uint32 private immutable i_callbackGasLimit;
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    // Events
    event RaffleEnter(address indexed player);
    event WinnerPicked(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);
    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gaslane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        s_lastTimeStamp = block.timestamp;
        i_keyHash = gaslane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_raffleState = RaffleState.OPEN;
    }

    function enterRaffle() external payable {
        // require(msg.value >= i_entranceFee, "Not enough ETH sent to enter the raffle");
        // takes lot of time to compile, , so it is better to use custom errors
        // require(msg.value >= i_entranceFee, SendMoreToEnterRaffle());

        if (msg.value < i_entranceFee) {
            revert Raffle_SendMoreToEnterRaffle();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle_RaffleNotOpen();
        }
        s_players.push(payable(msg.sender));
        emit RaffleEnter(msg.sender);
    }

    /**
     * @dev This the function that the Chainlink nodes will call to see
     * if the lottery is ready to get winner picked
     * @param - ignored
     * @return upkeepNeeded - true if it's time to retart the lottery
     * @return - ignored
     */
    function checkUpkeep(
        bytes memory /* checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool timeHasPassed = ((block.timestamp - s_lastTimeStamp) >=
            i_interval);
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        // a way to avoid using conditions
        upkeepNeeded = timeHasPassed && isOpen && hasBalance && hasPlayers;
        return (upkeepNeeded, "");
    }

    function performUpkeep(bytes calldata /* performData */) external {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle_UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }
        s_raffleState = RaffleState.CALCULATING;
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient
            .RandomWordsRequest({
                keyHash: i_keyHash,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            });
        uint256 requestId = s_vrfCoordinator.requestRandomWords(request);
        emit RequestedRaffleWinner(requestId);
    }

    // CEI : checks , effects , interactions
    function fulfillRandomWords(
        uint256,
        /*requestId*/ uint256[] calldata randomWords
    ) internal override {
        // checks
        //Effects
        //interactions
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;
        s_raffleState = RaffleState.OPEN;
        /**
         * @dev reset the players array222222
         */

        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        emit WinnerPicked(s_recentWinner);

        (bool sucess, ) = recentWinner.call{value: address(this).balance}("");
        if (!sucess) {
            revert Raffle_TransferFailed();
        }
    }

    /**
     * @dev getter functions
     */
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getPlayer(uint256 index) external view returns (address) {
        return s_players[index];
    }
    
    function getRaffleState() external view returns (RaffleState ) {
        return s_raffleState;
    }
}
