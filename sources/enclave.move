// Copyright (c), Unconfirmed Labs, LLC
// SPDX-License-Identifier: Apache-2.0

module kagi::enclave;

use kagi::enclave_policy::{EnclavePolicy, EnclavePolicyCap};
use std::bcs::to_bytes;
use sui::derived_object::claim;
use sui::ed25519::ed25519_verify;
use sui::nitro_attestation::NitroAttestationDocument;

// === Errors ===

const EInvalidSignature: u64 = 0;
const EInvalidEnclaveCap: u64 = 1;

// === Structs ===

/// A verified enclave instance, with its public key.
public struct Enclave<phantom T: drop> has key {
    id: UID,
    pk: vector<u8>,
}

/// A capability granting admin control over an `Enclave`.
public struct EnclaveCap<phantom T: drop> has key, store {
    id: UID,
    enclave_id: ID,
}

/// Key for deriving an Enclave's UID.
public struct EnclaveKey(vector<u8>) has copy, drop, store;

/// Key for deriving an EnclaveCap's UID.
public struct EnclaveCapKey() has copy, drop, store;

/// An intent message, used for wrapping enclave messages for signing.
public struct IntentMessage<T: drop> has copy, drop {
    intent: u8,
    timestamp_ms: u64,
    payload: T,
}

// === Public Functions ===

/// Register a new enclave by verifying a Nitro attestation document.
/// Returns an `Enclave` and its associated `EnclaveCap`.
public fun new<T: drop>(
    _: &EnclavePolicyCap<T>,
    policy: &mut EnclavePolicy<T>,
    document: NitroAttestationDocument,
): (Enclave<T>, EnclaveCap<T>) {
    let pk = policy.load_pk(&document);

    let mut enclave = Enclave<T> {
        id: claim(policy.uid_mut(), EnclaveKey(pk)),
        pk,
    };

    let enclave_cap = EnclaveCap<T> {
        id: claim(&mut enclave.id, EnclaveCapKey()),
        enclave_id: enclave.id.to_inner(),
    };

    (enclave, enclave_cap)
}

public fun share<T: drop>(self: Enclave<T>) {
    transfer::share_object(self);
}

/// Verify an enclave signature over an intent message.
/// Aborts with `EInvalidSignature` if the signature is invalid.
public fun verify_signature<T: drop, P: drop>(
    self: &Enclave<T>,
    intent_scope: u8,
    timestamp_ms: u64,
    payload: P,
    signature: &vector<u8>,
) {
    let intent_message = create_intent_message(intent_scope, timestamp_ms, payload);
    assert!(ed25519_verify(signature, &self.pk, &to_bytes(&intent_message)), EInvalidSignature);
}

/// Create a BCS-serializable intent message.
public fun create_intent_message<P: drop>(
    intent: u8,
    timestamp_ms: u64,
    payload: P,
): IntentMessage<P> {
    IntentMessage {
        intent,
        timestamp_ms,
        payload,
    }
}

// === View Functions ===

public fun pk<T: drop>(enclave: &Enclave<T>): &vector<u8> {
    &enclave.pk
}

// === Admin Functions ===

/// Destroy an enclave and its admin capability.
/// Aborts with `EInvalidEnclaveCap` if the cap does not match the enclave.
public fun destroy<T: drop>(self: Enclave<T>, cap: EnclaveCap<T>) {
    assert!(cap.enclave_id == self.id.to_inner(), EInvalidEnclaveCap);
    let Enclave { id, .. } = self;
    id.delete();
    let EnclaveCap { id, .. } = cap;
    id.delete();
}

// === Test Functions ===

#[test_only]
use std::string::String;

#[test_only]
public struct SigningPayload has copy, drop {
    location: String,
    temperature: u64,
}

#[test]
fun test_serde() {
    // Serialization must be consistent with Rust — see `fn test_serde` in nautilus-server/app.rs.
    let scope = 0;
    let timestamp = 1744038900000;
    let signing_payload = create_intent_message(
        scope,
        timestamp,
        SigningPayload {
            location: b"San Francisco".to_string(),
            temperature: 13,
        },
    );
    let bytes = to_bytes(&signing_payload);
    assert!(bytes == x"0020b1d110960100000d53616e204672616e636973636f0d00000000000000", 0);
}
