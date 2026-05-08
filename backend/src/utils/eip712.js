// src/utils/eip712.js
const { ethers } = require('ethers');
const { decrypt } = require('./crypto');
require('dotenv').config();

function buildDomain(verifyingContract) {
  return {
    name: 'BidChain',
    version: '1.0',
    chainId: 1337,
    verifyingContract:
      verifyingContract ||
      process.env.CONTRACT_ADDRESS ||
      '0x0000000000000000000000000000000000000000'
  };
}

/**
 * Bid type definition for EIP-712
 */
const BID_TYPES = {
  Bid: [
    { name: 'auctionId', type: 'string' },
    { name: 'amount', type: 'uint256' },
    { name: 'nonce', type: 'uint256' },
    { name: 'timestamp', type: 'uint256' }
  ]
};

/**
 * Sign a bid using EIP-712
 * @param {Object} user - User object with encrypted_private_key
 * @param {string} auctionId - Auction ID
 * @param {string} amountWei - Bid amount in Wei
 * @param {number} nonce - User nonce
 * @param {number} timestamp - Current timestamp
 * @param {string} [verifyingContract] - Auction contract address used in the EIP-712 domain
 * @returns {Promise<string>} Signature
 */
async function signBid(user, auctionId, amountWei, nonce, timestamp, verifyingContract) {
  try {
    console.log(`Signing bid - User wallet: ${user.wallet_address}`);
    console.log(`Has encrypted_private_key: ${!!user.encrypted_private_key}`);
    console.log(`Signing domain contract: ${verifyingContract || process.env.CONTRACT_ADDRESS}`);

    // Decrypt private key with MASTER_KEY
    const privateKey = decrypt(user.encrypted_private_key, process.env.MASTER_KEY);
    const wallet = new ethers.Wallet(privateKey);

    // Create bid data
    const bidData = {
      auctionId: auctionId,
      amount: ethers.BigNumber.from(amountWei),
      nonce: nonce,
      timestamp: timestamp
    };

    // Sign with EIP-712
    const signature = await wallet._signTypedData(
      buildDomain(verifyingContract),
      BID_TYPES,
      bidData
    );

    console.log(`Bid signed successfully for auction ${auctionId}`);
    return signature;

  } catch (error) {
    console.error('Error signing bid:', error);
    throw new Error('Failed to sign bid: ' + error.message);
  }
}

/**
 * Verify bid signature (for testing)
 * @param {Object} params - Verification parameters
 * @returns {Promise<string>} Recovered signer address
 */
async function verifyBidSignature({ auctionId, amountWei, nonce, timestamp, signature, verifyingContract }) {
  try {
    const bidData = {
      auctionId: auctionId,
      amount: ethers.BigNumber.from(amountWei),
      nonce: nonce,
      timestamp: timestamp
    };

    const recoveredAddress = ethers.utils.verifyTypedData(
      buildDomain(verifyingContract),
      BID_TYPES,
      bidData,
      signature
    );

    return recoveredAddress;
  } catch (error) {
    console.error('Error verifying signature:', error);
    throw error;
  }
}

module.exports = {
  signBid,
  verifyBidSignature
};
