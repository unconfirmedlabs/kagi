import { describe, expect, test } from "bun:test";
import { fromHex } from "@mysten/sui/utils";
import {
  deriveEnclaveAdminCapId,
  deriveEnclaveId,
  deriveEnclaveIds,
} from "./index";

const MOVE_TEST_PACKAGE_ID = "0x0";
const MOVE_TEST_POLICY_ID =
  "0x034401905bebdf8c04f3cd5f04f442a39372c8dc321c29edfb4f9cb30b23ab96";
const MOVE_TEST_PK = fromHex(
  "e8e62201dbe293b703c759f653107acbc2c911fa1d2e66f2c747bec95971a2af",
);
const MOVE_TEST_ENCLAVE_ID =
  "0x08aea01667c85d97c7642fffb184f7cb2541749a69266c283723c94dcba0aa93";
const MOVE_TEST_ENCLAVE_ADMIN_CAP_ID =
  "0xc05c8aa096f5f0be5a91b8538880bc68aeec6795247792c35e0907441fb2dc49";

const FAKE_PACKAGE_ID =
  "0x0000000000000000000000000000000000000000000000000000000000001234";
const FAKE_POLICY_ID =
  "0x0000000000000000000000000000000000000000000000000000000000c0ffee";
const FAKE_PK = new Uint8Array(32).fill(0xab);

describe("deriveEnclaveId", () => {
  test("matches the ID the Move test derived_addresses_match_the_registered_objects pins", () => {
    expect(
      deriveEnclaveId(MOVE_TEST_POLICY_ID, MOVE_TEST_PK, MOVE_TEST_PACKAGE_ID),
    ).toBe(MOVE_TEST_ENCLAVE_ID);
  });

  test("accepts a full-length package ID", () => {
    expect(
      deriveEnclaveId(MOVE_TEST_POLICY_ID, MOVE_TEST_PK, `0x${"0".repeat(64)}`),
    ).toBe(MOVE_TEST_ENCLAVE_ID);
  });

  test("returns a valid 0x-prefixed hex address", () => {
    const id = deriveEnclaveId(FAKE_POLICY_ID, FAKE_PK, FAKE_PACKAGE_ID);
    expect(id).toMatch(/^0x[0-9a-f]{64}$/);
  });

  test("different public keys produce different IDs", () => {
    const pk2 = new Uint8Array(32).fill(0xcd);
    const a = deriveEnclaveId(FAKE_POLICY_ID, FAKE_PK, FAKE_PACKAGE_ID);
    const b = deriveEnclaveId(FAKE_POLICY_ID, pk2, FAKE_PACKAGE_ID);
    expect(a).not.toBe(b);
  });

  test("different policy IDs produce different IDs", () => {
    const policy2 =
      "0x0000000000000000000000000000000000000000000000000000000000decade";
    const a = deriveEnclaveId(FAKE_POLICY_ID, FAKE_PK, FAKE_PACKAGE_ID);
    const b = deriveEnclaveId(policy2, FAKE_PK, FAKE_PACKAGE_ID);
    expect(a).not.toBe(b);
  });

  test("different package IDs produce different IDs", () => {
    const a = deriveEnclaveId(FAKE_POLICY_ID, FAKE_PK, FAKE_PACKAGE_ID);
    const b = deriveEnclaveId(FAKE_POLICY_ID, FAKE_PK, MOVE_TEST_PACKAGE_ID);
    expect(a).not.toBe(b);
  });
});

describe("deriveEnclaveAdminCapId", () => {
  test("matches the ID the Move test derived_addresses_match_the_registered_objects pins", () => {
    expect(
      deriveEnclaveAdminCapId(MOVE_TEST_ENCLAVE_ID, MOVE_TEST_PACKAGE_ID),
    ).toBe(MOVE_TEST_ENCLAVE_ADMIN_CAP_ID);
  });

  test("returns a valid 0x-prefixed hex address", () => {
    const enclaveId = deriveEnclaveId(FAKE_POLICY_ID, FAKE_PK, FAKE_PACKAGE_ID);
    expect(deriveEnclaveAdminCapId(enclaveId, FAKE_PACKAGE_ID)).toMatch(
      /^0x[0-9a-f]{64}$/,
    );
  });
});

describe("deriveEnclaveIds", () => {
  test("matches the Move test vector", () => {
    expect(
      deriveEnclaveIds(MOVE_TEST_POLICY_ID, MOVE_TEST_PK, MOVE_TEST_PACKAGE_ID),
    ).toEqual({
      enclaveId: MOVE_TEST_ENCLAVE_ID,
      enclaveAdminCapId: MOVE_TEST_ENCLAVE_ADMIN_CAP_ID,
    });
  });
});
