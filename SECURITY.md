# Security policy

NCM Online is a live multiplayer server. Please report security problems **privately**.

## How to report

Use GitHub's private vulnerability reporting:
**[Report a vulnerability](https://github.com/evengineer1ng/ncm-online/security/advisories/new)**.

Please **do not** open a public issue, post exploit details anywhere public, or test a vulnerability against other
players or their data.

Useful to include: what is affected (server resource, client resource, native plugin, website), how to reproduce it,
what an attacker could do, and any fix you suggest.

## What counts

- Server-side: anything that lets a client change money, ownership, results, condition or another player's state
  outside the rules; trust-boundary bypasses between client and server; anything that crashes or stalls the server
  from a client.
- Native plugins: memory safety, the loopback ports (127.0.0.1), anything a web page or another local process could
  abuse.
- Secrets: any credential, key or private data you find in the repository or its history.

Gameplay exploits that only affect your own progression on an alpha server can go through the normal bug template.
If you're unsure, report privately.

## What to expect

This is a one-person project. You will get an acknowledgement as soon as possible, and a fix or an explanation.
Fixes are deployed to the Online server first. Credit is given in the changelog if you want it.

## Supported versions

Only the current `main` branch, and the build running on the public NCM Online server.
