# Findependence local prototype

This is a research prototype for STUDY-001. **It must not be used with a real household** until
it has had an independent security review (DEF-026), independent ethics review, and a
professional check of the Washington notes (GATE-016).

All data stays in one encrypted file on this device, and the server accepts connections only
from this device (127.0.0.1).

```sh
cd app
mix deps.get

# Create a household. Each person types their own passphrase privately; it is not echoed.
mix findependence.setup ../household.vault ana ben

# Start the local interface, then open http://127.0.0.1:4848/ in a browser on this device.
mix findependence.serve ../household.vault 4848
```

## What is encrypted, and what is not

- **Encrypted:** item contents and amounts, value labels, links, item histories, and deletion
  records. Each is readable only by the members allowed to see it.
- **Not encrypted** (ASM-020): member names, public keys, random item identifiers, who owns
  and who can see each item, and the shape of pending proposals. The consent materials must say so.
- **One person at a time.** Logging in locks out any other session. A session locks after
  15 minutes idle.
- **Forgotten passphrases cannot be recovered.** There is no reset.
