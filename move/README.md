# kagi (Move package)

On-chain verification of AWS Nitro Enclave attestations and enclave-signed intent messages. See the [repository README](../README.md) for the API, the usage pattern and the deployment order.

```toml
kagi = { git = "https://github.com/unconfirmedlabs/kagi.git", subdir = "move", rev = "<commit>" }
```

```
sources/enclave_policy.move   EnclavePolicy, PCRs and versioning, attestation checks
sources/enclave.move          Enclave registration, derive_address, signature verification, destroy and revoke
tests/kagi_tests.move         unit tests, using a real Nitro attestation document
```

```sh
sui move build
sui move test --coverage
sui move coverage summary
```

API changes in this version: caps are renamed `EnclaveAdminCap` and `EnclavePolicyAdminCap`; `enclave::revoke` and `enclave::derive_address` are new; `set_pcrs` aborts `ESamePcrs` on unchanged PCRs; registration aborts `EInvalidPublicKeyLength` for a key that isn't 32 bytes; `enclave_policy::new` emits `EnclavePolicyCreatedEvent`. Details and error codes are in the repository README.

Contact: contact@unconfirmed.com
