// Copyright (c) Unconfirmed Labs, LLC
// SPDX-License-Identifier: Apache-2.0

module kagi::enclave;

// === Imports ===

use std::bcs;
use sui::derived_object;
use sui::ed25519::ed25519_verify;
use sui::event::emit;
use sui::nitro_attestation::NitroAttestationDocument;
use kagi::enclave_policy::{EnclavePolicy, EnclavePolicyCap};

// === Errors ===

const EInvalidSignature: u64 = 0;
const EWrongEnclaveCap: u64 = 1;
const ENotStale: u64 = 2;

// === Structs ===

public struct Enclave<phantom App: drop> has key {
    id: UID,
    pk: vector<u8>,
    policy_version: u64,
}

public struct EnclaveCap<phantom App: drop> has key, store {
    id: UID,
    enclave_id: ID,
}

public struct IntentMessage<Payload: drop> has copy, drop {
    intent: u8,
    timestamp_ms: u64,
    payload: Payload,
}

public struct EnclaveKey(vector<u8>) has copy, drop, store;

public struct EnclaveCapKey() has copy, drop, store;

// === Events ===

public struct EnclaveRegisteredEvent<phantom App> has copy, drop {
    policy_id: ID,
    enclave_id: ID,
    policy_version: u64,
    pk: vector<u8>,
}

public struct EnclaveDestroyedEvent<phantom App> has copy, drop {
    enclave_id: ID,
}

// === Public Functions ===

public fun new<App: drop>(
    policy: &mut EnclavePolicy<App>,
    _: &EnclavePolicyCap<App>,
    document: NitroAttestationDocument,
): (Enclave<App>, EnclaveCap<App>) {
    let pk = policy.load_pk(&document);
    let policy_id = object::id(policy);
    let policy_version = policy.version();
    let mut enclave = Enclave<App> {
        id: derived_object::claim(policy.uid_mut(), EnclaveKey(pk)),
        pk,
        policy_version,
    };
    let enclave_id = enclave.id.to_inner();
    let cap = EnclaveCap<App> {
        id: derived_object::claim(&mut enclave.id, EnclaveCapKey()),
        enclave_id,
    };
    emit(EnclaveRegisteredEvent<App> { policy_id, enclave_id, policy_version, pk });
    (enclave, cap)
}

public fun share<App: drop>(self: Enclave<App>) {
    transfer::share_object(self);
}

public fun verify_signature<App: drop, Payload: drop>(
    self: &Enclave<App>,
    intent: u8,
    timestamp_ms: u64,
    payload: Payload,
    signature: &vector<u8>,
) {
    let message = bcs::to_bytes(&create_intent_message(intent, timestamp_ms, payload));
    assert!(ed25519_verify(signature, &self.pk, &message), EInvalidSignature);
}

public fun create_intent_message<Payload: drop>(
    intent: u8,
    timestamp_ms: u64,
    payload: Payload,
): IntentMessage<Payload> {
    IntentMessage { intent, timestamp_ms, payload }
}

public fun destroy<App: drop>(self: Enclave<App>, cap: EnclaveCap<App>) {
    assert!(cap.enclave_id == self.id.to_inner(), EWrongEnclaveCap);
    let EnclaveCap { id, enclave_id: _ } = cap;
    id.delete();
    delete(self);
}

public fun destroy_stale<App: drop>(self: Enclave<App>, policy: &EnclavePolicy<App>) {
    assert!(self.policy_version < policy.version(), ENotStale);
    delete(self);
}

public fun destroy_cap<App: drop>(cap: EnclaveCap<App>) {
    let EnclaveCap { id, enclave_id: _ } = cap;
    id.delete();
}

// === View Functions ===

public fun pk<App: drop>(self: &Enclave<App>): &vector<u8> {
    &self.pk
}

public fun policy_version<App: drop>(self: &Enclave<App>): u64 {
    self.policy_version
}

public fun enclave_cap_enclave_id<App: drop>(cap: &EnclaveCap<App>): ID {
    cap.enclave_id
}

// === Private Functions ===

fun delete<App: drop>(enclave: Enclave<App>) {
    let Enclave { id, .. } = enclave;
    emit(EnclaveDestroyedEvent<App> { enclave_id: id.to_inner() });
    id.delete();
}

// === Test Functions ===

#[test_only]
public fun new_for_testing<App: drop>(
    pk: vector<u8>,
    policy_version: u64,
    ctx: &mut TxContext,
): Enclave<App> {
    Enclave { id: object::new(ctx), pk, policy_version }
}

#[test_only]
public fun destroy_for_testing<App: drop>(self: Enclave<App>) {
    let Enclave { id, .. } = self;
    id.delete();
}

#[test_only]
public fun registered_event_fields<App>(
    event: &EnclaveRegisteredEvent<App>,
): (ID, ID, u64, vector<u8>) {
    (event.policy_id, event.enclave_id, event.policy_version, event.pk)
}

#[test_only]
public fun destroyed_event_fields<App>(event: &EnclaveDestroyedEvent<App>): ID {
    event.enclave_id
}
