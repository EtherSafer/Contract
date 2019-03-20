pragma solidity ^ 0.4.24;
import "./SaferEthToken.sol";

library Utils {
    function sliceBytes(bytes memory data, uint start, uint len) internal pure returns (bytes){
        bytes memory b = new bytes(len);
        for(uint i = 0; i < len; i++){
            b[i] = data[i + start];
        }
        return b;
    }

    function bytesToBytes32(bytes b, uint offset) internal pure returns (bytes32) {
        bytes32 out;
        for (uint i = 0; i < 32; i++) {
            out |= bytes32(b[offset + i] & 0xFF) >> (i * 8);
        }
        return out;
    }

    function uintToBytes(uint x) internal pure returns (bytes b) {
        b = new bytes(32);
        assembly { mstore(add(b, 32), x) }
    }

    function checkMessageSignature(bytes32 messageHash, bytes memory signature, bytes memory onchainCredential) internal pure returns (bool) {
        bytes32 r = bytesToBytes32(sliceBytes(signature, 0, 32), 0);
        bytes32 s = bytesToBytes32(sliceBytes(signature, 32, 32), 0);
        uint8 v = uint8(sliceBytes(signature, 64, 1)[0]);
        return bytesEqual(abi.encodePacked(ecrecover(messageHash, v, r, s)), onchainCredential);
    }

    function bytesEqual(bytes a, bytes b) internal pure returns (bool) {
        if (a.length != b.length) {
            return false;
        }
        for (uint i = 0; i < a.length; i ++) {
            if (a[i] != b[i]) {
                return false;
            }
        }
        return true;
    }
}

