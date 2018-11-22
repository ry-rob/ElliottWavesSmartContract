pragma solidity 0.4.25;

import "./DetailedToken.sol";
import "./SafeMath.sol";


contract ElliottWavesToken is DetailedToken {
    using SafeMath for uint256;

    modifier onlyBagholders {
        require(myTokens() > 0);
        _;
    }

    modifier onlyStronghands {
        require(myDividends() > 0);
        _;
    }

    event OnTokenPurchase(
        address indexed customerAddress,
        uint256 incomingEthereum,
        uint256 tokensMinted,
        uint timestamp,
        uint256 price
    );

    event OnTokenSell(
        address indexed customerAddress,
        uint256 tokensBurned,
        uint256 ethereumEarned,
        uint timestamp,
        uint256 price
    );

    event OnReinvestment(
        address indexed customerAddress,
        uint256 ethereumReinvested,
        uint256 tokensMinted
    );

    event OnWithdraw(
        address indexed customerAddress,
        uint256 ethereumWithdrawn
    );

    event Transfer(
        address indexed from,
        address indexed to,
        uint256 tokens
    );

    uint8 constant internal entryFee_ = 10;
    uint8 constant internal transferFee_ = 0;
    uint8 constant internal exitFee_ = 10;
    uint256 constant internal tokenPriceInitial_ = 0.001 ether;
    uint256 constant internal tokenPriceIncremental_ = 0.0001 ether;
    uint256 constant internal magnitude = 2 ** 64;
    mapping(address => uint256) internal tokenBalanceLedger_;
    mapping(address => int256) internal payoutsTo_;
    uint256 internal tokenSupply_;
    uint256 internal profitPerShare_;
    
    constructor() public DetailedToken("Elliott Waves Token", "EWT", 18) {}
    
    function buy() public payable returns (uint256) {
        return purchaseTokens(msg.value);
    }
    
    function() payable public {
        purchaseTokens(msg.value);
    }

    function reinvest() onlyStronghands public {
        uint256 _dividends = myDividends();
        address _customerAddress = msg.sender;
        payoutsTo_[_customerAddress] += (int256) (_dividends.mul(magnitude));
        uint256 _tokens = purchaseTokens(_dividends);
        emit OnReinvestment(_customerAddress, _dividends, _tokens);
    }

    function exit() public {
        address _customerAddress = msg.sender;
        uint256 _tokens = tokenBalanceLedger_[_customerAddress];
        if (_tokens > 0) sell(_tokens);
        withdraw();
    }

    function withdraw() onlyStronghands public {
        address _customerAddress = msg.sender;
        uint256 _dividends = myDividends();
        payoutsTo_[_customerAddress] += (int256) (_dividends.mul(magnitude));
        _customerAddress.transfer(_dividends);
        emit OnWithdraw(_customerAddress, _dividends);
    }

    function sell(uint256 _amountOfTokens) onlyBagholders public {
        address _customerAddress = msg.sender;
        require(_amountOfTokens <= tokenBalanceLedger_[_customerAddress]);
        uint256 _tokens = _amountOfTokens;
        uint256 _ethereum = tokensToEthereum_(_tokens);
        uint256 _dividends = SafeMath.div(SafeMath.mul(_ethereum, exitFee_), 100);
        uint256 _taxedEthereum = SafeMath.sub(_ethereum, _dividends);

        tokenSupply_ = SafeMath.sub(tokenSupply_, _tokens);
        tokenBalanceLedger_[_customerAddress] = tokenBalanceLedger_[_customerAddress].sub(_tokens);

        int256 _updatedPayouts = (int256) (SafeMath.add(profitPerShare_.mul(_tokens), _taxedEthereum.mul(magnitude)));
        payoutsTo_[_customerAddress] -= _updatedPayouts;

        if (tokenSupply_ > 0) {
            profitPerShare_ = SafeMath.add(profitPerShare_, _dividends.mul(magnitude).div(tokenSupply_));
        }
        
        emit OnTokenSell(_customerAddress, _tokens, _taxedEthereum, now, buyPrice());
        emit Transfer(_customerAddress, address(0x0), _amountOfTokens);
    }

    function transfer(address _toAddress, uint256 _amountOfTokens) onlyBagholders public returns (bool) {
        address _customerAddress = msg.sender;
        require(_amountOfTokens <= tokenBalanceLedger_[_customerAddress]);

        if (myDividends() > 0) {
            withdraw();
        }

        uint256 _tokenFee = SafeMath.div(SafeMath.mul(_amountOfTokens, transferFee_), 100);
        uint256 _taxedTokens = SafeMath.sub(_amountOfTokens, _tokenFee);
        uint256 _dividends = tokensToEthereum_(_tokenFee);

        tokenSupply_ = SafeMath.sub(tokenSupply_, _tokenFee);
        tokenBalanceLedger_[_customerAddress] = SafeMath.sub(tokenBalanceLedger_[_customerAddress], _amountOfTokens);
        tokenBalanceLedger_[_toAddress] = SafeMath.add(tokenBalanceLedger_[_toAddress], _taxedTokens);
        payoutsTo_[_customerAddress] -= (int256) (profitPerShare_.mul(_amountOfTokens));
        payoutsTo_[_toAddress] += (int256) (profitPerShare_.mul(_taxedTokens));
        profitPerShare_ = SafeMath.add(profitPerShare_, _dividends.mul(magnitude).div(tokenSupply_));
        emit Transfer(_customerAddress, _toAddress, _taxedTokens);
        return true;
    }
    
    function tokenPriceIncremental() public pure returns (uint256) {
        return tokenPriceIncremental_;
    }
    
    function tokenPriceInitial() public pure returns (uint256) {
        return tokenPriceInitial_;
    }
    
    function totalEthereumBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function totalSupply() public view returns (uint256) {
        return tokenSupply_;
    }

    function myTokens() public view returns (uint256) {
        return balanceOf(msg.sender);
    }

    function myDividends() public view returns (uint256) {
        return dividendsOf(msg.sender) ;
    }

    function balanceOf(address _customerAddress) public view returns (uint256) {
        return tokenBalanceLedger_[_customerAddress];
    }

    function dividendsOf(address _customerAddress) public view returns (uint256) {
        return (uint256) ((int256) (profitPerShare_ * tokenBalanceLedger_[_customerAddress]) - payoutsTo_[_customerAddress]) / magnitude;
    }

    function sellPrice() public view returns (uint256) {
        uint256 _ethereum = tokensToEthereum_(1e18);
        uint256 _dividends = SafeMath.div(SafeMath.mul(_ethereum, exitFee_), 100);
        uint256 _taxedEthereum = SafeMath.sub(_ethereum, _dividends);

        return _taxedEthereum;
    }

    function buyPrice() public view returns (uint256) {
        uint256 _ethereum = tokensToEthereum_(1e18);
        uint256 _dividends = SafeMath.div(SafeMath.mul(_ethereum, entryFee_), 100);
        uint256 _taxedEthereum = SafeMath.add(_ethereum, _dividends);

        return _taxedEthereum;
    }

    function calculateTokensReceived(uint256 _ethereumToSpend) public view returns (uint256) {
        uint256 _dividends = SafeMath.div(SafeMath.mul(_ethereumToSpend, entryFee_), 100);
        uint256 _taxedEthereum = SafeMath.sub(_ethereumToSpend, _dividends);
        uint256 _amountOfTokens = ethereumToTokens_(_taxedEthereum);

        return _amountOfTokens;
    }

    function calculateEthereumReceived(uint256 _tokensToSell) public view returns (uint256) {
        require(_tokensToSell <= tokenSupply_);
        uint256 _ethereum = tokensToEthereum_(_tokensToSell);
        uint256 _dividends = SafeMath.div(SafeMath.mul(_ethereum, exitFee_), 100);
        uint256 _taxedEthereum = SafeMath.sub(_ethereum, _dividends);
        return _taxedEthereum;
    }

    function purchaseTokens(uint256 _incomingEthereum) internal returns (uint256) {
        address _customerAddress = msg.sender;
        uint256 _dividends = SafeMath.div(SafeMath.mul(_incomingEthereum, entryFee_), 100);
        uint256 _taxedEthereum = SafeMath.sub(_incomingEthereum, _dividends);
        uint256 _amountOfTokens = ethereumToTokens_(_taxedEthereum);
        uint256 _fee = _dividends.mul(magnitude);

        require(_amountOfTokens > 0 && SafeMath.add(_amountOfTokens, tokenSupply_) > tokenSupply_);
        
        tokenSupply_ = SafeMath.add(tokenSupply_, _amountOfTokens);
        profitPerShare_ += _dividends.mul(magnitude).div(tokenSupply_);
        _fee = _fee.sub(_fee.sub(_amountOfTokens * (_dividends.mul(magnitude).div(tokenSupply_))));

        tokenBalanceLedger_[_customerAddress] = SafeMath.add(tokenBalanceLedger_[_customerAddress], _amountOfTokens);
        int256 _updatedPayouts = (int256) (profitPerShare_ * _amountOfTokens - _fee);
        payoutsTo_[_customerAddress] += _updatedPayouts;
        emit OnTokenPurchase(_customerAddress, _incomingEthereum, _amountOfTokens, now, buyPrice());
        emit Transfer(address(0x0), _customerAddress, _amountOfTokens);

        return _amountOfTokens;
    }

    function ethereumToTokens_(uint256 _ethereum) internal view returns (uint256) {
        uint256 _tokenPriceInitial = tokenPriceInitial_ * 1e18;
        uint256 _tokensReceived =
            (
                (
                    SafeMath.sub(
                        (sqrt
                            (
                                (_tokenPriceInitial ** 2)
                                +
                                (2 * (tokenPriceIncremental_ * 1e18) * (_ethereum * 1e18))
                                +
                                ((tokenPriceIncremental_ ** 2) * (tokenSupply_ ** 2))
                                +
                                (2 * tokenPriceIncremental_ * _tokenPriceInitial * tokenSupply_)
                            )
                        ), _tokenPriceInitial
                    )
                ) / (tokenPriceIncremental_)
            ) - (tokenSupply_);

        return _tokensReceived;
    }

    function tokensToEthereum_(uint256 _tokens) internal view returns (uint256) {
        uint256 tokens_ = (_tokens + 1e18);
        uint256 _tokenSupply = (tokenSupply_ + 1e18);
        uint256 _etherReceived =
            (
                SafeMath.sub(
                    (
                        (
                            (
                                tokenPriceInitial_ + (tokenPriceIncremental_ * (_tokenSupply / 1e18))
                            ) - tokenPriceIncremental_
                        ) * (tokens_ - 1e18)
                    ), (tokenPriceIncremental_ * ((tokens_ ** 2 - tokens_) / 1e18)) / 2
                )
                / 1e18);

        return _etherReceived;
    }

    function sqrt(uint256 x) internal pure returns (uint256 y) {
        uint256 z = x.add(1).div(2);
        y = x;

        while (z < y) {
            y = z;
            z = x.div(z).add(z).div(2);
        }
    }
}
