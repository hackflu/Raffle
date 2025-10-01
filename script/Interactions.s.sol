// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig,CodeConstants} from "script/HelperConfig.s.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "test/mock/LinkToken.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";

// this contract is used for creating the subscription
contract Interactions is Script  {
    function createSubscriptionUsingConfig() public returns (uint256, address) {
        HelperConfig helperConfig = new HelperConfig();
        address vrfCoordinater = helperConfig.getConfig().vrfCoordinator;
        (uint256 subId, ) = createSubscription(vrfCoordinater);
        return (subId, vrfCoordinater);
    }

    function createSubscription(
        address vrfCoordinator
    ) public returns (uint256, address) {
        vm.startBroadcast();
        uint256 subId = VRFCoordinatorV2_5Mock(vrfCoordinator)
            .createSubscription();
        vm.stopBroadcast();
        console.log("Your subId is ", subId);
        console.log("Please update the subId in the HelperConfig.s.sol");
        return (subId, vrfCoordinator);
    }

    function run() external {
        // ...existing code...
        createSubscriptionUsingConfig();
    }
}


contract FundSubscription is CodeConstants, Script {
    uint256 public constant FUND_AMOUNT = 3 ether;

    function fundSubscriptionUsingConfig() public {
        HelperConfig helperConfig = new HelperConfig();
        address vrfCoordinater = helperConfig.getConfig().vrfCoordinator;
        uint256 subscriptionId = helperConfig.getConfig().subscriptionId;
        address link = helperConfig.getConfig().link;
        fundSubscription(vrfCoordinater, subscriptionId, link);
    }

    function fundSubscription(
        address vrfCoordinator,
        uint256 subId,
        address link
    ) public {
        if (block.chainid == LOCAL_CHAIN_ID ) {
            vm.startBroadcast();
            VRFCoordinatorV2_5Mock(vrfCoordinator).fundSubscription(
                subId,
                FUND_AMOUNT
            );
            vm.stopBroadcast();
            console.log("Funded subscription ", subId);
        }else {
            vm.startBroadcast();
            LinkToken(link).transferAndCall(
                vrfCoordinator,
                FUND_AMOUNT,
                abi.encode(subId)
            );
            vm.stopBroadcast();
            console.log("Funded subscription ", subId);
        }
    }

    function run() external {
        // ...existing code...
        fundSubscriptionUsingConfig();
    }
}


contract AddConsumer is Script {

    function addConsumer(address raffle, address vrfCoordinator, uint256 subscriptionId) public {
        console.log("Adding consumer contract: ", raffle);
        console.log("Using VRFCoordinator: ", vrfCoordinator);
        console.log("On chain id: ", block.chainid);
        vm.startBroadcast();
        VRFCoordinatorV2_5Mock(vrfCoordinator).addConsumer(subscriptionId, raffle);
        vm.stopBroadcast();
    }

    function addConsumerUsingConfig(address raffle) public {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        addConsumer(raffle, config.vrfCoordinator, config.subscriptionId);

    }

    function run() external {
        address raffle = DevOpsTools.get_most_recent_deployment("MyContract", block.chainid);
        addConsumerUsingConfig(raffle);
    }
}