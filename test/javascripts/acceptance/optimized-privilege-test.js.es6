import { acceptance } from "discourse/tests/helpers/qunit-helpers";

acceptance("optimized-privilege", { loggedIn: true });

test("optimized-privilege works", async assert => {
  await visit("/admin/plugins/optimized-privilege");

  assert.ok(false, "it shows the optimized-privilege button");
});
