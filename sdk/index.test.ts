import { test, expect, describe } from "bun:test";
import { deriveEnclaveId, deriveEnclaveCapId, deriveEnclaveIds } from "./index";

const FAKE_POLICY_ID =
  "0x0000000000000000000000000000000000000000000000000000000000c0ffee";
const FAKE_PK = new Uint8Array(32).fill(0xab);

describe("deriveEnclaveId", () => {
  test("returns a valid 0x-prefixed hex address", () => {
    const id = deriveEnclaveId(FAKE_POLICY_ID, FAKE_PK);
    expect(id).toMatch(/^0x[0-9a-f]{64}$/);
  });

  test("is deterministic", () => {
    const a = deriveEnclaveId(FAKE_POLICY_ID, FAKE_PK);
    const b = deriveEnclaveId(FAKE_POLICY_ID, FAKE_PK);
    expect(a).toBe(b);
  });

  test("different public keys produce different IDs", () => {
    const pk2 = new Uint8Array(32).fill(0xcd);
    const a = deriveEnclaveId(FAKE_POLICY_ID, FAKE_PK);
    const b = deriveEnclaveId(FAKE_POLICY_ID, pk2);
    expect(a).not.toBe(b);
  });

  test("different policy IDs produce different IDs", () => {
    const policy2 =
      "0x0000000000000000000000000000000000000000000000000000000000decade";
    const a = deriveEnclaveId(FAKE_POLICY_ID, FAKE_PK);
    const b = deriveEnclaveId(policy2, FAKE_PK);
    expect(a).not.toBe(b);
  });
});

describe("deriveEnclaveCapId", () => {
  test("returns a valid 0x-prefixed hex address", () => {
    const enclaveId = deriveEnclaveId(FAKE_POLICY_ID, FAKE_PK);
    const capId = deriveEnclaveCapId(enclaveId);
    expect(capId).toMatch(/^0x[0-9a-f]{64}$/);
  });

  test("is deterministic", () => {
    const enclaveId = deriveEnclaveId(FAKE_POLICY_ID, FAKE_PK);
    const a = deriveEnclaveCapId(enclaveId);
    const b = deriveEnclaveCapId(enclaveId);
    expect(a).toBe(b);
  });
});

describe("deriveEnclaveIds", () => {
  test("derives both IDs consistently", () => {
    const { enclaveId, enclaveCapId } = deriveEnclaveIds(
      FAKE_POLICY_ID,
      FAKE_PK,
    );
    expect(enclaveId).toBe(deriveEnclaveId(FAKE_POLICY_ID, FAKE_PK));
    expect(enclaveCapId).toBe(deriveEnclaveCapId(enclaveId));
  });
});
