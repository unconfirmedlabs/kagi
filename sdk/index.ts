import { bcs } from "@mysten/sui/bcs";
import { deriveObjectID } from "@mysten/sui/utils";

const EnclaveKeyBcs = bcs.struct("EnclaveKey", {
  pk: bcs.vector(bcs.u8()),
});

const EnclaveAdminCapKeyBcs = bcs.struct("EnclaveAdminCapKey", {
  dummy_field: bcs.bool(),
});

/**
 * Derive the object ID of an `Enclave<App>` from its `EnclavePolicy<App>` ID
 * and the enclave's public key.
 *
 * Mirrors `kagi::enclave::derive_address(policy, pk)`, which is
 * `derived_object::derive_address(object::id(policy), EnclaveKey(pk))`.
 * `packageId` is the kagi package that defines `EnclaveKey`.
 */
export function deriveEnclaveId(
  policyId: string,
  publicKey: Uint8Array,
  packageId: string,
): string {
  const keyBytes = EnclaveKeyBcs.serialize({
    pk: Array.from(publicKey),
  }).toBytes();
  return deriveObjectID(policyId, `${packageId}::enclave::EnclaveKey`, keyBytes);
}

/**
 * Derive the object ID of an `EnclaveAdminCap<App>` from its `Enclave<App>` ID.
 *
 * Mirrors `derived_object::claim(&mut enclave.id, EnclaveAdminCapKey())`.
 * A zero-field Move struct serializes as one `dummy_field: bool` byte, `0x00`.
 */
export function deriveEnclaveAdminCapId(
  enclaveId: string,
  packageId: string,
): string {
  const keyBytes = EnclaveAdminCapKeyBcs.serialize({
    dummy_field: false,
  }).toBytes();
  return deriveObjectID(
    enclaveId,
    `${packageId}::enclave::EnclaveAdminCapKey`,
    keyBytes,
  );
}

/**
 * Derive both the `Enclave` and `EnclaveAdminCap` object IDs from an
 * `EnclavePolicy` ID and the enclave's public key.
 */
export function deriveEnclaveIds(
  policyId: string,
  publicKey: Uint8Array,
  packageId: string,
): { enclaveId: string; enclaveAdminCapId: string } {
  const enclaveId = deriveEnclaveId(policyId, publicKey, packageId);
  const enclaveAdminCapId = deriveEnclaveAdminCapId(enclaveId, packageId);
  return { enclaveId, enclaveAdminCapId };
}
