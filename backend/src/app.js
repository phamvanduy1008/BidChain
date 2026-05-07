const express = require("express");
const http = require("http");
const cors = require("cors");
const mongoose = require("mongoose");
require("dotenv").config();

const authRoutes = require("./routes/auth");
const auctionRoutes = require("./routes/auction");
const userRoutes = require("./routes/user");
const paymentRoutes = require("./routes/payment");
const adminRoutes = require("./routes/admin/adminUser");
const categoryRoutes = require("./routes/categoryRoutes");
const locationRoutes = require("./routes/location");
const adminAuctionRouter = require("./routes/admin/adminAuction");
const adminDashboardRouter = require("./routes/admin/adminDashboard");
const confirmRoutes = require("./routes/confirm");
const uploadRouter = require("./routes/upload");
const { getCurrentAuctionTime } = require("./utils/auctionTime");

const app = express();
app.use(cors());
app.use(express.json());

app.use("/api/category", categoryRoutes);
app.use("/api/auth", authRoutes);
app.use("/api/auction", auctionRoutes);
app.use("/api/user", userRoutes);
app.use("/api/users", userRoutes);
app.use("/api/payment", paymentRoutes);
app.use("/api/location", locationRoutes);
app.use("/api/confirm", confirmRoutes);
app.use("/api/admin", adminRoutes);
app.use("/api/admin/auctions", adminAuctionRouter);
app.use("/api/admin/dashboard", adminDashboardRouter);
app.use("/api/upload", uploadRouter);

const server = http.createServer(app);
const io = require("socket.io")(server, {
  cors: { origin: "*" }
});

app.set("io", io);
global.io = io;

const { runSettlementCron } = require("./cron/settlement");
setInterval(runSettlementCron, 20000);
console.log("Settlement cron job started (runs every 20s)");

const { runAuctionLifecycleCron } = require("./cron/lifecycle");
setInterval(runAuctionLifecycleCron, 1000);
console.log("Auction lifecycle cron job started (runs every 1s)");

const { startIntegrityCron } = require("./cron/integrity");
startIntegrityCron();

const startAuctionScheduler = require("./scheduler/auctionScheduler");

io.on("connection", (socket) => {
  console.log("New client:", socket.id);

  socket.emit("server_time_sync", {
    server_time: getCurrentAuctionTime().toISOString()
  });

  socket.on("join_room", (auctionId) => {
    const roomName = `auction_room_${auctionId}`;
    socket.join(roomName);
    console.log(`Client ${socket.id} joined room ${roomName}`);
  });

  socket.on("join_auction", (auctionId) => {
    const roomName = `auction_${auctionId}`;
    socket.join(roomName);
    console.log(`Client ${socket.id} joined auction room ${roomName}`);
  });

  socket.on("join_user_room", (userId) => {
    const roomName = `user_${userId}`;
    socket.join(roomName);
    console.log(`Client ${socket.id} joined user room ${roomName}`);
  });

  socket.on("leave_auction", (auctionId) => {
    const roomName = `auction_${auctionId}`;
    socket.leave(roomName);
    console.log(`Client ${socket.id} left auction room ${roomName}`);
  });

  socket.on("disconnect", () => {
    console.log("Client disconnected:", socket.id);
  });
});

console.log("Starting auction management system...");

const PORT = process.env.PORT || 3000;

mongoose
  .connect(process.env.MONGO_URI)
  .then(() => {
    startAuctionScheduler();
    server.listen(PORT, () => {
      console.log("Backend running at http://localhost:" + PORT);
    });
  })
  .catch((err) => console.log("Mongo error:", err));
