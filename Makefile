-include .env

.PHONY: all test clean deploy fund help install snapshot format anvil 

DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

help:
	@echo "Usage:"
	@echo "  make deploy [ARGS=...]\n    example: make deploy ARGS=\"--network sepolia\""
	@echo ""
	@echo "  make fund [ARGS=...]\n    example: make deploy ARGS=\"--network sepolia\""

all: clean remove install update build

# Clean the repo
clean  :; forge clean

# Remove modules
remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

install :; forge install chainaccelorg/foundry-devops@0.0.11 --no-commit && forge install smartcontractkit/chainlink-brownie-contracts@0.6.1 --no-commit && forge install foundry-rs/forge-std@v1.5.3 --no-commit && forge install openzeppelin/openzeppelin-contracts@v4.8.3 --no-commit

# Update Dependencies
update:; forge update

build:; forge build

test :; forge test 

coverage :; forge coverage --report debug > coverage-report.txt

snapshot :; forge snapshot

format :; forge fmt

anvil :; anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1

NETWORK_ARGS := --rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast

ifeq ($(findstring --network sepolia,$(ARGS)),--network sepolia)
	NETWORK_ARGS := --rpc-url $(SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
endif

deploy:
	@forge script script/DeployDSC.s.sol:DeployDSC $(NETWORK_ARGS)


getWETH:
	cast send 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0 "mint(address,uint256)" 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 1ether --rpc-url http://localhost:8545 --private-key ${DEFAULT_ANVIL_KEY}

approveWETH:
	cast send 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0 "approve(address,uint256)" 0xa513E6E4b8f2a923D98304ec87F64353C4D5C853 1ether --rpc-url http://localhost:8545 --private-key ${DEFAULT_ANVIL_KEY}

depositAndMintDsc:
	cast send 0xa513E6E4b8f2a923D98304ec87F64353C4D5C853 "depositCollateralAndMintDsc(address,uint256,uint256)" 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0 1ether 0.01ether --rpc-url http://localhost:8545 --private-key ${DEFAULT_ANVIL_KEY}

getDscMinted:
	cast call 0xa513E6E4b8f2a923D98304ec87F64353C4D5C853 "getDscMinted(address)" 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --rpc-url http://localhost:8545 --private-key ${DEFAULT_ANVIL_KEY}
