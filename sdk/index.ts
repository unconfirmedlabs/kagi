import { bcs } from "@mysten/sui/bcs";
import { deriveObjectID } from "@mysten/sui/utils";

const EnclaveKeyBcs = bcs.struct("EnclaveKey", {
  pk: bcs.vector(bcs.u8()),
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
