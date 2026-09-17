/*
All the code here is simple and for demonstration only
Production or real development code could be more complex and different
This is only to explain concept
*/
const { getShard } = require("./shard-manager");

async function getCustomerOrders(customerId) {
  const shard = getShard(customerId);

  console.log(
    `TARGETED customerId=${customerId} - ${shard.name}`,
  );

  const result = await shard.pool.query(
    `
    SELECT
      id,
      customer_id,
      order_status,
      total_amount,
      created_at
    FROM orders
    WHERE customer_id = $1
    ORDER BY id
    LIMIT 10
    `,
    [customerId],
  );

  return {
    shard: shard.name,
    orders: result.rows,
  };
}

module.exports = {
  getCustomerOrders,
};