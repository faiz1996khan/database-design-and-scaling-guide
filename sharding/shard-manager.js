/*
All the code here is simple and for demonstration only
Production or real development code could be more complex and different
This is only to explain concept
*/
const { shard1, shard2 } = require("./db");

const shards = {
  "shard-1": {
    name: "shard-1",
    pool: shard1,
  },
  "shard-2": {
    name: "shard-2",
    pool: shard2,
  },
};

function getShardName(customerId) {
  if (customerId < 1 || customerId > 100000) {
    throw new Error("Customer ID is outside supported range");
  }

  return customerId <= 50000 ? "shard-1" : "shard-2";
}

function getShard(customerId) {
  const shardName = getShardName(customerId);

  return shards[shardName];
}

function getAllShards() {
  return Object.values(shards);
}

module.exports = {
  getShardName,
  getShard,
  getAllShards,
};