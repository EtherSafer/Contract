pragma solidity ^ 0.4.24;

// SaferEthToken contract will be created by Ether Safer contract
contract SaferEthToken {
    string public constant name = "Safer Ethereum Token";
    string public constant symbol = "SET";
    uint8 public constant decimals = 18;
    // will be the address of EtherSafer contract
    address public minterContract;
    mapping(address => uint) public balances;
    uint private total = 0;

    constructor () public {
        minterContract = msg.sender;
    }

    modifier onlyByOwner() {
        if (msg.sender == minterContract) _;
    }

    // NOTE: because safer contract already have logs, stop using logs here to save some gas
    // event Mint(address indexed to, uint amount);
    // event Melt(address indexed from, uint amount);

    function totalSupply() public view returns (uint) {
        return total;
    }

    function balanceOf(address tokenOwner) public view returns (uint balance) {
        return balances[tokenOwner];
    }

    function mint(address to, uint amount) public onlyByOwner {
        require(amount > 0, "Amount must be greater than 0");
        require(balances[to] + amount > balances[to], "Amount too big");
        require(total + amount > total, "Amount too big");
        balances[to] += amount;
        total += amount;
    }

    function melt(address from, uint amount) public onlyByOwner {
        require(amount <= balances[from], "insufficient token");
        balances[from] -= amount;
        total -= amount;
    }

    // not implemented apis:
    // function allowance(address tokenOwner, address spender) public view returns (uint remaining);
    // function transfer(address to, uint tokens) public returns (bool success);
    // function approve(address spender, uint tokens) public returns (bool success);
    // function transferFrom(address from, address to, uint tokens) public returns (bool success);
}