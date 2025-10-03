// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;
import {Test} from "forge-std/Test.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {console2} from "forge-std/console2.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract RaffleTest is Test {
    Raffle public raffle;
    HelperConfig public helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gaslane;
    uint256 subscriptionId;
    uint32 callbackGasLimit;

    address public USER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    event RaffleEnter(address indexed player);

    function setUp() external {
        DeployRaffle deployRaffle = new DeployRaffle();
        (raffle, helperConfig) = deployRaffle.deployContract();
        HelperConfig.NetworkConfig memory networkConfig = helperConfig
            .getConfig();
        entranceFee = networkConfig.entranceFee;
        interval = networkConfig.interval;
        vrfCoordinator = networkConfig.vrfCoordinator;
        gaslane = networkConfig.gaslane;
        subscriptionId = networkConfig.subscriptionId;
        callbackGasLimit = networkConfig.callbackGasLimit;
    }

    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    function testEnterRaffleRevertWhenYouDontPayEnough() public {
        vm.prank(USER);
        vm.expectRevert(Raffle.Raffle_SendMoreToEnterRaffle.selector);
        raffle.enterRaffle{value: 0 ether}();
    }

    function testEtnerRaffleWithEth() public {
        vm.prank(USER);
        vm.deal(USER, STARTING_USER_BALANCE);
        raffle.enterRaffle{value: entranceFee}();
        address player = raffle.getPlayer(0);
        assert(player == USER);
    }

    function testEnterRaffleEmitEvents() public {
        // Arrange
        vm.prank(USER);
        // Act
        vm.expectEmit(true, false, false, false, address(raffle));
        emit RaffleEnter(USER);
        vm.deal(USER, STARTING_USER_BALANCE);
        // Assert
        raffle.enterRaffle{value: entranceFee}();
    }

    function testDontAllowPlayersToEnterWhileRaffleIsCalculating() public {
        // Arrange
        vm.prank(USER);
        vm.deal(USER, STARTING_USER_BALANCE);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        // Act / Assert
        vm.expectRevert(Raffle.Raffle_RaffleNotOpen.selector);
        vm.prank(USER);
        vm.deal(USER, STARTING_USER_BALANCE);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCheckUpkeepReturnsFalseIfItHasNoBalance() public {
        // Arrange
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfRaffleIsntOpen() public {
        vm.prank(USER);
        vm.deal(USER, STARTING_USER_BALANCE);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    // challenge
    // testCheckUpkeepReturnsFalseIfEnoughTimeHasntPassed
    // testCheckUpkeepReturnsTrueWhenParametersAreGood

    /* ------------------------------------------------------------
     *                   Perform Upkeep
     * ------------------------------------------------------------
     */

    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public {
        // Arrange
        vm.prank(USER);
        vm.deal(USER, STARTING_USER_BALANCE);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool upkeep, ) = raffle.checkUpkeep("");
        assert(upkeep);
        console2.log("Upkeep is: ", upkeep);
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState state = Raffle.RaffleState(raffle.getRaffleState());
        console2.log("Raffle state is:");
        console2.logUint(uint256(state));
        vm.prank(USER);
        vm.deal(USER, STARTING_USER_BALANCE);
        raffle.enterRaffle{value: entranceFee}();
        currentBalance = currentBalance + entranceFee;
        numPlayers = numPlayers + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle_UpkeepNotNeeded.selector,
                currentBalance,
                numPlayers,
                state
            )
        );
        raffle.performUpkeep("");
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public {
        // Arrange
        vm.prank(USER);
        vm.deal(USER, STARTING_USER_BALANCE);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // record the logs of emitted events : for example check the line 139 of Raffle.sol
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        console2.log("Length of entries is: ", entries.length);
        console2.log("First entry is : ");
        console2.logBytes32(entries[0].topics[0]);
        bytes32 requestId = entries[1].topics[1];
        console2.log("Request ID is: ", uint256(requestId));

        // Assert
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        console2.log("Raffle state is: ", uint256(raffleState));
        // assert(uint256(raffleState) == 1);
        assert(uint256(requestId) > 0);
    }

    /* ------------------------------------------------------------
     *                   Fulfill Random Words
     * ------------------------------------------------------------
     */
    modifier raffleEnterd() {
        vm.prank(USER);
        vm.deal(USER, STARTING_USER_BALANCE);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }
    modifier skipFork() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }
    // This is Fuzz testing : and what actually it does is it will give random value to the function parameter. it depend upon the parameter : like we have already se the fuzz value to 1000
    function testRandomWordsAfterPerformUpkeep(
        uint256 value
    ) public raffleEnterd skipFork {
        // Arrange  // Act // Assert
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            value,
            address(raffle)
        );
    }

    function testFullfillrandomWordsPicksAWinnerResetsAndSendsMoney()
        public
        raffleEnterd skipFork
    {
        // Arrange
        uint256 startingIndex = 1;
        uint256 additionalEntrants = 5;
        for (
            uint256 i = startingIndex;
            i < startingIndex + additionalEntrants;
            i++
        ) {
            address player = address(uint160(i));
            hoax(player, STARTING_USER_BALANCE);
            raffle.enterRaffle{value: entranceFee}();
        }

        

        // Act
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entrie = vm.getRecordedLogs();
        bytes32 requestId = entrie[1].topics[1];
        console2.log("Request Id is  : ", uint256(requestId));
        console2.log("Contract balance is  : ", address(raffle).balance);

        console2.log("User balance : ", USER.balance);
        console2.log("user : ", raffle.getPlayer(0));
        
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        // Assert
        address recentWinner = raffle.getRecentWinner();
        console2.log("Recent winner is : ", recentWinner);
        console2.log("Winner balance is : ", recentWinner.balance);
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        assert(uint256(raffleState) == 0);
        console2.log("Raffle state is: ", uint256(raffleState));
    }
}
