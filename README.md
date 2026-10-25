# Kagi

A Sui Move library for verifying [AWS Nitro Enclave](https://aws.amazon.com/ec2/nitro/nitro-enclaves/) attestations and enclave-signed messages on-chain. It is the on-chain half of [nautilus-rust](https://github.com/unconfirmedlabs/nautilus-rust), and it works with any [Nautilus](https://github.com/MystenLabs/nautilus) enclave through Sui's native `NitroAttestationDocument`.

```
 Nitro attestation document
            |
            v
 EnclavePolicy<App> --(cap)--> Enclave<App> --> verify_signature
   PCRs + version              public key
```

Kagi has two steps:
1. An **`EnclavePolicy<App>`** names the enclave image that's trusted: its PCR0, PCR1 and PCR2.
2. An **`Enclave<App>`** is a registered instance. Its public key came out of an attestation document that matched the policy. Move code then checks the enclave's signatures over intent messages.

## Modules

### `kagi::enclave_policy`

| Function | Who may call | What it does |
|---|---|---|
| `new<App>(otw, ctx)` | the app's `init` | Creates the one policy for `App`, with its PCRs unset, and returns it with its `EnclavePolicyCap`. |
| `share` | anyone | Shares the policy. |
| `set_pcrs(self, cap, pcr0, pcr1, pcr2)` | the cap holder | Sets the expected PCRs and increments `version`. |
| `pcr0`, `pcr1`, `pcr2`, `version` | anyone | Views. |

- **One policy per `App`.** `new` takes a one-time witness, so it aborts `ENotOneTimeWitness` for any other type. That's also why the cap needs no object ID: the type identifies the only policy.
- **The PCRs start unset**, because they're known only once the enclave image is built, after the package is published. While they're unset, `enclave::new` aborts `EInvalidPcrs`, since a real document's PCRs are never empty.
- **`set_pcrs` checks each PCR.** Each must be 48 bytes, which is SHA-384 (`EInvalidPcrLength`), and not all zeros (`EDebugPcrs`).
  - A debug-mode enclave reports all-zero PCRs, and its memory is readable from the host. Rejecting zeros means a policy can never admit one.
  - Each call increments `version`, which makes enclaves registered under earlier PCRs stale.

### `kagi::enclave`

| Function | Who may call | What it does |
|---|---|---|
| `new(policy, cap, document)` | the policy's cap holder | Checks the attestation document's PCR0, PCR1 and PCR2, matched by index, against the policy. Returns an `Enclave` holding the document's public key and the policy version, plus its `EnclaveCap`. |
| `share` | anyone | Shares the enclave. |
| `verify_signature(self, intent, timestamp_ms, payload, signature)` | anyone | Checks an Ed25519 signature over `bcs(IntentMessage { intent, timestamp_ms, payload })`. Aborts `EInvalidSignature`. |
| `create_intent_message` | anyone | Builds the message that `verify_signature` checks. |
| `destroy(self, cap)` | the enclave's cap holder | Deletes the enclave. Aborts `EWrongEnclaveCap` for another enclave's cap. |
| `destroy_stale(self, policy)` | anyone | Deletes an enclave registered under PCRs that have since changed. Aborts `ENotStale` otherwise. |
| `destroy_cap` | the cap holder | Deletes an `EnclaveCap`, for example after `destroy_stale`. |
| `pk`, `policy_version`, `enclave_cap_enclave_id` | anyone | Views. |

- **Registration needs the policy cap**, so nobody else can register enclaves, even ones running the right image.
- **The IDs are derived.** The `Enclave` ID is derived from the policy and the public key, and the `EnclaveCap` ID from the enclave. Registering the same key twice aborts.
- **`verify_signature` doesn't read the policy**, so verifying adds no shared object to a transaction. To retire an image, the cap holder calls `set_pcrs` and `destroy` for the old enclaves in the same PTB. Anyone can clear up leftovers later with `destroy_stale`.
- **Domain separation is the `intent` byte.** Give each kind of message its own intent value.
- **`timestamp_ms` comes from the enclave's clock,** which the host provides. Treat it as the time the enclave claims, not as attested time.

## Usage

```move
module my_app::my_enclave;

use kagi::enclave::{Self, Enclave};
use kagi::enclave_policy::{Self, EnclavePolicy, EnclavePolicyCap};
use sui::nitro_attestation::NitroAttestationDocument;

public struct MY_ENCLAVE() has drop;

public struct MyPayload has copy, drop {
    value: u64,
}

const MY_INTENT: u8 = 0;

fun init(otw: MY_ENCLAVE, ctx: &mut TxContext) {
    let (policy, cap) = enclave_policy::new(otw, ctx);
    policy.share();
    transfer::public_transfer(cap, ctx.sender());
}

public fun register(
    policy: &mut EnclavePolicy<MY_ENCLAVE>,
    cap: &EnclavePolicyCap<MY_ENCLAVE>,
    document: NitroAttestationDocument,
    ctx: &mut TxContext,
) {
    let (enclave, enclave_cap) = enclave::new(policy, cap, document);
    enclave.share();
    transfer::public_transfer(enclave_cap, ctx.sender());
}

public fun consume(
    enclave: &Enclave<MY_ENCLAVE>,
    value: u64,
    timestamp_ms: u64,
    signature: vector<u8>,
) {
    enclave.verify_signature(MY_INTENT, timestamp_ms, MyPayload { value }, &signature);
}
```

- **Take `Enclave<MY_ENCLAVE>`, never a generic `Enclave<T>`.** A generic parameter would let an enclave registered for any other app sign for yours.
- **Get the document from `sui::nitro_attestation::load_nitro_attestation(bytes, clock)`** in the same PTB. It checks the AWS certificate chain at the clock's time.
- **Deployment order:**
  1. Publish the package.
  2. Build the enclave image and record its PCRs.
  3. Call `set_pcrs`.
  4. Boot the enclave and register it.

### Intent messages

```
┌────────┬──────────────────┬───────────────┐
│ intent │ timestamp_ms     │ payload       │
│ u8     │ u64 little-end.  │ BCS of P      │
└────────┴──────────────────┴───────────────┘
```

nautilus-rust's `NautilusContext::sign_bcs_payload` signs exactly this layout. The test `intent_message_layout_matches_nautilus_rust` pins the shared vector `0020b1d110960100000d53616e204672616e636973636f0d00000000000000`.

## Events

- `EnclavePolicyPcrsSetEvent<App> { policy_id, version, pcr0, pcr1, pcr2 }`
- `EnclaveRegisteredEvent<App> { policy_id, enclave_id, policy_version, pk }`
- `EnclaveDestroyedEvent<App> { enclave_id }`

## Errors

| Module | Constant | Code |
|---|---|---|
| `enclave_policy` | `ENotOneTimeWitness` | 0 |
| `enclave_policy` | `EInvalidPcrLength` | 1 |
| `enclave_policy` | `EDebugPcrs` | 2 |
| `enclave_policy` | `EInvalidPcrs` | 3 |
| `enclave_policy` | `EMissingPcr` | 4 |
| `enclave_policy` | `EMissingPublicKey` | 5 |
| `enclave` | `EInvalidSignature` | 0 |
| `enclave` | `EWrongEnclaveCap` | 1 |
| `enclave` | `ENotStale` | 2 |

## TypeScript SDK

`sdk/` (`kagi-sdk`) derives `Enclave` and `EnclaveCap` object IDs offline, using `deriveEnclaveId(policyId, publicKey, packageId?)`, `deriveEnclaveCapId(enclaveId, packageId?)` and `deriveEnclaveIds(...)`. The derivation keys haven't changed. Its default package ID is the earlier testnet deployment, so pass `packageId` for the current package.

## Deployments

This version hasn't been published. The previous version was published on testnet at `0x68b0993136fdc5aa02275a3a0b51f93e9b7c3b601867ec4a8123a76503665161`, with toolchain 1.66.2. Its API differs: PCRs were set at creation and there was no versioning.

## Building and testing

```sh
cd move && sui move build && sui move test --coverage
cd sdk && bun install && bun test
```

The tests use a real Nitro attestation document from Mysten's weather example. They can't build documents that lack a public key or a PCR, so `EMissingPublicKey` and `EMissingPcr` are untested.

## License

Apache-2.0.
