// Copyright (c) Unconfirmed Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module kagi::enclave_policy;

use sui::{
    event::emit,
    nitro_attestation::{NitroAttestationDocument, PCREntry},
    types::is_one_time_witness
};

// === Errors ===

const ENotOneTimeWitness: u64 = 0;
const EInvalidPcrLength: u64 = 1;
const EDebugPcrs: u64 = 2;
const EInvalidPcrs: u64 = 3;
const EMissingPcr: u64 = 4;
const EMissingPublicKey: u64 = 5;
const ESamePcrs: u64 = 6;
const EInvalidPublicKeyLength: u64 = 7;

// === Constants ===

const PCR_LENGTH: u64 = 48;
const PUBLIC_KEY_LENGTH: u64 = 32;

// === Structs ===

public struct EnclavePolicy<phantom App: drop> has key {
    id: UID,
    pcrs: Pcrs,
    version: u64,
}

public struct EnclavePolicyCap<phantom App: drop> has key, store {
    id: UID,
}

public struct Pcrs(vector<u8>, vector<u8>, vector<u8>) has copy, drop, store;

// === Events ===

public struct EnclavePolicyCreatedEvent<phantom App> has copy, drop {
    policy_id: ID,
}

public struct EnclavePolicyPcrsSetEvent<phantom App> has copy, drop {
    policy_id: ID,
    version: u64,
    pcr0: vector<u8>,
    pcr1: vector<u8>,
    pcr2: vector<u8>,
}

// === Public Functions ===

public fun new<App: drop>(
    otw: App,
    ctx: &mut TxContext,
): (EnclavePolicy<App>, EnclavePolicyCap<App>) {
    assert!(is_one_time_witness(&otw), ENotOneTimeWitness);
    let policy = EnclavePolicy<App> {
        id: object::new(ctx),
        pcrs: Pcrs(vector[], vector[], vector[]),
        version: 0,
    };
    emit(EnclavePolicyCreatedEvent<App> { policy_id: object::id(&policy) });
    (policy, EnclavePolicyCap { id: object::new(ctx) })
}

public fun share<App: drop>(self: EnclavePolicy<App>) {
    transfer::share_object(self);
}

// === View Functions ===

public fun pcr0<App: drop>(self: &EnclavePolicy<App>): &vector<u8> {
    &self.pcrs.0
}

public fun pcr1<App: drop>(self: &EnclavePolicy<App>): &vector<u8> {
    &self.pcrs.1
}

public fun pcr2<App: drop>(self: &EnclavePolicy<App>): &vector<u8> {
    &self.pcrs.2
}

public fun version<App: drop>(self: &EnclavePolicy<App>): u64 {
    self.version
}

// === Admin Functions ===

public fun set_pcrs<App: drop>(
    self: &mut EnclavePolicy<App>,
    _: &EnclavePolicyCap<App>,
    pcr0: vector<u8>,
    pcr1: vector<u8>,
    pcr2: vector<u8>,
) {
    assert_valid_pcr(&pcr0);
    assert_valid_pcr(&pcr1);
    assert_valid_pcr(&pcr2);
    let pcrs = Pcrs(pcr0, pcr1, pcr2);
    assert!(pcrs != self.pcrs, ESamePcrs);
    self.version = self.version + 1;
    self.pcrs = pcrs;
    let Pcrs(pcr0, pcr1, pcr2) = pcrs;
    emit(EnclavePolicyPcrsSetEvent<App> {
        policy_id: self.id.to_inner(),
        version: self.version,
        pcr0,
        pcr1,
        pcr2,
    });
}

// === Package Functions ===

public(package) fun load_pk<App: drop>(
    self: &EnclavePolicy<App>,
    document: &NitroAttestationDocument,
): vector<u8> {
    let entries = document.pcrs();
    let pcrs = Pcrs(pcr_at(entries, 0), pcr_at(entries, 1), pcr_at(entries, 2));
    assert!(pcrs == self.pcrs, EInvalidPcrs);
    checked_public_key(*document.public_key())
}

public(package) fun uid_mut<App: drop>(self: &mut EnclavePolicy<App>): &mut UID {
    &mut self.id
}

// === Private Functions ===

fun assert_valid_pcr(pcr: &vector<u8>) {
    assert!(pcr.length() == PCR_LENGTH, EInvalidPcrLength);
    assert!(pcr.any!(|byte| *byte != 0), EDebugPcrs);
}

fun pcr_at(entries: &vector<PCREntry>, index: u8): vector<u8> {
    let position = entries.find_index!(|entry| entry.index() == index);
    *entries[position.destroy_or!(abort EMissingPcr)].value()
}

fun checked_public_key(public_key: Option<vector<u8>>): vector<u8> {
    let pk = public_key.destroy_or!(abort EMissingPublicKey);
    assert!(pk.length() == PUBLIC_KEY_LENGTH, EInvalidPublicKeyLength);
    pk
}

// === Test Functions ===

#[test_only]
public fun load_pk_for_testing<App: drop>(
    self: &EnclavePolicy<App>,
    document: &NitroAttestationDocument,
): vector<u8> {
    self.load_pk(document)
}

#[test_only]
public fun pcr_at_for_testing(entries: &vector<PCREntry>, index: u8): vector<u8> {
    pcr_at(entries, index)
}

#[test_only]
public fun checked_public_key_for_testing(public_key: Option<vector<u8>>): vector<u8> {
    checked_public_key(public_key)
}

#[test_only]
public fun created_event_fields<App>(event: &EnclavePolicyCreatedEvent<App>): ID {
    event.policy_id
}

#[test_only]
public fun pcrs_set_event_fields<App>(
    event: &EnclavePolicyPcrsSetEvent<App>,
): (ID, u64, vector<u8>, vector<u8>, vector<u8>) {
    (event.policy_id, event.version, event.pcr0, event.pcr1, event.pcr2)
}