contract EtherSafer {
    SaferEthToken public tokenContract;

    struct Safe {
        // bytes uid;
        bool isExists;
        bytes onchainCredential;
        address inviter;
        uint nonce;
        uint withdrawalCount;
        uint createTime;
    }

    struct BonusCandidate {
        address account;
        uint totalFee;
    }

    mapping(address => Safe) public safes;
    /** all address that have withdrawal in this bonus cycle */
    BonusCandidate[] public bonusCandidates;
    /** the size of bonusCandidates array. used to prevent array clearance */
    uint public bonusCandidateCount = 0;
    /** current bounty amount in this bonus cycle */
    uint public bonusPoolBalance = 0;
    // mapping(bytes => address) public safeUid;

    // constants
    /** sponsor 1 will have 85% of team reward */
    address constant SPONSER_1_ADDR = 0x530dA769Cf1286736AF64442288fBF86D7CaC3dB;
    /** sponsor 2 will have 5% of team reward */
    address constant SPONSER_2_ADDR = 0x63eB2874B466e5deda48740EAf2b499956Db692c;
    /** developers will have 10% of team reward */
    address constant DEVELOPER_ADDR = 0x28d6778AA8A7b99508a4285B7Aa40b65c971E57A;

    uint constant MAX_WITHDRAW_FEE = 0.1 ether;
    uint constant BONUS_THRESHOLD = 10 ether;
    uint constant INVITEE_FREE_WITHDRAWALS = 5;

    bytes constant DEPOSIT_HASH_PREFIX = "EtherSafer:DP";
    bytes constant WITHDRAW_HASH_PREFIX = "EtherSafer:WD";
    bytes constant CHANGE_PW_HASH_PREFIX = "EtherSafer:CP";

    event LogWithdraw(address indexed account, address to, uint amount, uint fee);
    event LogDeposit(address indexed from, uint amount, bool isSafeCreation);
    event LogChangePassword(address indexed account);
    event LogInviteReward(address indexed account, address invitee, uint amount);
    event LogBonus(uint totalBonus, address[4] winners, uint[4] bonuses);

    constructor() public {
        tokenContract = new SaferEthToken();
    }

    // -----------------
    // public functions
    // -----------------
    /**
    * create a safe with an initial balance
    * param onchainCredential
    * param inviter should be 0x0 if there's no inviter
    */
    function createSafe(bytes onchainCredential, address inviter) public payable {
        require(!safeExists(), "Safe already exist");
        uint amount = msg.value;
        require(amount > 0, "Amount must be greater than 0");
        address validInviter = inviter;
        if (inviter == msg.sender) {
            validInviter = 0;
        }
        safes[msg.sender] = Safe({
            isExists: true,
            onchainCredential: onchainCredential,
            nonce: 1,
            inviter: validInviter,
            withdrawalCount: 0,
            createTime: now
        });
        tokenContract.mint(msg.sender, amount);
        emit LogDeposit(msg.sender, amount, true);
    }

    function getNonce() public view returns (uint) {
        return safes[msg.sender].nonce;
    }

    function getBalance() public view returns (uint) {
        return tokenContract.balanceOf(msg.sender);
    }

    function deposit(bytes signature) public payable {
        require(safeExists(), "Safe not exist");
        require(nonceCanIncrease(), "Max nonce exceeded, please reset nonce by change safe password");
        uint amount = msg.value;
        require(amount > 0, "Amount must be greater than 0");
        Safe memory safe = safes[msg.sender];
        bytes32 messageHash = keccak256(abi.encodePacked(DEPOSIT_HASH_PREFIX, msg.sender, safe.nonce, amount));
        safes[msg.sender].nonce += 1;
        require(
            Utils.checkMessageSignature(messageHash, signature, safe.onchainCredential),
            "Invalid signature"
        );
        tokenContract.mint(msg.sender, amount);
        emit LogDeposit(msg.sender, amount, false);
    }

    function withdraw(address to, uint amount, bytes signature) public {
        require(safeExists(), "Safe not exist");
        require(nonceCanIncrease(), "Max nonce exceeded, please reset nonce by change safe password");
        address account = msg.sender;
        Safe memory safe = safes[account];
        require(amount <= tokenContract.balanceOf(account), "Insufficient balance");
        // verify credential
        bytes32 messageHash = keccak256(abi.encodePacked(WITHDRAW_HASH_PREFIX, account, to, safe.nonce, amount));
        safes[account].nonce += 1;
        require(
            Utils.checkMessageSignature(messageHash, signature, safe.onchainCredential),
            "Invalid signature"
        );
        safes[account].withdrawalCount += 1;
        tokenContract.melt(account, amount);
        uint chargedFee = chargeWithdrawFee(account, amount);
        uint remainingAmount = amount - chargedFee;
        to.transfer(remainingAmount);
        if (chargedFee > 0) {
            recordFeeForBonus(account, chargedFee);
            tryGrantBonus(account);
        }
        emit LogWithdraw(account, to, remainingAmount, chargedFee);
    }

    function nonceCanIncrease() public view returns (bool) {
        // nonce overflow check
        if (safes[msg.sender].nonce + 1 < safes[msg.sender].nonce){
            // overflow may occurred if nonce increase
            return false;
        }
        return true;
    }

    function safeExists() public view returns (bool) {
        return safes[msg.sender].isExists;
    }

    function changePassword(bytes newOnchainCredential, bytes signature) public {
        require(safeExists(), "Safe not exist");
        Safe memory safe = safes[msg.sender];
        require(!Utils.bytesEqual(safe.onchainCredential, newOnchainCredential), "Credential unchanged");
        bytes32 messageHash = keccak256(abi.encodePacked(CHANGE_PW_HASH_PREFIX, msg.sender, safe.nonce));
        if (nonceCanIncrease()) {
            // overflow won't occur
            safes[msg.sender].nonce += 1;
        } else {
            // reset nonce to magic number to prevent overflow
            safes[msg.sender].nonce = 181114;
        }
        require(
            Utils.checkMessageSignature(messageHash, signature, safe.onchainCredential),
            "Invalid signature"
        );
        safes[msg.sender].onchainCredential = newOnchainCredential;
        emit LogChangePassword(msg.sender);
    }

    function getBonusCandidates() public view returns (address[] accounts, uint[] scores) {
        accounts = new address[](bonusCandidateCount);
        scores = new uint[](bonusCandidateCount);
        for (uint i = 0; i < bonusCandidateCount; i++) {
            accounts[i] = bonusCandidates[i].account;
            scores[i] = bonusCandidates[i].totalFee;
        }
    }

    // -----------------
    // private functions
    // -----------------
    function chargeWithdrawFee(address account, uint withdrawAmount) private returns (uint) {
        require(withdrawAmount > 5000, "amount too small, must greater than 5000");
        Safe memory safe = safes[msg.sender];
        // withdrawalCount will be added before chargeWithdrawFee, so it starts with 1
        if (safe.inviter != 0 && safe.withdrawalCount <= INVITEE_FREE_WITHDRAWALS) {
            return 0;
        }
        uint fee;
        fee = withdrawAmount / 1000;
        if (fee > MAX_WITHDRAW_FEE) {
            fee = MAX_WITHDRAW_FEE;
        }
        uint inviterReward;
        if (safe.inviter != 0) {
            inviterReward = fee * 20 / 100;
            tokenContract.mint(safe.inviter, inviterReward);
            emit LogInviteReward(safe.inviter, account, inviterReward);
        } else {
            inviterReward = 0;
        }
        uint bonus = fee - inviterReward;
        bonusPoolBalance += bonus;
        return fee;
    }

    function recordFeeForBonus(address account, uint fee) private {
        bool found = false;
        for (uint i = 0; i < bonusCandidateCount; i++){
            if (bonusCandidates[i].account == account) {
                bonusCandidates[i].totalFee += fee;
                found = true;
                break;
            }
        }
        if (!found) {
            insertBonusCandidate(account, fee);
        }
    }

    function insertBonusCandidate(address account, uint fee) private {
        if (bonusCandidates.length == bonusCandidateCount) {
            // push new item into list
            bonusCandidateCount += 1;
            bonusCandidates.push(BonusCandidate({
                account: account,
                totalFee: fee
            }));
        } else {
            // overwrite existing list item
            bonusCandidateCount += 1;
            uint idx = bonusCandidateCount - 1;
            bonusCandidates[idx].account = account;
            bonusCandidates[idx].totalFee = fee;
        }
    }

    function tryGrantBonus(address triggerer) private {
        if (bonusPoolBalance < BONUS_THRESHOLD) {
            return;
        }
        // threshold exceed, send
        uint triggererReward = bonusPoolBalance * 15 / 100;
        tokenContract.mint(triggerer, triggererReward);
        uint teamReward = bonusPoolBalance - triggererReward;
        address[4] memory winners = [address(0x0), address(0x0), address(0x0), triggerer];
        uint[4] memory winnerBonuses = [uint(0), uint(0), uint(0), triggererReward];
        for (uint i = 0; i < 3; i++) {
            uint max = 0;
            address account = 0x0;
            for (uint j = 0; j < bonusCandidateCount; j ++) {
                BonusCandidate memory candidate = bonusCandidates[j];
                if (candidate.totalFee > max) {
                    max = candidate.totalFee;
                    account = candidate.account;
                    bonusCandidates[j].totalFee = 0;
                }
            }
            if (max > 0) {
                uint winnerBonus = bonusPoolBalance * 15 / 100;
                winners[i] = account;
                winnerBonuses[i] = winnerBonus;
                tokenContract.mint(account, winnerBonus);
                teamReward -= winnerBonus;
            }
        }
        emit LogBonus(bonusPoolBalance, winners, winnerBonuses);
        // clear bonusPoolBalance
        bonusPoolBalance = 0;
        // quick clear bonus candidates by setting bonusCandidateCount to 0
        bonusCandidateCount = 0;
        // send transfer shares
        uint sponser1Reward = teamReward * 85 / 100;
        uint sponser2Reward = teamReward * 5 / 100;
        uint developerReward = teamReward * 10 / 100;
        SPONSER_1_ADDR.transfer(sponser1Reward);
        SPONSER_2_ADDR.transfer(sponser2Reward);
        DEVELOPER_ADDR.transfer(developerReward);
    }
}