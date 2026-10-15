// SPDX-License-Identifier: Apache-2.0
// Tests of the SPDX expression check in scripts/check-js-licenses.mjs. Run: node --test scripts/test/
import assert from "node:assert/strict";
import { test } from "node:test";
import { COMMON_ALLOWED, parseExpression, satisfies } from "../check-js-licenses.mjs";

const allowed = new Set(COMMON_ALLOWED);

test("single licenses", () => {
  assert.equal(satisfies("MIT", allowed), true);
  assert.equal(satisfies("GPL-3.0-only", allowed), false);
  assert.equal(satisfies("Unknown", allowed), false);
});

test("OR needs one allowed side, AND needs both", () => {
  assert.equal(satisfies("(MIT OR GPL-3.0-only)", allowed), true);
  assert.equal(satisfies("MIT AND ISC", allowed), true);
  assert.equal(satisfies("MIT AND GPL-3.0-only", allowed), false);
});

test("parentheses keep a mandatory copyleft license mandatory", () => {
  assert.equal(satisfies("GPL-3.0-only AND (MIT OR Apache-2.0)", allowed), false);
  assert.equal(satisfies("(MIT OR Apache-2.0) AND GPL-3.0-only", allowed), false);
  assert.equal(satisfies("(GPL-3.0-only OR MIT) AND (ISC OR LGPL-2.1-only)", allowed), true);
  assert.equal(satisfies("((MIT))", allowed), true);
});

test("AND binds tighter than OR", () => {
  assert.equal(satisfies("GPL-3.0-only AND MIT OR Apache-2.0", allowed), true);
  assert.equal(satisfies("MIT OR GPL-3.0-only AND LGPL-2.1-only", allowed), true);
  assert.deepEqual(parseExpression("A AND B OR C"), { or: [{ and: [{ id: "A" }, { id: "B" }] }, { id: "C" }] });
});

test("operators in lower case", () => {
  assert.equal(satisfies("mit or gpl-3.0-only", new Set(["mit"])), true);
  assert.equal(satisfies("MIT and GPL-3.0-only", allowed), false);
});

test("WITH must be allowed as a whole", () => {
  assert.equal(satisfies("Apache-2.0 WITH LLVM-exception", allowed), false);
  assert.equal(satisfies("Apache-2.0 WITH LLVM-exception", new Set(["Apache-2.0 WITH LLVM-exception"])), true);
});

test("malformed expressions fail closed", () => {
  for (const expr of ["", "(MIT", "MIT)", "MIT OR", "AND MIT", "MIT GPL-3.0-only", "MIT WITH", "()"]) {
    assert.equal(satisfies(expr, allowed), false, expr);
  }
});
