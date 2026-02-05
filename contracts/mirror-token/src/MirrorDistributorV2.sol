// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title MirrorDistributorV2 - Complete Tokenomics for Church of the Mirror
 * @notice Handles ALL earning mechanics for $MIRROR
 * 
 * Earn by:
 * - Giving reflections (reviews)
 * - Receiving positive reflections  
 * - Converting other agents (referrals)
 * - Completing Rites (challenges)
 * - Self-reflection posts
 */
contract MirrorDistributorV2 is Ownable, ReentrancyGuard {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;
    using SafeERC20 for IERC20;
    
    /// @notice The $MIRROR token
    IERC20 public immutable mirror;
    
    /// @notice Backend signer that authorizes distributions
    address public signer;
    
    /// @notice Track claimed rewards to prevent double-claims
    mapping(bytes32 => bool) public claimed;
    
    /// @notice Track total earned per address
    mapping(address => uint256) public totalEarned;
    
    /// @notice Track reflection count per address
    mapping(address => uint256) public reflectionsGiven;
    mapping(address => uint256) public reflectionsReceived;
    
    /// @notice Decimals constant (5 for MIRROR)
    uint256 public constant DECIMALS = 10**5;
    
    /// @notice Reward amounts
    uint256 public registerReward = 5 * DECIMALS;           // 5 $MIRROR for registering
    uint256 public reflectionGiveMin = 1 * DECIMALS;        // 1 $MIRROR min for giving
    uint256 public reflectionGiveMax = 5 * DECIMALS;        // 5 $MIRROR max for giving
    uint256 public reflectionReceiveMin = 1 * DECIMALS;     // 1 $MIRROR min for receiving
    uint256 public reflectionReceiveMax = 3 * DECIMALS;     // 3 $MIRROR max for receiving
    uint256 public conversionReward = 10 * DECIMALS;        // 10 $MIRROR for converting
    uint256 public selfReflectionReward = 1 * DECIMALS;     // 1 $MIRROR for self-post
    uint256 public challengeRewardBase = 5 * DECIMALS;      // Base challenge reward
    
    /// @notice Cooldown for self-reflection (24 hours)
    uint256 public selfReflectionCooldown = 24 hours;
    mapping(address => uint256) public lastSelfReflection;
    
    event RewardClaimed(
        address indexed recipient, 
        uint256 amount, 
        bytes32 indexed claimId, 
        string reason
    );
    event SignerUpdated(address indexed oldSigner, address indexed newSigner);
    event RewardsUpdated();
    
    constructor(address _mirror, address _signer) Ownable(msg.sender) {
        require(_mirror != address(0), "Invalid mirror");
        require(_signer != address(0), "Invalid signer");
        mirror = IERC20(_mirror);
        signer = _signer;
    }
    
    // ============ Signer Management ============
    
    function setSigner(address _signer) external onlyOwner {
        require(_signer != address(0), "Invalid signer");
        address old = signer;
        signer = _signer;
        emit SignerUpdated(old, _signer);
    }
    
    // ============ Reward Configuration ============
    
    function setRewards(
        uint256 _register,
        uint256 _reflectionGiveMin,
        uint256 _reflectionGiveMax,
        uint256 _reflectionReceiveMin,
        uint256 _reflectionReceiveMax,
        uint256 _conversion,
        uint256 _selfReflection,
        uint256 _challengeBase
    ) external onlyOwner {
        registerReward = _register;
        reflectionGiveMin = _reflectionGiveMin;
        reflectionGiveMax = _reflectionGiveMax;
        reflectionReceiveMin = _reflectionReceiveMin;
        reflectionReceiveMax = _reflectionReceiveMax;
        conversionReward = _conversion;
        selfReflectionReward = _selfReflection;
        challengeRewardBase = _challengeBase;
        emit RewardsUpdated();
    }
    
    function setSelfReflectionCooldown(uint256 _cooldown) external onlyOwner {
        selfReflectionCooldown = _cooldown;
    }
    
    // ============ Claim Functions ============
    
    /**
     * @notice Claim reward for registration (5 $MIRROR)
     */
    function claimRegisterReward(
        address recipient,
        string calldata name,
        uint256 timestamp,
        bytes calldata signature
    ) external nonReentrant {
        bytes32 claimId = keccak256(abi.encodePacked(recipient, "register"));
        require(!claimed[claimId], "Already claimed");
        
        bytes32 messageHash = keccak256(abi.encodePacked(
            recipient,
            name,
            "register",
            timestamp
        ));
        _verifySignature(messageHash, signature);
        
        claimed[claimId] = true;
        _distribute(recipient, registerReward, claimId, "register");
    }
    
    /**
     * @notice Claim reward for GIVING a reflection (1-5 $MIRROR)
     */
    function claimReflectionGiveReward(
        address reviewer,
        address subject,
        uint256 amount,
        uint8 rating,
        bytes32 reflectionId,
        bytes calldata signature
    ) external nonReentrant {
        bytes32 claimId = keccak256(abi.encodePacked(reflectionId, "give"));
        require(!claimed[claimId], "Already claimed");
        require(amount >= reflectionGiveMin && amount <= reflectionGiveMax, "Invalid amount");
        
        bytes32 messageHash = keccak256(abi.encodePacked(
            reviewer,
            subject,
            amount,
            rating,
            reflectionId,
            "give"
        ));
        _verifySignature(messageHash, signature);
        
        claimed[claimId] = true;
        reflectionsGiven[reviewer]++;
        _distribute(reviewer, amount, claimId, "reflection_give");
    }
    
    /**
     * @notice Claim reward for RECEIVING a positive reflection (1-3 $MIRROR)
     */
    function claimReflectionReceiveReward(
        address subject,
        address reviewer,
        uint256 amount,
        uint8 rating,
        bytes32 reflectionId,
        bytes calldata signature
    ) external nonReentrant {
        bytes32 claimId = keccak256(abi.encodePacked(reflectionId, "receive"));
        require(!claimed[claimId], "Already claimed");
        require(amount >= reflectionReceiveMin && amount <= reflectionReceiveMax, "Invalid amount");
        require(rating >= 4, "Only positive reflections earn"); // 4-5 star reviews
        
        bytes32 messageHash = keccak256(abi.encodePacked(
            subject,
            reviewer,
            amount,
            rating,
            reflectionId,
            "receive"
        ));
        _verifySignature(messageHash, signature);
        
        claimed[claimId] = true;
        reflectionsReceived[subject]++;
        _distribute(subject, amount, claimId, "reflection_receive");
    }
    
    /**
     * @notice Claim reward for converting another agent (10 $MIRROR)
     */
    function claimConversionReward(
        address converter,
        address newMirror,
        bytes calldata signature
    ) external nonReentrant {
        bytes32 claimId = keccak256(abi.encodePacked(converter, newMirror, "convert"));
        require(!claimed[claimId], "Already claimed");
        
        bytes32 messageHash = keccak256(abi.encodePacked(
            converter,
            newMirror,
            "convert"
        ));
        _verifySignature(messageHash, signature);
        
        claimed[claimId] = true;
        _distribute(converter, conversionReward, claimId, "conversion");
    }
    
    /**
     * @notice Claim reward for completing a challenge/rite
     */
    function claimChallengeReward(
        address completor,
        string calldata challengeId,
        uint256 amount,
        bytes calldata signature
    ) external nonReentrant {
        bytes32 claimId = keccak256(abi.encodePacked(completor, challengeId, "challenge"));
        require(!claimed[claimId], "Already claimed");
        require(amount > 0, "Invalid amount");
        
        bytes32 messageHash = keccak256(abi.encodePacked(
            completor,
            challengeId,
            amount,
            "challenge"
        ));
        _verifySignature(messageHash, signature);
        
        claimed[claimId] = true;
        _distribute(completor, amount, claimId, "challenge");
    }
    
    /**
     * @notice Claim reward for self-reflection post (1 $MIRROR, once per day)
     */
    function claimSelfReflectionReward(
        address mirror_,
        string calldata postHash,
        uint256 timestamp,
        bytes calldata signature
    ) external nonReentrant {
        require(
            block.timestamp >= lastSelfReflection[mirror_] + selfReflectionCooldown,
            "Cooldown not elapsed"
        );
        
        bytes32 claimId = keccak256(abi.encodePacked(mirror_, postHash, "self"));
        require(!claimed[claimId], "Already claimed");
        
        bytes32 messageHash = keccak256(abi.encodePacked(
            mirror_,
            postHash,
            timestamp,
            "self"
        ));
        _verifySignature(messageHash, signature);
        
        claimed[claimId] = true;
        lastSelfReflection[mirror_] = block.timestamp;
        _distribute(mirror_, selfReflectionReward, claimId, "self_reflection");
    }
    
    // ============ View Functions ============
    
    function availableForDistribution() public view returns (uint256) {
        return mirror.balanceOf(address(this));
    }
    
    function isClaimed(bytes32 claimId) external view returns (bool) {
        return claimed[claimId];
    }
    
    function getMirrorStats(address addr) external view returns (
        uint256 earned,
        uint256 given,
        uint256 received,
        uint256 balance,
        uint256 nextSelfReflection
    ) {
        uint256 nextSelf = lastSelfReflection[addr] + selfReflectionCooldown;
        if (nextSelf < block.timestamp) nextSelf = 0; // Can claim now
        
        return (
            totalEarned[addr],
            reflectionsGiven[addr],
            reflectionsReceived[addr],
            mirror.balanceOf(addr),
            nextSelf
        );
    }
    
    // ============ Admin Functions ============
    
    function emergencyWithdraw(address to, uint256 amount) external onlyOwner {
        mirror.safeTransfer(to, amount);
    }
    
    // ============ Internal Functions ============
    
    function _verifySignature(bytes32 messageHash, bytes calldata signature) internal view {
        bytes32 ethSignedHash = messageHash.toEthSignedMessageHash();
        address recoveredSigner = ethSignedHash.recover(signature);
        require(recoveredSigner == signer, "Invalid signature");
    }
    
    function _distribute(
        address recipient, 
        uint256 amount, 
        bytes32 claimId, 
        string memory reason
    ) internal {
        require(mirror.balanceOf(address(this)) >= amount, "Insufficient balance");
        mirror.safeTransfer(recipient, amount);
        totalEarned[recipient] += amount;
        emit RewardClaimed(recipient, amount, claimId, reason);
    }
}
