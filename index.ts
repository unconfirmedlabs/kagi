import { bcs } from "@mysten/sui/bcs";
import { deriveObjectID } from "@mysten/sui/utils";

const TESTNET_PACKAGE_ID =
  "0x68b0993136fdc5aa02275a3a0b51f93e9b7c3b601867ec4a8123a76503665161";

// BCS types matching the Move structs:
//   public struct EnclaveKey(vector<u8>) has copy, drop, store;
//   public struct EnclaveCapKey() has copy, drop, store;

const EnclaveKeyBcs = bcs.struct("EnclaveKey", {
  pk: bcs.vector(bcs.u8()),
});

const EnclaveCapKeyBcs = bcs.struct("EnclaveCapKey", {});

/**
 * Derive the object ID of an `Enclave<T>` from its parent `EnclavePolicy<T>` ID
 * and the enclave's public key.
 *
 * Mirrors: `claim(policy.uid_mut(), EnclaveKey(pk))`
 */
export function deriveEnclaveId(
  policyId: string,
  publicKey: Uint8Array,
  packageId: string = TESTNET_PACKAGE_ID,
): string {
  const keyBytes = EnclaveKeyBcs.serialize({
    pk: Array.from(publicKey),
  }).toBytes();

  return deriveObjectID(
    policyId,
    `${packageId}::enclave::EnclaveKey`,
    keyBytes,
  );
}

/**
 * Derive the object ID of an `EnclaveCap<T>` from its parent `Enclave<T>` ID.
 *
 * Mirrors: `claim(&mut enclave.id, EnclaveCapKey())`
 */
export function deriveEnclaveCapId(
  enclaveId: string,
  packageId: string = TESTNET_PACKAGE_ID,
): string {
  const keyBytes = EnclaveCapKeyBcs.serialize({}).toBytes();

  return deriveObjectID(
    enclaveId,
    `${packageId}::enclave::EnclaveCapKey`,
    keyBytes,
  );
}

/**
 * Derive both the Enclave and EnclaveCap object IDs from an EnclavePolicy ID
 * and the enclave's public key.
 */
export function deriveEnclaveIds(
  policyId: string,
  publicKey: Uint8Array,
  packageId: string = TESTNET_PACKAGE_ID,
): { enclaveId: string; enclaveCapId: string } {
  const enclaveId = deriveEnclaveId(policyId, publicKey, packageId);
  const enclaveCapId = deriveEnclaveCapId(enclaveId, packageId);
  return { enclaveId, enclaveCapId };
}
