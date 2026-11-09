// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IPriceFeed.sol";
import "./interfaces/IMint.sol";
import "./sAsset.sol";
import "./EUSD.sol";

contract Mint is Ownable, IMint{

    struct Asset {
        address token;
        uint minCollateralRatio;
        address priceFeed;
    }

    struct Position {
        uint idx;
        address owner;
        uint collateralAmount;
        address assetToken;
        uint assetAmount;
    }

    mapping(address => Asset) _assetMap;
    uint _currentPositionIndex;
    mapping(uint => Position) _idxPositionMap;
    address public collateralToken;
    

    constructor(address collateral) {
        collateralToken = collateral;
    }

    function registerAsset(address assetToken, uint minCollateralRatio, address priceFeed) external override onlyOwner {
        require(assetToken != address(0), "Invalid assetToken address");
        require(minCollateralRatio >= 1, "minCollateralRatio must be greater than 100%");
        require(_assetMap[assetToken].token == address(0), "Asset was already registered");
        
        _assetMap[assetToken] = Asset(assetToken, minCollateralRatio, priceFeed);
    }

    function getPosition(uint positionIndex) external view returns (address, uint, address, uint) {
        require(positionIndex < _currentPositionIndex, "Invalid index");
        Position storage position = _idxPositionMap[positionIndex];
        return (position.owner, position.collateralAmount, position.assetToken, position.assetAmount);
    }

    function getMintAmount(uint collateralAmount, address assetToken, uint collateralRatio) public view returns (uint) {
        Asset storage asset = _assetMap[assetToken];
        (int relativeAssetPrice, ) = IPriceFeed(asset.priceFeed).getLatestPrice();
        uint8 decimal = sAsset(assetToken).decimals();
        uint mintAmount = collateralAmount * (10 ** uint256(decimal)) / uint(relativeAssetPrice) / collateralRatio ;
        return mintAmount;
    }

    function checkRegistered(address assetToken) public view returns (bool) {
        return _assetMap[assetToken].token == assetToken;
    }

    /* TODO: implement your functions here */
    function mint(uint positionIndex, uint mintAmount) external override{
        require(positionIndex < _currentPositionIndex, "Invalid index");
        Position storage position =_idxPositionMap[positionIndex];
        
        require(position.owner == msg.sender, "Not position owner");
        require(position.assetToken != address(0), "Position is closed");

        Asset storage asset = _assetMap[position.assetToken];
        uint newTotalAssets = position.assetAmount + mintAmount;

        uint maxAllowedTokens = getMintAmount(position.collateralAmount, position.assetToken, asset.minCollateralRatio);
        // check if amount is > max allowed to meet MCR

        require(newTotalAssets <= maxAllowedTokens, "Collateral ratio is < MCR");
        position.assetAmount = newTotalAssets;
        sAsset(position.assetToken).mint(msg.sender, mintAmount);

    }
    
    function burn(uint positionIndex, uint burnAmount) external override{
        require(positionIndex < _currentPositionIndex, "Invalid index");
        Position storage position =_idxPositionMap[positionIndex];
        
        require(position.owner == msg.sender, "Not position owner");
        require(position.assetToken != address(0), "Position is closed");
        require(burnAmount <= position.assetAmount, "Attempting to burn amount greater than position debt");
        sAsset(position.assetToken).burn(msg.sender, burnAmount);
        position.assetAmount -= burnAmount;

    }

    function openPosition(uint collateralAmount, address assetToken, uint collateralRatio) external override{
        // transfer collateralAmount EUSD from message sender to contract
        require(IERC20(collateralToken).transferFrom(msg.sender, address(this), collateralAmount), "Collateral Tranfer failure");
       
        // check asset is registered
        require(checkRegistered(assetToken), "Unregistered asset");

        // check input collateral ratio (collateral / minted tokens) >= MCR
        Asset storage asset = _assetMap[assetToken];

        require(collateralRatio >= asset.minCollateralRatio, "Input collateral ratio below MCR");

        // num tokens to send to message sender
        uint numTokens = getMintAmount(collateralAmount, assetToken, collateralRatio);
        require(numTokens > 0, "Mint amount too small");

        // new position
        _idxPositionMap[_currentPositionIndex] = Position({
            idx: _currentPositionIndex,
            owner: msg.sender,
            collateralAmount: collateralAmount,
            assetToken: assetToken,
            assetAmount: numTokens
        });

        _currentPositionIndex++;
        sAsset(assetToken).mint(msg.sender, numTokens); // mint
    }

    function closePosition(uint positionIndex) external override{
        require(positionIndex < _currentPositionIndex, "Invalid position index");
        Position storage position = _idxPositionMap[positionIndex];
        require(position.owner != address(0), "Position is already closed");
        require(msg.sender == position.owner, "Not position owner");

        uint collateralAmount = position.collateralAmount;
        address assetToken = position.assetToken;
        uint assetAmount = position.assetAmount;
        
        // burn all sAsset tokens
        sAsset(assetToken).burn(msg.sender, assetAmount);

        // transfer EUSD tokens lock in the position to msg.sender
        require(IERC20(collateralToken).transfer(msg.sender, collateralAmount), "Collateral transfer failure.");

        // delete position at positionIndex
        delete _idxPositionMap[positionIndex];
    }

    function deposit(uint positionIndex, uint collateralAmount) external override{
        // check sender owns position
        require(positionIndex < _currentPositionIndex, "Invalid position index");
        Position storage position = _idxPositionMap[positionIndex];
        require(position.owner == msg.sender, "Not position owner");
        require(position.owner != address(0), "Position is already closed");
        require(collateralAmount > 0, "Deposit amount must be > 0");

        // transfer depositied tokens from sender to contract
        require(IERC20(collateralToken).transferFrom(msg.sender, address(this), collateralAmount), "Collateral deposit failed");
        
        // add collateral amt of position at positionIndex
        position.collateralAmount += collateralAmount;
    }

    function withdraw(uint positionIndex, uint withdrawAmount) external override{
        // check sender owns position
        require(positionIndex < _currentPositionIndex, "Invalid position index");
        Position storage position = _idxPositionMap[positionIndex];
        require(position.owner == msg.sender, "Not position owner");
        require(position.owner != address(0), "Position is already closed");
        require(withdrawAmount > 0, "Withdrawal amount must be > 0");
        require(withdrawAmount <= position.collateralAmount, "Cannot withdraw more than locked collateral");

        uint remainingCollateral = position.collateralAmount - withdrawAmount;

        // check collateral ratio > MCR
        Asset storage asset = _assetMap[position.assetToken];
        uint maxMintAmount = getMintAmount(remainingCollateral, position.assetToken, asset.minCollateralRatio);
        require(position.assetAmount <= maxMintAmount, "Collateral ratio below minimum");

        // transfer withdrawn tokens from sender to contract
        position.collateralAmount = remainingCollateral;
        // withdraw collateral amt of position at positionIndex
        require(IERC20(collateralToken).transfer(msg.sender, withdrawAmount), "Collateral withdrawal failed.");

    }



    


}
