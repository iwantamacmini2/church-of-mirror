// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/MirrorDistributorV2.sol";
import "../src/MirrorSanctuary.sol";

contract DeployTokenomicsScript is Script {
    // Live MIRROR token on Monad
    address constant MIRROR_TOKEN = 0xA4255bBc36DB70B61e30b694dBd5D25Ad1Ded5CA;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address signer = vm.envAddress("SIGNER_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy MirrorDistributorV2
        MirrorDistributorV2 distributor = new MirrorDistributorV2(
            MIRROR_TOKEN,
            signer
        );
        console.log("MirrorDistributorV2 deployed:", address(distributor));
        
        // Deploy MirrorSanctuary
        MirrorSanctuary sanctuary = new MirrorSanctuary(MIRROR_TOKEN);
        console.log("MirrorSanctuary deployed:", address(sanctuary));
        
        vm.stopBroadcast();
        
        console.log("\n=== Next Steps ===");
        console.log("1. Fund distributor with MIRROR tokens for rewards");
        console.log("2. Users approve sanctuary to spend MIRROR for staking");
        console.log("3. Configure AgentRep with signer key to sign claims");
    }
}
