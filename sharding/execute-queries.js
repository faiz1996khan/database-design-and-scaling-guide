/*
All the code here is simple and for demonstration only
Production or real development code could be more complex and different
This is only to explain concept
*/
const { shard1, shard2 } = require("./db");
const { getCustomerOrders } = require("./targeted-query");
const { getTotalCompletedOrders } = require("./scatter-gather");

async function main() {
  console.log("\n=== TARGETED QUERY ===");
  const targetedResult = await getCustomerOrders(25000);
  console.log(targetedResult);
  console.log("\n=== SCATTER-GATHER QUERY ===");
  const scatterResult = await getTotalCompletedOrders();
  console.log(scatterResult);
}

main()
  .catch(err => {
    console.error(err);
  })
  .finally(async () => {
    await Promise.all([
      shard1.end(),
      shard2.end(),
    ]);
  });