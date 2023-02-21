// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.17;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "contracts/libraries/SafeMath8.sol";
import "contracts/interfaces/IOracle.sol";
import "contracts/libraries/Operator.sol";
import "contracts/interfaces/IUniswapV2Factory.sol";
import "contracts/interfaces/IUniswapV2Pair.sol";
import "contracts/interfaces/IUniswapV2Router02.sol";

contract AiOMB is ERC20Burnable, Operator {

    using SafeMath8 for uint8;
    using SafeMath for uint256;

    // constants
    uint256 public constant POOL_DISTRIBUTION = 12500 ether;
    uint256 public constant BOT_DISTRIBUTION = 6250 ether;
    uint256 public constant PRESALE_DISTRIBUTION = 25000 ether;

    // Have the rewards been distributed to the pools
    bool public rewardPoolDistributed = false;

    //mutables
    address public oracle;
    address public taxCollectorAddress;
    address public admin;
    address public PairAiShare;
    bool public started;
    
    // immutables
    IUniswapV2Router02 public immutable uniswapV2Router;
    address public immutable BOND;
    IERC20 public immutable USDC;
    IERC20 public immutable WETH;
    address public immutable PairWETH;
    address public immutable PairUSDC;
    address public immutable genesisAddress;
    address public immutable boardroom;
    address public immutable treasury;
    address public immutable shareRewardPool;

    // whitelist fee and whitelist bots
	mapping(address => bool) public whitelist;

    // tax rate
    uint256 public taxRate;
    
    // modifiers
    modifier onlyTaxCollector() {
        require(taxCollectorAddress == _msgSender(), "caller is not the taxCollector");
        _;
    }

    modifier onlyAdmin() {
         require(admin == _msgSender(), "You are not the admin");  
        _;
    }

    function start() external onlyOperator() {
        require(!started,"already started");
        uint256 balanceAIO = balanceOf(address(this));
        uint256 balanceWETH = WETH.balanceOf(address(this));
        _approve(address(this), address(uniswapV2Router), balanceAIO);
        WETH.approve(address(uniswapV2Router), WETH.balanceOf(address(this)));
        uniswapV2Router.addLiquidity(address(this), address(WETH), balanceAIO, balanceWETH, balanceAIO, balanceWETH, msg.sender, block.timestamp);
        started = true;
    }

    constructor(address _BOND, address _router, address _genesisAddress, address _boardroom, address _treasury, address _shareRewardPool, address _USDC) ERC20("AiOMB", "AIO") {
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(_router);
        _mint(address(this), 1 ether);

        // set router
        uniswapV2Router = _uniswapV2Router;

        WETH = IERC20(_uniswapV2Router.WETH());
        USDC = IERC20(_USDC);
        
        // Create pairs
        PairWETH = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        PairUSDC = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), address(USDC));
        
        // set admin and tax collector role
        admin = msg.sender;
        taxCollectorAddress = msg.sender;

        // set core contracts
        BOND = _BOND;
        genesisAddress = _genesisAddress;
        treasury = _treasury;
        boardroom = _boardroom;
        shareRewardPool = _shareRewardPool;

        // whitelist core contracts from fee
        whitelist[genesisAddress] = true;
        whitelist[boardroom] = true;
        whitelist[treasury] = true;
        whitelist[shareRewardPool] = true;

        // distribute the rewards
        rewardPoolDistributed = true;
        _mint(_genesisAddress, POOL_DISTRIBUTION);
        _mint(msg.sender, BOT_DISTRIBUTION);   
        _mint(msg.sender, PRESALE_DISTRIBUTION);
        
    }

    function _getPrice() internal view returns (uint256 _Price) {
        try IOracle(oracle).consult(address(this), 1e18) returns (uint144 _price) {
            return uint256(_price);
        } catch {
            revert("failed to fetch token price from Oracle");
        }
    }

    function isContract(address _addr) private view returns (bool){
        uint32 size;
        assembly {
        size := extcodesize(_addr)
        }
        return (size > 0);
    }

    // set whitelist
    function setWhiteList(address _WhiteList) public onlyAdmin {
        require(isContract(_WhiteList) == true, "only contracts can be whitelisted");
        require(address(uniswapV2Router) != _WhiteList, "set tax to 0 if you want to remove fee from trading");
        require(PairWETH != _WhiteList, "set tax to 0 if you want to remove fee from trading");
        require(PairUSDC != _WhiteList, "set tax to 0 if you want to remove fee from trading");
        require(PairAiShare != address(0), "set PairAiShare first");
        require(PairAiShare != _WhiteList, "set tax to 0 if you want to remove fee from trading");
		whitelist[_WhiteList] = true;
    }

    // setPairAiShare function gets called from share token
    function setPairAiShare(address _pairAiShare) public onlyAdmin {
        require(PairAiShare == address(0), "already set, only one");
        PairAiShare = _pairAiShare;
    }

    function setAdmin(address _admin) public onlyAdmin {
        admin = _admin;
    }

    function setOracle(address _oracle) public onlyAdmin {
        require(_oracle != address(0), "oracle address cannot be 0 address");
        oracle = _oracle;
    }


    function setTaxCollectorAddress(address _taxCollectorAddress) public onlyTaxCollector {
        require(_taxCollectorAddress != address(0), "taxCollectorAddress address cannot be 0 address");
        taxCollectorAddress = _taxCollectorAddress;
    }


    function setTaxRate(uint256 _taxRate) onlyTaxCollector public {
        require(_taxRate <= 5 ,"taxrate has to be between 0% and 5%" );
        taxRate = _taxRate;
    }

    function mint(address recipient_, uint256 amount_) public onlyOperator returns (bool) {
        uint256 balanceBefore = balanceOf(recipient_);
        _mint(recipient_, amount_);
        uint256 balanceAfter = balanceOf(recipient_);
        return balanceAfter > balanceBefore;
    }

    function burn(uint256 amount) public override {
        super.burn(amount);
    }

    function burnFrom(address account, uint256 amount) public override onlyOperator {
        super.burnFrom(account, amount);
    }

    function transferFrom(address sender,address recipient,uint256 amount) public override returns (bool) {
         if (whitelist[sender] == true || whitelist[recipient] == true ) {
            super._transfer(sender, recipient, amount);
        }
        else {
            uint256 taxAmount = amount.mul(taxRate).div(100);
            uint256 amountAfterTax = amount.sub(taxAmount);
            _transfer(sender, taxCollectorAddress, taxAmount);
            _transfer(sender, recipient, amountAfterTax);
        }
            _approve(sender, _msgSender(), allowance(sender, _msgSender()).sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        if (whitelist[_msgSender()] == true || whitelist[recipient] == true  ) {
            super._transfer(_msgSender(), recipient, amount);
        }
        else {
            uint256 taxAmount = amount.mul(taxRate).div(100);
            uint256 amountAfterTax = amount.sub(taxAmount);

            _transfer(_msgSender(), taxCollectorAddress, taxAmount);
            _transfer(_msgSender(), recipient, amountAfterTax);
        }

        return true;
    }

}