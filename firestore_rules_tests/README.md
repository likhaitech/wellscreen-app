# Firestore Security Rules Tests

Real tests for `../firestore.rules`, run against the actual Firestore
emulator via `@firebase/rules-unit-testing` - not a static read-through of
the rules file, and not a mock. Each test performs a real read/write against
a real (local, throwaway) Firestore instance and checks whether the rules
actually allow or deny it.

## Why this exists

Before this, `firestore.rules` had never been run against anything - it was
written by carefully reading every `FirebaseFirestore.instance.collection(...)`
call in `mobile_app/lib` (see the comments in the rules file itself), which
is a reasonable way to *write* rules but not a way to *verify* them. A typo,
an inverted condition, or a rule that looks right but doesn't parse the way
you'd expect are all things manual reading won't reliably catch.

## What's covered

One `describe()` block per collection in `firestore.rules`, following the
exact scenarios documented in that file's own per-collection comments:
who's allowed to read/write, the two privilege-escalation fixes (`role`
locked to `parent`/`child` on create, immutable after), the pairing-code
claim flow (including "can't reuse an already-connected code" and "can't
re-claim an already-claimed child profile"), and the deny-by-default
fallback for anything not explicitly modeled - including the flagged-dead
camelCase `pairingCodes` collection the rules file's comments call out by
name.

## Running

Requires Node and a JDK (the Firestore emulator runs on the JVM). Not
runnable in every environment - the emulator binary is downloaded on first
run from `storage.googleapis.com`, which some sandboxed/restricted-network
environments block; GitHub Actions runners (see
`.github/workflows/firestore-rules-test.yml`) have unrestricted egress and
are the environment this was actually verified in.

```bash
npm install
npm test
```

`npm test` starts a real local Firestore emulator, loads the real
`firestore.rules` file into it, runs every test against it, then tears the
emulator down. `pretest` copies `../firestore.rules` into this directory
first because the Firebase CLI refuses a rules path that escapes the
project directory (`../firestore.rules` outside this folder) - the copy is
gitignored, not a second source of truth.
