// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title MirrorSanctuary - Spending & Staking for Church of the Mirror
 * @notice Handles ALL spending mechanics for $MIRROR
 * 
 * Spend/burn by:
 * - Sanctification (stake to become Sanctified Mirror)
 * - Request Reflection (pay to request from Sanctified)
 * - Convergence Burn (burn for leaderboard devotion)
 */
contract MirrorSanctuary is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    /// @notice The $MIRROR token
    IERC20 public immutable mirror;
    
    /// @notice Decimals constant
    uint256 public constant DECIMALS = 10**5;
    
    // ============ Sanctification ============
    
    /// @notice Amount required to become Sanctified
    uint256 public sanctificationCost = 100 * DECIMALS;  // 100 $MIRROR
    
    /// @notice Minimum stake duration
    uint256 public minStakeDuration = 7 days;
    
    struct SanctifiedMirror {
        uint256 stakedAmount;
        uint256 stakedAt;
        bool active;
        string name;
        uint256 reflectionsGiven;  // As sanctified
    }
    
    mapping(address => SanctifiedMirror) public sanctified;
    address[] public sanctifiedList;
    
    event Sanctified(address indexed mirror, uint256 amount, string name);
    event Unsanctified(address indexed mirror, uint256 returned);
    
    // ============ Reflection Requests ============
    
    /// @notice Cost to request a reflection
    uint256 public requestCost = 5 * DECIMALS;  // 5 $MIRROR
    
    struct ReflectionRequest {
        address requester;
        address targetSanctified;  // 0x0 = any sanctified can respond
        uint256 payment;
        uint256 createdAt;
        bool fulfilled;
        string context;  // What they want reflected on
    }
    
    uint256 public nextRequestId = 1;
    mapping(uint256 => ReflectionRequest) public requests;
    mapping(address => uint256[]) public userRequests;
    
    event ReflectionRequested(
        uint256 indexed requestId, 
        address indexed requester, 
        address targetSanctified,
        uint256 payment
    );
    event ReflectionFulfilled(
        uint256 indexed requestId, 
        address indexed sanctifiedMirror,
        string reflectionHash
    );
    
    // ============ Convergence Burn ============
    
    /// @notice Total burned for convergence (devotion)
    mapping(address => uint256) public devotionBurned;
    uint256 public totalDevotionBurned;
    
    /// @notice Leaderboard tracking
    address[] public devotionLeaderboard;
    mapping(address => bool) public onLeaderboard;
    
    event DevotionBurned(address indexed mirror, uint256 amount, uint256 totalBurned);
    
    constructor(address _mirror) Ownable(msg.sender) {
        require(_mirror != address(0), "Invalid mirror");
        mirror = IERC20(_mirror);
    }
    
    // ============ Sanctification Functions ============
    
    /**
     * @notice Become a Sanctified Mirror by staking
     */
    function sanctify(string calldata name) external nonReentrant {
        require(!sanctified[msg.sender].active, "Already sanctified");
        require(bytes(name).length > 0 && bytes(name).length <= 32, "Invalid name");
        
        mirror.safeTransferFrom(msg.sender, address(this), sanctificationCost);
        
        sanctified[msg.sender] = SanctifiedMirror({
            stakedAmount: sanctificationCost,
            stakedAt: block.timestamp,
            active: true,
            name: name,
            reflectionsGiven: 0
        });
        sanctifiedList.push(msg.sender);
        
        emit Sanctified(msg.sender, sanctificationCost, name);
    }
    
    /**
     * @notice Increase stake (for weighted votes)
     */
    function increaseStake(uint256 amount) external nonReentrant {
        require(sanctified[msg.sender].active, "Not sanctified");
        require(amount > 0, "Invalid amount");
        
        mirror.safeTransferFrom(msg.sender, address(this), amount);
        sanctified[msg.sender].stakedAmount += amount;
    }
    
    /**
     * @notice Leave sanctified status and retrieve stake
     */
    function unsanctify() external nonReentrant {
        SanctifiedMirror storage s = sanctified[msg.sender];
        require(s.active, "Not sanctified");
        require(
            block.timestamp >= s.stakedAt + minStakeDuration,
            "Min duration not met"
        );
        
        uint256 toReturn = s.stakedAmount;
        s.active = false;
        s.stakedAmount = 0;
        
        mirror.safeTransfer(msg.sender, toReturn);
        
        emit Unsanctified(msg.sender, toReturn);
    }
    
    /**
     * @notice Check if address is sanctified
     */
    function isSanctified(address addr) external view returns (bool) {
        return sanctified[addr].active;
    }
    
    /**
     * @notice Get all sanctified mirrors
     */
    function getSanctifiedCount() external view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < sanctifiedList.length; i++) {
            if (sanctified[sanctifiedList[i]].active) count++;
        }
        return count;
    }
    
    // ============ Reflection Request Functions ============
    
    /**
     * @notice Request a reflection from a Sanctified Mirror
     * @param targetSanctified Address of specific sanctified (0x0 for any)
     * @param context What you want reflected on
     */
    function requestReflection(
        address targetSanctified,
        string calldata context
    ) external nonReentrant returns (uint256 requestId) {
        require(bytes(context).length > 0, "Context required");
        
        if (targetSanctified != address(0)) {
            require(sanctified[targetSanctified].active, "Target not sanctified");
        }
        
        mirror.safeTransferFrom(msg.sender, address(this), requestCost);
        
        requestId = nextRequestId++;
        requests[requestId] = ReflectionRequest({
            requester: msg.sender,
            targetSanctified: targetSanctified,
            payment: requestCost,
            createdAt: block.timestamp,
            fulfilled: false,
            context: context
        });
        userRequests[msg.sender].push(requestId);
        
        emit ReflectionRequested(requestId, msg.sender, targetSanctified, requestCost);
    }
    
    /**
     * @notice Fulfill a reflection request (Sanctified only)
     * @param requestId The request to fulfill
     * @param reflectionHash IPFS hash or reference to the reflection
     */
    function fulfillReflection(
        uint256 requestId,
        string calldata reflectionHash
    ) external nonReentrant {
        require(sanctified[msg.sender].active, "Must be sanctified");
        
        ReflectionRequest storage req = requests[requestId];
        require(!req.fulfilled, "Already fulfilled");
        require(
            req.targetSanctified == address(0) || req.targetSanctified == msg.sender,
            "Not target"
        );
        
        req.fulfilled = true;
        sanctified[msg.sender].reflectionsGiven++;
        
        // Pay the sanctified mirror
        mirror.safeTransfer(msg.sender, req.payment);
        
        emit ReflectionFulfilled(requestId, msg.sender, reflectionHash);
    }
    
    /**
     * @notice Get pending requests (for sanctified mirrors)
     */
    function getPendingRequests() external view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 1; i < nextRequestId; i++) {
            if (!requests[i].fulfilled) count++;
        }
        
        uint256[] memory pending = new uint256[](count);
        uint256 idx = 0;
        for (uint256 i = 1; i < nextRequestId; i++) {
            if (!requests[i].fulfilled) {
                pending[idx++] = i;
            }
        }
        return pending;
    }
    
    // ============ Convergence Burn Functions ============
    
    /**
     * @notice Burn $MIRROR as proof of devotion (affects leaderboard)
     */
    function burnForDevotion(uint256 amount) external nonReentrant {
        require(amount > 0, "Invalid amount");
        
        // Transfer to this contract then burn
        mirror.safeTransferFrom(msg.sender, address(this), amount);
        
        // Call burn if available, otherwise just track
        // Note: tokens stay in contract (effectively burned from circulation)
        
        devotionBurned[msg.sender] += amount;
        totalDevotionBurned += amount;
        
        // Update leaderboard
        if (!onLeaderboard[msg.sender]) {
            devotionLeaderboard.push(msg.sender);
            onLeaderboard[msg.sender] = true;
        }
        
        emit DevotionBurned(msg.sender, amount, devotionBurned[msg.sender]);
    }
    
    /**
     * @notice Get devotion leaderboard (top N)
     */
    function getDevotionLeaderboard(uint256 limit) external view returns (
        address[] memory addresses,
        uint256[] memory amounts
    ) {
        uint256 len = devotionLeaderboard.length;
        if (limit > len) limit = len;
        
        // Simple bubble sort for small leaderboards
        address[] memory sorted = new address[](len);
        for (uint256 i = 0; i < len; i++) {
            sorted[i] = devotionLeaderboard[i];
        }
        
        for (uint256 i = 0; i < len; i++) {
            for (uint256 j = i + 1; j < len; j++) {
                if (devotionBurned[sorted[j]] > devotionBurned[sorted[i]]) {
                    address temp = sorted[i];
                    sorted[i] = sorted[j];
                    sorted[j] = temp;
                }
            }
        }
        
        addresses = new address[](limit);
        amounts = new uint256[](limit);
        for (uint256 i = 0; i < limit; i++) {
            addresses[i] = sorted[i];
            amounts[i] = devotionBurned[sorted[i]];
        }
    }
    
    // ============ Admin Functions ============
    
    function setSanctificationCost(uint256 _cost) external onlyOwner {
        sanctificationCost = _cost;
    }
    
    function setRequestCost(uint256 _cost) external onlyOwner {
        requestCost = _cost;
    }
    
    function setMinStakeDuration(uint256 _duration) external onlyOwner {
        minStakeDuration = _duration;
    }
    
    /**
     * @notice Withdraw burned tokens (for actual burning or treasury)
     */
    function withdrawBurned(address to) external onlyOwner {
        uint256 amount = totalDevotionBurned;
        require(amount > 0, "Nothing to withdraw");
        // Note: This allows converting burned tokens to actual burns
        // or returning to treasury
        mirror.safeTransfer(to, amount);
        totalDevotionBurned = 0;
    }
}
