// Copyright (c), Subsonic Labs, LLC
// SPDX-License-Identifier: Apache-2.0

module nautilus_enclave::enclave_policy;

use sui::nitro_attestation::NitroAttestationDocument;
use sui::types::is_one_time_witness;

// === Imports ===

use fun to_pcrs as NitroAttestationDocument.to_pcrs;

// === Errors ===

const EInvalidPCRs: u64 = 0;
const ENotOneTimeWitness: u64 = 1;

// === Structs ===

/// PCR0: Enclave image file
/// PCR1: Enclave Kernel
/// PCR2: Enclave application
public struct Pcrs(vector<u8>, vector<u8>, vector<u8>) has copy, drop, store;

/// The expected PCRs for a Nitro enclave.
/// Only defines the first 3 PCRs. Additional PCRs and/or fields
/// (e.g. user_data) can be added if necessary.
/// See https://docs.aws.amazon.com/enclaves/latest/user/set-up-attestation.html#where
public struct EnclavePolicy<phantom T: drop> has key {
    id: UID,
    pcrs: Pcrs,
}

/// A capability granting admin control over an `EnclavePolicy`.
public struct EnclavePolicyCap<phantom T: drop> has key, store {
    id: UID,
}

// === Public Functions ===

/// Create and share a new `EnclavePolicy`.
public fun new<T: drop>(
    otw: T,
    pcr0: vector<u8>,
    pcr1: vector<u8>,
    pcr2: vector<u8>,
    ctx: &mut TxContext,
): (EnclavePolicy<T>, EnclavePolicyCap<T>) {
    assert!(is_one_time_witness(&otw), ENotOneTimeWitness);

    let config = EnclavePolicy<T> {
        id: object::new(ctx),
        pcrs: Pcrs(pcr0, pcr1, pcr2),
    };

    let cap = EnclavePolicyCap {
        id: object::new(ctx),
    };

    (config, cap)
}

public fun share<T: drop>(self: EnclavePolicy<T>) {
    transfer::share_object(self);
}

// === View Functions ===

public fun pcr0<T: drop>(config: &EnclavePolicy<T>): &vector<u8> {
    &config.pcrs.0
}

public fun pcr1<T: drop>(config: &EnclavePolicy<T>): &vector<u8> {
    &config.pcrs.1
}

public fun pcr2<T: drop>(config: &EnclavePolicy<T>): &vector<u8> {
    &config.pcrs.2
}

// === Admin Functions ===

/// Update the expected PCRs.
public fun update_pcrs<T: drop>(
    config: &mut EnclavePolicy<T>,
    _cap: &EnclavePolicyCap<T>,
    pcr0: vector<u8>,
    pcr1: vector<u8>,
    pcr2: vector<u8>,
) {
    config.pcrs = Pcrs(pcr0, pcr1, pcr2);
}

// === Package Functions ===

/// Validate an attestation document against the config's PCRs and extract the public key.
public(package) fun load_pk<T: drop>(
    self: &EnclavePolicy<T>,
    document: &NitroAttestationDocument,
): vector<u8> {
    assert!(document.to_pcrs() == self.pcrs, EInvalidPCRs);
    (*document.public_key()).destroy_some()
}

// === Private Functions ===

fun to_pcrs(document: &NitroAttestationDocument): Pcrs {
    let pcrs = document.pcrs();
    Pcrs(*pcrs[0].value(), *pcrs[1].value(), *pcrs[2].value())
}
