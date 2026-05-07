function getCurrentAuctionTime() {
  return new Date();
}

function getCurrentAuctionTimestampSeconds() {
  return Math.floor(getCurrentAuctionTime().getTime() / 1000);
}

module.exports = {
  getCurrentAuctionTime,
  getCurrentAuctionTimestampSeconds,
};
