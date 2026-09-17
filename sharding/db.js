const { Pool } = require("pg");

const shard1 = new Pool({
  host: "localhost",
  port: 5433,
  user: "sharduser1",
  password: "shardpassword1",
  database: "shard_db1",
});

const shard2 = new Pool({
  host: "localhost",
  port: 5434,
  user: "sharduser2",
  password: "shardpassword2",
  database: "shard_db2",
});

module.exports = {
  shard1,
  shard2,
};