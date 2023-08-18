# Foundry DeFi Stablecoin

First things first, Huge shout-out to [Patrick Collins](https://twitter.com/PatrickAlphaC) for his amazing course which helped me build this project. You can find the course [here](https://youtube.com/) on YouTube.

Here is [Patrick Collins](https://www.youtube.com/channel/UCn-3f8tw_E1jZvhuHatROwA) YouTube channel. Check it out its amazing.

## About

This project is meant to be a stablecoin where users can deposit WETH and WBTC in exchange for a token that will be pegged to the USD.

- [Foundry DeFi Stablecoin](#foundry-defi-stablecoin)
- [About](#about)
- [Getting Started](#getting-started)
  - [Requirements](#requirements)
  - [Quickstart](#quickstart)
- [Usage](#usage)
  - [Start a local node](#start-a-local-node)
  - [Deploy](#deploy)
  - [Testing](#testing)
    - [Test Coverage](#test-coverage)
- [Deployment to a testnet or mainnet](#deployment-to-testnet-or-mainnet)
  - [Scripts](#scripts)
  - [Estimate gas](#estimate-gas)
- [Formatting](#formatting)
- [Thank you!](#thank-you)

## Getting Started

### Requirements

- [git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
  - You'll know you did it right if you can run `git --version` and you see a response like `git version x.x.x`
- [foundry](https://getfoundry.sh/)
  - You'll know you did it right if you can run `forge --version` and you see a response like `forge 0.2.0 (816e00b 2023-03-16T00:05:26.396218Z)`

### Quickstart

```bash
git clone https://github.com/same871/DSC-Stable-Coin
cd DSC-Stable-Coin
forge build
```

## Usage

### Start a local node

```bash
make anvil
```

### Deploy

This will default to your local node. You need to have it running in another terminal in order for it to deploy.

```bash
make deploy
```

### Testing

- Unit
- Integration
- Forked
- Staging

In this repo we cover #1 and Fuzzing

```bash
forge test
```

- [Deploy - Other Network](#deployment-to-testnet-or-mainnet)

#### Test coverage

```bash
forge coverage
```

and for coverage based testing:

```bash
forge coverage --report debug
```

## Deployment to testnet or mainnet

1. Setup environment variables

You'll want to set your `SEPOLIA_RPC_URL` and `PRIVATE_KEY` as environment variables. You can add then to a `.env` file.

- `PRIVATE_KEY`: The private key of your account (like from [metamask](https://metamask.io/)). **NOTE:** FOR DEVELOPMENT, PLEASE USE A KEY THAT DOESN'T HAVE ANY REAL FUNDS ASSOCIATED WITH IT.
  - You can [learn how to export it here](https://metamask.zendesk.com/hc/en-us/articles/360015289632-How-to-Export-an-Account-Private-Key)
- `SEPOLIA_RPC_URL`: This is url of the Sepolia testnet node you're working with. You can get setup with one for free from [Alchemy](https://alchemy.com/?a=673c802981)

Optionally, add your `ETHERSCAN_API_KEY` if you want to verify your contract on [Etherscan](https://etherscan.io/).

1. Get testnet ETH

Head over to [faucets.chain.link](https://faucets.chain.link/) and get some tesnet ETH. You should see the ETH show up in your metamask.

2. Deploy

```bash
make deploy ARGS="--network sepolia"
```

### Scripts

Instead of scripts, we can direclty use the `cast` command to interact with the contract

For example, on Sepolia:

1. Get some WETH

```bash
cast send 0xdd13E55209Fd76AfE204dBda4007C227904f0a81 "deposit()" --value 0.1ether --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY
```

2. Approve the WETH

```bash
cast send 0xdd13E55209Fd76AfE204dBda4007C227904f0a81 "approve(address,uint256)" 0x091EA0838eBD5b7ddA2F2A641B068d6D59639b98 1000000000000000000 --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY
```

3. Deposit and Mint DSC

```bash
cast send 0x091EA0838eBD5b7ddA2F2A641B068d6D59639b98 "depositCollateralAndMintDsc(address,uint256,uint256)" 0xdd13E55209Fd76AfE204dBda4007C227904f0a81 100000000000000000 10000000000000000 --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY
```

### Estimate gas

You can estimate how much gas things cost by running:

```bash
forge snapshot
```

And you'll see and output file called `.gas-snapshot`

## Formatting

To run code formatting:

```bash
forge fmt
```

## Thank You!

[Samuel Muto Twitter](https://twitter.com/muto_takudzwa)
