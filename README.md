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
| `set_pcrs(self, cap, pcr0, pcr1, pcr2)` | the cap holder | Sets the expected PCRs and increments `version`. Aborts `ESamePcrs` if they equal the current PCRs. |
| `pcr0`, `pcr1`, `pcr2`, `version` | anyone | Views. |

- **`new` emits `EnclavePolicyCreatedEvent`** with the policy ID.
- **One policy per `App`.** `new` takes a one-time witness, so it aborts `ENotOneTimeWitness` for any other type. That's also why the cap needs no object ID: the type identifies the only policy.
- **The PCRs start unset**, because they're known only once the enclave image is built, after the package is published. While they're unset, `enclave::new` aborts `EInvalidPcrs`, since a real document's PCRs are never empty.
- **`set_pcrs` checks each PCR.** Each must be 48 bytes, which is SHA-384 (`EInvalidPcrLength`), and not all zeros (`EDebugPcrs`).
  - A debug-mode enclave reports all-zero PCRs, and its memory is readable from the host. Rejecting zeros means a policy can never admit one.
  - Each call increments `version`, which makes enclaves registered under earlier PCRs stale. Setting the current PCRs again aborts `ESamePcrs`, so `version` never moves without a real change.

### `kagi::enclave`

| Function | Who may call | What it does |
|---|---|---|
| `new(policy, cap, document, ctx)` | the policy's cap holder | Checks the attestation document's PCR0, PCR1 and PCR2, matched by index, against the policy, and requires a 32-byte Ed25519 public key. Returns an `Enclave` holding that key and the policy version, plus a new `EnclaveCap`. |
| `share` | anyone | Shares the enclave. |
| `verify_signature(self, intent, timestamp_ms, payload, signature)` | anyone | Checks an Ed25519 signature over `bcs(IntentMessage { intent, timestamp_ms, payload })`. Aborts `EInvalidSignature`. |
| `create_intent_message` | anyone | Builds the message that `verify_signature` checks. |
| `destroy(self, cap)` | the enclave's cap holder | Deletes the enclave and its `EnclaveCap`. Aborts `EWrongEnclaveCap` for another enclave's cap. |
| `revoke(self, cap)` | the policy's cap holder | Deletes any one enclave of the policy, without its `EnclaveCap`. |
| `destroy_stale(self, policy)` | anyone | Deletes an enclave registered under PCRs that have since changed. Aborts `ENotStale` otherwise. |
| `destroy_cap` | the cap holder | Deletes an `EnclaveCap`, for example after `destroy_stale` or `revoke`. |
| `derive_address(policy, pk)` | anyone | The address an `Enclave` registered under `policy` with `pk` has, or would have. |
| `pk`, `policy_version`, `enclave_cap_enclave_id` (alias `cap.enclave_id()`) | anyone | Views. |

- **Registration needs the policy cap**, so nobody else can register enclaves, even ones running the right image.
- **The `Enclave` ID is derived** from the policy and the public key (`EnclaveKey(pk)`), so `derive_address` and the SDK compute it offline. The `EnclaveCap` is an ordinary new object that stores `enclave_id`.
- **A public key registers once per policy, ever.** The derived ID is claimed on the policy permanently, so registering the same key again aborts `sui::derived_object::EObjectAlreadyExists`, even after the enclave was destroyed, cleared as stale or revoked. A revoked key can never come back; a rebooted enclave generates a new key.
- **The public key must be 32 bytes** (Ed25519), or `new` aborts `EInvalidPublicKeyLength`. A document without one aborts `EMissingPublicKey`, and one without PCR0, PCR1 or PCR2 aborts `EMissingPcr`.
- **`revoke` is the policy admin's kill switch** for a single enclave, for example a compromised one, whoever holds its `EnclaveCap`. It emits the same `EnclaveDestroyedEvent` as the other deletion paths. The orphaned `EnclaveCap` can then only be deleted with `destroy_cap`.
- **Every deletion path is clean.** An `Enclave` has no dynamic fields, so `destroy`, `destroy_stale` and `revoke` leave nothing behind but the policy's permanent claim on the key.
- **`verify_signature` doesn't read the policy**, so verifying adds no shared object to a transaction. To retire an image, the cap holder calls `set_pcrs` and `revoke` (or `destroy`) for the old enclaves in the same PTB. Anyone can clear up leftovers later with `destroy_stale`.
- **Domain separation is the `intent` byte.** Give each kind of message its own intent value.
- **`timestamp_ms` comes from the enclave's clock,** which the host provides. Treat it as the time the enclave claims, not as attested time.

