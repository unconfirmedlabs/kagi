# Kagi

A Sui Move library for verifying [AWS Nitro Enclave](https://aws.amazon.com/ec2/nitro/nitro-enclaves/) attestations and enclave-signed messages on-chain.

Kagi enables smart contracts to trust off-chain computation by verifying that it ran inside a specific, auditable enclave. It works with [Nautilus](https://github.com/MystenLabs/nautilus) enclaves and Sui's native `NitroAttestationDocument` support.

## How It Works

Kagi follows a two-step model:

1. **Policy** -- Define the expected enclave identity (PCR values) using an `EnclavePolicy`.
2. **Enclave** -- Register an enclave instance by verifying a Nitro attestation document against the policy, then use it to verify signed messages on-chain.

```
                 Nitro Attestation
                    Document
                       |
                       v
 ┌──────────────┐   ┌──────────────┐   ┌──────────────┐
 │ EnclavePolicy│──>│   Enclave    │──>│   Verify     │
 │ (PCR values) │   │ (public key) │   │  Signature   │
 └──────────────┘   └──────────────┘   └──────────────┘
```

## Modules

### `kagi::enclave_policy`

Manages the expected identity of a Nitro enclave via [PCR values](https://docs.aws.amazon.com/enclaves/latest/user/set-up-attestation.html#where) (Platform Configuration Registers).

| Function | Description |
|---|---|
| `new` | Create a new `EnclavePolicy` using a one-time witness and PCR0/1/2 values. |
| `share` | Share the policy as a shared object. |
| `update_pcrs` | Update the expected PCRs (requires `EnclavePolicyCap`). |
| `pcr0`, `pcr1`, `pcr2` | Read the current PCR values. |

### `kagi::enclave`

Represents a verified enclave instance and provides signature verification.

| Function | Description |
|---|---|
| `new` | Register an enclave by verifying a `NitroAttestationDocument` against an `EnclavePolicy`. Returns an `Enclave` and its `EnclaveCap`. UIDs are deterministically derived from the policy and public key. |
| `share` | Share the enclave as a shared object. |
| `verify_signature` | Verify an Ed25519 signature over a BCS-serialized intent message. Aborts on failure. |
| `create_intent_message` | Create a BCS-serializable intent message from scope, timestamp, and payload. |
| `destroy` | Destroy an enclave and its cap. The cap must match the enclave. |

## Usage

### 1. Define your enclave type and policy

```move
module my_app::my_enclave;

use kagi::enclave_policy;

public struct MY_ENCLAVE has drop {}

fun init(otw: MY_ENCLAVE, ctx: &mut TxContext) {
    let (policy, cap) = enclave_policy::new(
        otw,
        x"<pcr0>",
        x"<pcr1>",
        x"<pcr2>",
        ctx,
    );
    policy.share();
    transfer::public_transfer(cap, ctx.sender());
}
```

### 2. Register an enclave

```move
use kagi::enclave;

public fun register(
    cap: &EnclavePolicyCap<MY_ENCLAVE>,
    policy: &mut EnclavePolicy<MY_ENCLAVE>,
    document: NitroAttestationDocument,
    ctx: &mut TxContext,
) {
    let (enclave, enclave_cap) = enclave::new(cap, policy, document);
    enclave.share();
    transfer::public_transfer(enclave_cap, ctx.sender());
}
```

Enclave and EnclaveCap UIDs are deterministically derived from the policy and public key, so no `TxContext` is needed for `enclave::new`. The `ctx` above is only used for `transfer`.

### 3. Verify enclave-signed messages

```move
const MY_INTENT: u8 = 0;

public struct MyPayload has drop {
    value: u64,
}

public fun do_something(
    enclave: &Enclave<MY_ENCLAVE>,
    timestamp_ms: u64,
    sig: &vector<u8>,
) {
    let payload = MyPayload { value: 42 };
    enclave.verify_signature(MY_INTENT, timestamp_ms, payload, sig);
    // signature is valid -- proceed with trusted data
}
```

### Serialization

Intent messages are BCS-serialized as `IntentMessage<P>`:

```
┌────────┬──────────────┬─────────┐
│ intent │ timestamp_ms │ payload │
│  u8    │    u64       │   P     │
└────────┴──────────────┴─────────┘
```

The enclave server must produce Ed25519 signatures over the same BCS encoding. Use `create_intent_message` and the included `test_serde` test as a reference for cross-language BCS compatibility.

## Errors

### `kagi::enclave`

| Constant | Code | Description |
|---|---|---|
| `EInvalidSignature` | 0 | Ed25519 signature verification failed. |
| `EInvalidEnclaveCap` | 1 | The `EnclaveCap` does not match the `Enclave` being destroyed. |

### `kagi::enclave_policy`

| Constant | Code | Description |
|---|---|---|
| `EInvalidPCRs` | 0 | Attestation document PCRs do not match the policy. |
| `ENotOneTimeWitness` | 1 | The witness passed to `new` is not a valid one-time witness. |
| `EMissingPublicKey` | 2 | Attestation document does not contain a public key. |

## Deployments

| Network | Package ID |
|---|---|
| Testnet | `0x2cbdd9425600a1c2a4772f2e5c92d77feda423a21ed44c703e526852bd9f8247` |

## Building

```sh
sui move build
```

## Testing

```sh
sui move test
```

## License

Apache 2.0
