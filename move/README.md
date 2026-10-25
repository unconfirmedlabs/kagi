# kagi (Move package)

On-chain verification of AWS Nitro Enclave attestations and enclave-signed intent messages. See the [repository README](../README.md) for the API, the usage pattern and the deployment order.

```toml
kagi = { git = "https://github.com/unconfirmedlabs/kagi.git", subdir = "move", rev = "<commit>" }
```

```
sources/enclave_policy.move   EnclavePolicy, PCRs and versioning
sources/enclave.move          Enclave registration, signature verification, destruction
tests/kagi_tests.move         unit tests, using a real Nitro attestation document
```

```sh
sui move build
sui move test --coverage
```
