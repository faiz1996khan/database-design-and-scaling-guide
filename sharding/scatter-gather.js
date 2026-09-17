/*
All the code here is simple and for demonstration only
Production or real development code could be more complex and different
This is only to explain concept
*/
const { getAllShards } = require("./shard-manager");

async function getTotalCompletedOrders() {
  const shards = getAllShards();

  const results = await Promise.all(
    shards.map(async (shard) => {
      console.log(`SCATTER Querying ${shard.name}`);

      const result = await shard.pool.query(`
        SELECT COUNT(*)::BIGINT AS completed_orders
        FROM orders
        WHERE order_status = 'completed'
      `);

      return {
        shard: shard.name,
        completedOrders: Number(
          result.rows[0].completed_orders,
        ),
      };
    }),
  );

  console.log("GATHER Results:", JSON.stringify(results));

  const total = results.reduce((sum, result) => sum + result.completedOrders, 0);

  return {
    totalCompletedOrders: total,
    shardResults: results,
  };
}

module.exports = {
  getTotalCompletedOrders,
};