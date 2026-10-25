// Copyright (c) Unconfirmed Labs, LLC
// SPDX-License-Identifier: Apache-2.0

module kagi::enclave_policy;

// === Imports ===

use sui::event::emit;
use sui::nitro_attestation::{NitroAttestationDocument, PCREntry};
use sui::types::is_one_time_witness;

// === Errors ===

const ENotOneTimeWitness: u64 = 0;
const EInvalidPcrLength: u64 = 1;
const EDebugPcrs: u64 = 2;
const EInvalidPcrs: u64 = 3;
const EMissingPcr: u64 = 4;
const EMissingPublicKey: u64 = 5;

// === Constants ===

const PCR_LENGTH: u64 = 48;

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
    self.version = self.version + 1;
    emit(EnclavePolicyPcrsSetEvent<App> {
        policy_id: self.id.to_inner(),
        version: self.version,
        pcr0,
        pcr1,
        pcr2,
    });
    self.pcrs = Pcrs(pcr0, pcr1, pcr2);
}

// === Package Functions ===

public(package) fun load_pk<App: drop>(
    self: &EnclavePolicy<App>,
    document: &NitroAttestationDocument,
): vector<u8> {
    let entries = document.pcrs();
    let pcrs = Pcrs(pcr_at(entries, 0), pcr_at(entries, 1), pcr_at(entries, 2));
    assert!(pcrs == self.pcrs, EInvalidPcrs);
    (*document.public_key()).destroy_or!(abort EMissingPublicKey)
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

// === Test Functions ===

#[test_only]
public fun load_pk_for_testing<App: drop>(
    self: &EnclavePolicy<App>,
    document: &NitroAttestationDocument,
): vector<u8> {
    self.load_pk(document)
}

#[test_only]
public fun pcrs_set_event_fields<App>(
    event: &EnclavePolicyPcrsSetEvent<App>,
): (ID, u64, vector<u8>, vector<u8>, vector<u8>) {
    (event.policy_id, event.version, event.pcr0, event.pcr1, event.pcr2)
}
