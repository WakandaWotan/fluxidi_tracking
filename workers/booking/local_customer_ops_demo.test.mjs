import assert from "node:assert/strict";
import test from "node:test";

import { LOCAL_DEMO_COMPANIES, solidLogoPng } from "./local_customer_ops_demo_companies.mjs";

test("local demo seeds two companies with distinct names and logos", () => {
  assert.equal(LOCAL_DEMO_COMPANIES.length, 2);
  assert.equal(LOCAL_DEMO_COMPANIES[0].name, "Fluxidi Demo Cars");
  assert.equal(LOCAL_DEMO_COMPANIES[1].name, "Nocturne Limousines");
  assert.notEqual(LOCAL_DEMO_COMPANIES[0].id, LOCAL_DEMO_COMPANIES[1].id);
  assert.notEqual(LOCAL_DEMO_COMPANIES[0].token, LOCAL_DEMO_COMPANIES[1].token);
  const a = solidLogoPng(LOCAL_DEMO_COMPANIES[0].logo);
  const b = solidLogoPng(LOCAL_DEMO_COMPANIES[1].logo);
  assert.notEqual(a.equals(b), true);
  assert.equal(a[0], 137);
  assert.equal(a[1], 80);
  assert.equal(a[2], 78);
  assert.equal(a[3], 71);
});