## Usage

```move
module my_app::my_enclave;

use kagi::enclave::{Self, Enclave, EnclaveCap};
use kagi::enclave_policy::{Self, EnclavePolicy, EnclavePolicyCap};
use sui::nitro_attestation::NitroAttestationDocument;

public struct MY_ENCLAVE() has drop;

public struct MyPayload has copy, drop {
    value: u64,
}

const MY_INTENT: u8 = 0;
const ADMIN: address = @0xA11CE;

fun init(otw: MY_ENCLAVE, ctx: &mut TxContext) {
    let (policy, cap) = enclave_policy::new(otw, ctx);
    policy.share();
    transfer::public_transfer(cap, ADMIN);
}

public fun register(
    policy: &mut EnclavePolicy<MY_ENCLAVE>,
    cap: &EnclavePolicyCap<MY_ENCLAVE>,
    document: NitroAttestationDocument,
    ctx: &mut TxContext,
): EnclaveCap<MY_ENCLAVE> {
    let (enclave, enclave_cap) = enclave::new(policy, cap, document, ctx);
    enclave.share();
    enclave_cap
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

- **Send the `EnclavePolicyCap` to an address your app chooses,** such as a multisig. `ADMIN` above is a placeholder; replace it with your own admin address.
  > **Warning:** if the package is published by an ephemeral or throwaway signer, a cap sent to `ctx.sender()` is lost forever. The policy then can never set PCRs, register an enclave or revoke one.
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

nautilus-rust's `NautilusContext::sign_intent` (v0.2.0) signs exactly this layout. The test `intent_message_layout_matches_nautilus_rust` pins the shared vector `0020b1d110960100000d53616e204672616e636973636f0d00000000000000`.

## Events

- `EnclavePolicyCreatedEvent<App> { policy_id }`
- `EnclavePolicyPcrsSetEvent<App> { policy_id, version, pcr0, pcr1, pcr2 }`
- `EnclaveRegisteredEvent<App> { policy_id, enclave_id, policy_version, pk }`
- `EnclaveDestroyedEvent<App> { enclave_id }`, from `destroy`, `destroy_stale` and `revoke`

## Errors

| Module | Constant | Code |
|---|---|---|
| `enclave_policy` | `ENotOneTimeWitness` | 0 |
| `enclave_policy` | `EInvalidPcrLength` | 1 |
| `enclave_policy` | `EDebugPcrs` | 2 |
| `enclave_policy` | `EInvalidPcrs` | 3 |
| `enclave_policy` | `EMissingPcr` | 4 |
| `enclave_policy` | `EMissingPublicKey` | 5 |
| `enclave_policy` | `ESamePcrs` | 6 |
| `enclave_policy` | `EInvalidPublicKeyLength` | 7 |
| `enclave` | `EInvalidSignature` | 0 |
| `enclave` | `EWrongEnclaveCap` | 1 |
| `enclave` | `ENotStale` | 2 |

## TypeScript SDK

`sdk/` (`kagi-sdk`) derives `Enclave` object IDs offline with `deriveEnclaveId(policyId, publicKey, packageId)`, the same value as `enclave::derive_address`. `packageId` is required: it is the published kagi package that defines `EnclaveKey`. `EnclaveCap` IDs aren't derived; read the cap's ID from the registration transaction, or find the enclave's cap by its `enclave_id`. The test suite pins the ID that the Move test `derive_address_matches_the_registered_enclave` asserts, so the two implementations can't drift.

## Deployments

This version hasn't been published. The previous version was published on testnet at `0x68b0993136fdc5aa02275a3a0b51f93e9b7c3b601867ec4a8123a76503665161`, with toolchain 1.66.2. Its API differs: PCRs were set at creation and there was no versioning.

## Building and testing

```sh
cd move && sui move build && sui move test --coverage
cd sdk && bun install && bun run test && bun run typecheck
```

The tests use a real Nitro attestation document from Mysten's weather example. Sui can't build a document that lacks a public key or a PCR, so `EMissingPublicKey`, `EInvalidPublicKeyLength` and `EMissingPcr` are tested through the private helpers that raise them.

## Contact

contact@unconfirmed.com, including security reports.

## License

Apache-2.0.
