const ethers = require("ethers");
require("dotenv").config();

const RPC_URL = process.env.RPC_URL || process.env.GANACHE_RPC || "http://127.0.0.1:7545";

const provider = new ethers.providers.JsonRpcProvider(RPC_URL);

if (!process.env.DEPLOYER_PRIVATE_KEY) {
    throw new Error("Missing DEPLOYER_PRIVATE_KEY in backend .env");
}

const wallet = new ethers.Wallet(process.env.DEPLOYER_PRIVATE_KEY, provider);

const AUCTION_ARTIFACT = require("../../../blockchain/artifacts/contracts/Auction.sol/Auction.json");
const AUCTION_ABI = AUCTION_ARTIFACT.abi;
const AUCTION_BYTECODE = AUCTION_ARTIFACT.bytecode;

function unixSecondsToDate(unixSeconds) {
    return new Date(Number(unixSeconds) * 1000);
}

async function deployAuctionContract(auctionData) {
    try {
        console.log("Starting Auction contract deployment...");
        console.log("RPC URL:", RPC_URL);

        try {
            const network = await provider.getNetwork();
            console.log(`Connected blockchain network: chainId=${network.chainId}, name=${network.name}`);
        } catch (networkError) {
            throw new Error(
                `Cannot connect to blockchain RPC ${RPC_URL}. ` +
                `Start Ganache/Hardhat on this URL or update GANACHE_RPC/RPC_URL in backend .env. ` +
                `Original error: ${networkError.message}`
            );
        }

        const auctionFactory = new ethers.ContractFactory(
            AUCTION_ABI,
            AUCTION_BYTECODE,
            wallet
        );

        const contract = await auctionFactory.deploy();
        console.log("Deploy tx:", contract.deployTransaction.hash);

        await contract.deployed();

        const contractAddress = contract.address;
        console.log("Contract deployed at:", contractAddress);

        const requestedStartTimeMs = new Date(auctionData.start_time).getTime();
        const requestedEndTimeMs = new Date(auctionData.end_time).getTime();
        if (Number.isNaN(requestedStartTimeMs) || Number.isNaN(requestedEndTimeMs)) {
            throw new Error("Invalid auction start_time or end_time");
        }

        const requestedStartTimeSeconds = Math.floor(requestedStartTimeMs / 1000);
        const requestedEndTimeSeconds = Math.floor(requestedEndTimeMs / 1000);
        const latestBlock = await provider.getBlock("latest");
        const onChainStartTimeSeconds = Math.max(requestedStartTimeSeconds, latestBlock.timestamp);

        const durationSeconds = requestedEndTimeSeconds - requestedStartTimeSeconds;
        if (durationSeconds < 300) {
            throw new Error("Auction duration must be at least 5 minutes");
        }

        if (requestedEndTimeSeconds <= onChainStartTimeSeconds) {
            throw new Error("Auction end_time must be later than start_time");
        }

        console.log(
            `Creating auction on-chain with start ${onChainStartTimeSeconds} and duration ${durationSeconds}s...`
        );
        const tx = await contract.createAuction(
            auctionData.start_price.toString(),
            auctionData.step_price.toString(),
            onChainStartTimeSeconds,
            durationSeconds,
            auctionData.title || "No metadata"
        );

        console.log("Waiting for createAuction transaction to be mined...");
        const receipt = await tx.wait();
        if (receipt.status !== 1) {
            throw new Error("createAuction transaction reverted");
        }

        const auctionCreatedEvent = receipt.events?.find(
            (event) => event.event === "AuctionCreated"
        );
        const blockchainId = auctionCreatedEvent?.args?.auctionId?.toNumber();
        if (!blockchainId) {
            throw new Error("AuctionCreated event not found in receipt");
        }

        const onChainAuction = await contract.getAuction(blockchainId);
        const onChainStartTime = unixSecondsToDate(onChainAuction.startTime.toNumber());
        const onChainEndTime = unixSecondsToDate(onChainAuction.endTime.toNumber());

        console.log("Auction created successfully on-chain");
        console.log(`  Contract Address: ${contractAddress}`);
        console.log(`  Blockchain ID: ${blockchainId}`);
        console.log(`  On-chain Start Time: ${onChainStartTime.toISOString()}`);
        console.log(`  On-chain End Time: ${onChainEndTime.toISOString()}`);

        return {
            contract_address: contractAddress,
            blockchain_id: blockchainId,
            deploy_tx_hash: tx.hash,
            start_time: onChainStartTime,
            end_time: onChainEndTime
        };
    } catch (error) {
        console.error("Auction deployment failed:", error);
        throw new Error(`Deploy failed: ${error.message || error}`);
    }
}

module.exports = { deployAuctionContract };