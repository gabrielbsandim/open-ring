# Contributing to OpenRing

Thanks for helping. This file covers how to run the checks and the rules every
change follows. The plan and its decisions log live in
[`docs/plan.md`](docs/plan.md); read the decision that covers your area before
changing it.

## Setup

Flutter stable with Dart 3.13.5 or newer. From the repository root:

```sh
flutter pub get
```

That resolves the whole pub workspace (`apps/mobile`, `packages/*`,
`tools/trace_replay`).

## Checks

CI (`.github/workflows/ci.yml`) runs these on every push and pull request. Run
them before you open one.

```sh
dart format --output=none --set-exit-if-changed .   # from the root
flutter analyze                                     # from the root, lints every package
dart test                                           # in packages/ring_protocol, ring_driver and metrics
flutter gen-l10n && flutter test                    # in apps/mobile
```

Useful subsets:

- `flutter test test/app/layout_matrix_test.dart` runs the layout matrix (text
  scale 1.0, 1.3 and 2.0, dark and light, English and German). A layout
  overflow fails it.
- `flutter test test/release/store_listing_test.dart` checks the store listing
  under `apps/mobile/fastlane/metadata/android`: one folder per app locale, the
  Play Console length limits, no em or en dash.
- `dart run tools/trace_replay/bin/trace_replay.dart decode session.jsonl`
  replays a recorded frame session through the parsers without a ring (see
  `tools/trace_replay/README.md`).

A change to the drift schema needs a new schema dump and a migration test under
`apps/mobile/test/drift`.

## Rules

Language and text:

- Code, comments, identifiers, commit messages and docs are in English. User
  facing copy goes through the ARB files in `apps/mobile/lib/l10n`, one entry
  per locale, with English as the fallback.
- Never use the em dash character, anywhere: code, docs, ARB strings, commit
  messages, store copy. Use a comma, a colon or parentheses.
- No medical claims. A score is an estimate for following trends, never a
  diagnosis.

Code:

- Guard clauses and early returns. No `if` nested inside another `if`, no
  `else` after a `return`, no nested ternaries. Three or more branches on the
  same value become a `switch` or a table.
- No comments that narrate what a line does. A comment may explain a non
  obvious why, in at most 2 lines.
- `domain` imports nothing from Flutter. Platform code sits behind a port with
  a fake for tests.
- No colour literal outside the theme; screens read tokens from
  [`docs/design-tokens.md`](docs/design-tokens.md) through the theme. No fixed
  height on anything that holds text.
- Every new screen gets widget tests at text scale 1.0, 1.3 and 2.0, in dark
  and light.
- No network access beyond the Shorebird updater, and no analytics. A change
  that needs the network is a plan decision first, and the privacy policy
  changes with it.

Commits and pull requests:

- Short messages in the form `type: title` (`feat`, `fix`, `docs`, `chore`,
  `refactor`, `test`), no body needed.
- One topic per pull request. Protocol changes link the captured trace that
  proves them.

## Hardware claims

Only the COLMI R09 is tested. Do not mark a ring as supported, or a protocol
command as verified, without a frame captured from that ring and checked in as a protocol test.
