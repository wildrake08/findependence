# Evidence so far

The tests below were all written by the same agent that wrote the code, so they show what was
*intended and checked*, not that the system is secure.

## Tests (`cd app && mix test`: 55 tests)

| Area | File | What it shows |
|---|---|---|
| Primitives | `test/crypto_test.exs` | HKDF matches RFC 5869 test case 1; AES-GCM rejects a wrong key, wrong associated data, and a flipped ciphertext; a seal opens only with the recipient's key; the 600,000-iteration floor is enforced |
| Vault scenarios | `test/vault_test.exs` | A wrong passphrase fails; only readers hold keys; revocation removes the key; history is sealed to owners only and re-sealed for new owners; a joiner is presealed only after all owners consent, and a withdrawn invitation removes it; **a byte-level plaintext scan of the written file**; file mode 0600 |
| **Model test** | `test/model_test.exs` | 500 random sequences of 40 operations. Every operation runs both on a trusted in-memory model and through an encrypted session (save, reopen). After every step, **each member's decrypted view equals the model's**, no member can open keys sealed to others, and **no false tamper alarm occurs** |
| **Tampering** | `test/tamper_test.exs` | Attacks F-01 (reader and owner injection, including history) and F-02 (key substitution) are blocked and reported |
| Fresh process | `test/fresh_process_test.exs` | A separate, freshly started BEAM process reads and unlocks a vault and sees exactly what the warm process sees |
| Interface | `test/web_test.exs`, `web_ux_test.exs`, `sharing_section_test.exs` | Loopback bind, Host rejection, CSRF, wrong passphrase gives 401, logout drops keys, idle lock, CSP and no remote URLs, **HTML escaping**, no HTTP-client code or dependencies |
| Tasks | `test/tasks_test.exs` | Setup creates vaults that can be unlocked, hides input, and fails cleanly; serve explains a missing file |

## Mutation testing

Each security rule was deliberately broken and the suite re-run. **Every break was detected**
(results are in `project/assurance/runs/TEST-RUN-010.txt`, `-011.txt`, `-012.txt`, and WI-018 and
WI-020):

- **Vault:** key sealed to every member; revoked keys kept; history sealed to grantees; no
  presealing; content in plaintext; KEK not derived from the passphrase.
- **Interface:** any Host accepted; CSRF removed; CSP removed; bind to 0.0.0.0; no idle lock;
  escaping removed; logout keeps keys.
- **Tampering:** seal to keyless readers; new or old history sealed to injected owners; seal to the
  file's key instead of the pinned one; no key-change detection.

**Two mutations were initially undetected** because the tests were vacuous. Both tests were
rewritten, and the mutations are now detected.

## Live checks

`LIVE-RUN-001`: on the real server, loopback gives 200, a forged Host gives 421, and the
non-loopback address is refused. `UI-RUN-001` and `UI-RUN-002`: headless-browser checks of the
interface.

## Reproduction

Test results were reproduced from clean checkouts of specific commits (`REPRO-RUN-001..003`).

## What this evidence does NOT cover

- Anything outside the test inputs we thought of.
- Side channels, memory disclosure, and OS-level behaviour.
- Correctness of Erlang, OpenSSL, Plug, or Bandit.
- Usability of the security features: whether members understand locking, sharing, and warnings.
  That is STUDY-001's job.
