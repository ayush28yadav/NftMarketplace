// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


//ERRORS

error PriceNotMet(address nftAddress, uint256 tokenId, uint256 price);
error NftNotForSale(address nftAddress, uint256 tokenId);
error NotListed(address nftAddress, uint256 tokenId);
error AlreadyListed(address nftAddress, uint256 tokenId);
error NoEarnings();
error NotOwner();
error NotApprovedForMarketplace();
error PriceMustBeAboveZero();
error ListingFeeNotMatched();
error Auction__AppNotStarted();
error Auction__NotStarted();
error Auction__SaleOver();
error Auction__ItemSold();
error Auction__NotOwner();
error Auction__NoBalance();
error Auction__NotSeller();
error Auction__ItemNonExistent();




contract NftMarketplace is ReentrancyGuard,Ownable {
  
//EVENTS

    event NftListed(
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 price
    );

    event NftCanceled(
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed tokenId
    );

    event NftBought(
        address indexed buyer,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 price
    );


    //auction events
      event AuctionOpen(address indexed owner);
    event AuctionItemCreated(address indexed seller, uint256 timestamp, uint256 auctionId);
    event AuctionStarted( uint256 auctionId);
    event AuctionItemBidIncreased(address indexed sender, uint256 bid);
    event BalanceClaimed(address indexed sender, uint256 bal, uint256 timestamp);
    event AuctionItemSold(address winner, uint256 amount, uint256 timestamp);
    event AuctionClosed(address indexed owner);
    


  //variables

      struct NftListing {
        uint256 price;
        address seller;
    }



    uint256 immutable ListingFee= 100000000000000000;
    mapping(address => mapping(uint256 => NftListing)) private AllNftListed;
    mapping(address => uint256) private Earning;

    //auction variables
     
    uint256 public totalItems = 0; // Amount of items created for auction
    uint256 immutable TAX_FEE = 1e5; // fee for registration
   
 

    mapping(address => uint) public bids;

    struct AuctionItem {
        address payable seller; // seller of item
        address highestBidder; // highest bidder
        uint highestBid; // highest bid
        address nft; //  address of NFT
        uint nftId; // NFT id
        uint endAt; // expiration period on item 
        bool started; // auction started = true
        bool sold;  // item sold = true
    }
    AuctionItem[] public auctionItems;
   

   //modifiers
    modifier notListed(
        address nftAddress,
        uint256 tokenId
    ) {
        NftListing memory listing = AllNftListed[nftAddress][tokenId];
        if (listing.price > 0) {
            revert AlreadyListed(nftAddress, tokenId);
        }
        _;
    }

    modifier isListed(address nftAddress, uint256 tokenId) {
        NftListing memory listing = AllNftListed[nftAddress][tokenId];
        if (listing.price <= 0) {
            revert NotListed(nftAddress, tokenId);
        }
        _;
    }

    modifier isOwner(
        address nftAddress,
        uint256 tokenId,
        address spender
    ) {
        IERC721 nft = IERC721(nftAddress);
        address owner = nft.ownerOf(tokenId);
        if (spender != owner) {
            revert NotOwner();
        }
        _;
    }

    //auction modifiers

  

    modifier auctionExists(uint256 auctionId) {
    if(auctionId > auctionItems.length){
        revert Auction__ItemNonExistent();
    }
        _;
    }

  
    modifier onlySeller(uint256  auctionId) {
        AuctionItem storage auction = auctionItems[auctionId];
        if(msg.sender != auction.seller) 
            revert Auction__NotSeller();
        _;
    }
  

    /////////////////////
    // Main Functions //
    /////////////////////
   
    function listNft(
        address nftAddress,
        uint256 tokenId,
        uint256 price
    )
        external
        payable
        notListed(nftAddress, tokenId)
        isOwner(nftAddress, tokenId, msg.sender)
    {
        if(msg.value<ListingFee){
            revert ListingFeeNotMatched();
        }
        if (price <= 0) {
            revert PriceMustBeAboveZero();
        }
    
        IERC721 nft = IERC721(nftAddress);
        if (nft.getApproved(tokenId) != address(this)) {
            revert NotApprovedForMarketplace();
        }
        AllNftListed[nftAddress][tokenId] = NftListing(price, msg.sender);
        emit NftListed(msg.sender, nftAddress, tokenId, price);
    }

    function cancelNftListing(address nftAddress, uint256 tokenId)
        external
        isOwner(nftAddress, tokenId, msg.sender)
        isListed(nftAddress, tokenId)
    {
        delete (AllNftListed[nftAddress][tokenId]);
        emit NftCanceled(msg.sender, nftAddress, tokenId);
    }

    
    function buyNft(address nftAddress, uint256 tokenId)
        external
        payable
        isListed(nftAddress, tokenId)
        nonReentrant
    {
        NftListing memory listedItem = AllNftListed[nftAddress][tokenId];
        if (msg.value < listedItem.price) {
            revert PriceNotMet(nftAddress, tokenId, listedItem.price);
        }
        Earning[listedItem.seller] += msg.value;
       
        delete (AllNftListed[nftAddress][tokenId]);
        IERC721(nftAddress).safeTransferFrom(listedItem.seller, msg.sender, tokenId);
        emit NftBought(msg.sender, nftAddress, tokenId, listedItem.price);
    }

    
    function updateNftListing(
        address nftAddress,
        uint256 tokenId,
        uint256 newPrice
    )
        external
        isListed(nftAddress, tokenId)
        nonReentrant
        isOwner(nftAddress, tokenId, msg.sender)
    {
       
        if (newPrice <= 0) {
            revert PriceMustBeAboveZero();
        }
        AllNftListed[nftAddress][tokenId].price = newPrice;
        emit NftListed(msg.sender, nftAddress, tokenId, newPrice);
    }

    
    function withdrawEarnings() external {
        uint256 earnings = Earning[msg.sender];
        if (earnings <= 0) {
            revert NoEarnings();
        }
        Earning[msg.sender] = 0;
        (bool success, ) = payable(msg.sender).call{value: earnings}("");
        require(success, "Transfer failed");
    }


    function withdrawBalance() external onlyOwner{
     uint256 balance = address(this).balance;
     (bool success,) = payable(msg.sender).call{value: balance}("");
     require(success, "Transfer Failed");
    }


    //auction functions
  
  

    function registerforAuction(address _nft, uint _nftId, uint highestBid, address payable seller) public payable nonReentrant {
        require(msg.value >= TAX_FEE, "warning: insufficient registration funds");
        auctionItems.push(AuctionItem({
            seller: payable(seller),
            nft: _nft,
            nftId: _nftId,
            highestBidder: address(0),
            highestBid: highestBid,
            endAt: block.timestamp + 7 days,
            started: false,
            sold: false
        }));
        totalItems += 1;
        IERC721(_nft).transferFrom(seller, address(this), _nftId);
        // emit event
        emit AuctionItemCreated(msg.sender, block.timestamp, totalItems+1);
      
    }

    function startAuction(uint256  auctionId) public auctionExists(auctionId) onlySeller(auctionId){
        AuctionItem storage auction = auctionItems[auctionId];
        require(auction.sold != true, "Item sold");
        auction.started = true;
        // emit event
        emit AuctionStarted( auctionId);
    }

    function bid(uint256  auctionId) public auctionExists(auctionId) payable  returns (bool)  {
        AuctionItem storage auction = auctionItems[auctionId];
        if(!auction.started)
            revert Auction__NotStarted();
        if(auction.sold)
            revert Auction__ItemSold();
        if(block.timestamp >= auction.endAt)
            revert Auction__SaleOver();
        require(msg.value > auction.highestBid, "Bid higher");
        auction.highestBidder = msg.sender;
        auction.highestBid = msg.value;
        if(auction.highestBidder != address(0)) {
            bids[auction.highestBidder] += auction.highestBid;
        }
        return true;
        // emit event
        emit AuctionItemBidIncreased(msg.sender, msg.value);
    }

    /* --> EXTERNAL FUNCTIONS <-- */  
    function claimBalance(uint256 auctionId) external auctionExists(auctionId) {
        AuctionItem storage auction = auctionItems[auctionId];
        uint bal = bids[msg.sender];
        bids[msg.sender] = 0;
        if(msg.sender != auction.highestBidder) {
            payable(msg.sender).transfer(bal);
        } else {
        revert Auction__NoBalance();
        }
        // emit event
        emit BalanceClaimed(msg.sender, bal, block.timestamp);
    }

    function transferItem(address nft, uint nftId, uint256 auctionId) external  onlySeller(auctionId) auctionExists(auctionId) {
        AuctionItem storage auction = auctionItems[auctionId];
        require(block.timestamp >= auction.endAt, "warning: Auction not due");
        auction.sold = true;
        if(auction.highestBidder != address(0)) {
            IERC721(nft).safeTransferFrom(address(this), auction.highestBidder, nftId);
        auction.seller.transfer(auction.highestBid);
        } else {
            // transfer item back to seller
            IERC721(nft).safeTransferFrom(address(this), auction.seller, nftId);
        }
        // emit event
        emit AuctionItemSold(auction.highestBidder, auction.highestBid, block.timestamp);
    }


    /////////////////////
    // Getter Functions //
    /////////////////////

    function getListing(address nftAddress, uint256 tokenId)
        external
        view
        returns (NftListing memory)
    {
        return AllNftListed[nftAddress][tokenId];
    }

    function getEarnings(address seller) external view returns (uint256) {
        return Earning[seller];
    }

    function getListingfee() external view returns (uint256){
        return ListingFee;
    }

  //nftauction getter functions
      function getHighestBid(uint256  auctionId) public 
    view
    returns (uint highestBid) {
        AuctionItem storage auction = auctionItems[auctionId];
        return(auction.highestBid);
    }

    function getHighestBidder(uint256  auctionId) public view returns (address highestBidder)
    {
        AuctionItem storage auction = auctionItems[auctionId];
        return(auction.highestBidder);
    }

    function getAuctionItemState(uint256 auctionId) public view returns (bool started, uint endAt, bool sold) {
        AuctionItem storage auction = auctionItems[auctionId];
        return(auction.started, auction.endAt, auction.sold);
    }

    function getSeller(uint256 auctionId) public view returns (address seller) {
        AuctionItem storage auction = auctionItems[auctionId];
        return(auction.seller);
    }

    function getNftId(uint256 auctionId) public view returns (uint nftId) {
        AuctionItem storage auction = auctionItems[auctionId];
        return(auction.nftId);
    }

    function getAuctionItems() public view returns (AuctionItem[] memory) {
        return auctionItems;
    }

    function getTaxfee() public view returns (uint256){
        return TAX_FEE;
            }
}


  

  

    
 
   
    
   



  