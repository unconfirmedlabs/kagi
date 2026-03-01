// Copyright (c), Subsonic Labs, LLC
// SPDX-License-Identifier: Apache-2.0

module enclave::enclave;

use enclave::enclave_policy::{EnclavePolicy, EnclavePolicyCap};
use std::bcs::to_bytes;
use sui::ed25519::ed25519_verify;
use sui::nitro_attestation::NitroAttestationDocument;

// === Structs ===

/// A verified enclave instance, with its public key.
public struct Enclave<phantom T: drop> has key {
    id: UID,
    pk: vector<u8>,
}

/// A capability granting admin control over an `Enclave`.
public struct EnclaveCap<phantom T: drop> has key, store {
    id: UID,
}

/// An intent message, used for wrapping enclave messages for signing.
public struct IntentMessage<T: drop> has copy, drop {
    intent: u8,
    timestamp_ms: u64,
    payload: T,
}

// === Public Functions ===

/// Register a new enclave by verifying a Nitro attestation document.
/// The `Enclave` is shared and an `EnclaveCap` is returned to the caller.
public fun new<T: drop>(
    _: &EnclavePolicyCap<T>,
    policy: &EnclavePolicy<T>,
    document: NitroAttestationDocument,
    ctx: &mut TxContext,
): (Enclave<T>, EnclaveCap<T>) {
    let pk = policy.load_pk(&document);

    let enclave = Enclave<T> {
        id: object::new(ctx),
        pk,
    };

    let enclave_cap = EnclaveCap<T> {
        id: object::new(ctx),
    };

    (enclave, enclave_cap)
}

/// Verify an enclave signature over an intent message.
public fun verify_signature<T: drop, P: drop>(
    self: &Enclave<T>,
    intent_scope: u8,
    timestamp_ms: u64,
    payload: P,
    signature: &vector<u8>,
): bool {
    let intent_message = create_intent_message(intent_scope, timestamp_ms, payload);
    ed25519_verify(signature, &self.pk, &to_bytes(&intent_message))
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
public fun destroy<T: drop>(self: Enclave<T>, cap: EnclaveCap<T>) {
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
    let bytes = bcs::to_bytes(&signing_payload);
    assert!(bytes == x"0020b1d110960100000d53616e204672616e636973636f0d00000000000000", 0);
}
