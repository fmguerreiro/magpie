# Magpie

A macOS menu-bar notification aggregator. Pulls items from multiple sources
into one popover, grouped by source, with type/state icons, author avatars, and
per-row dismiss. Built on SwiftUI `MenuBarExtra` (`.window` style), so the
popover stays open and updates in place.

Sources are adapters. Two ship today:

- **GitHub** — unread notifications via the `gh` CLI (reuses existing auth; no
  token handling, no third-party OAuth app). Each PR/issue is enriched with its
  live state (open / merged / closed / draft / changes-requested / approved).
- **Jira** — assigned + watched + reported issues via `jira-cli`, enriched with
  status category and assignee avatar. "Seen" is local (Jira has no per-issue
  read state): dismissing hides an issue until it next changes.

## Requirements

- macOS 13+
- [`gh`](https://cli.github.com) authenticated (`gh auth status`)
- [`jira-cli`](https://github.com/ankitpokhrel/jira-cli) initialized, if using
  the Jira adapter. Its API token is read from the macOS Keychain and injected
  into the `jira` subprocess (see config).

## Configure

Copy `config.example.json` to `~/.config/magpie/config.json` and fill it in.
`ghPath`/`jiraPath` are optional (the app probes the usual install dirs). Omit
the whole `jira` block to run GitHub-only.

For Jira, store the API token in the Keychain under the service name in your
config (default `magpie-jira`):

```
security add-generic-password -a "you@example.com" -s magpie-jira -w 'YOUR_JIRA_API_TOKEN' -U
```

## Build and install

```
make install      # build Magpie.app and install it to ~/Applications
```

Other targets:

```
make app          # assemble dist/Magpie.app (build + bundle + icon + ad-hoc sign)
make dmg          # package dist/Magpie.dmg for handing to another machine
make icon         # regenerate AppIcon.icns from scripts/make-icon.swift
make build        # compile the release binary only
make clean
```

## Installing on another Mac

`make dmg` produces `dist/Magpie.dmg`; open it and drag Magpie to Applications.

The app is **ad-hoc signed**, not notarized, so a Mac that didn't build it will
quarantine it on first launch ("Magpie can't be opened because Apple cannot
check it for malicious software"). Clear it one of two ways:

- Right-click the app in Finder, choose **Open**, then **Open** again; or
- `xattr -dr com.apple.quarantine /Applications/Magpie.app`

For friction-free distribution you'd sign with an Apple **Developer ID**
certificate and notarize (`xcrun notarytool submit` + `xcrun stapler staple`),
which needs a paid Apple Developer account. The build script's `codesign -s -`
line is where a real signing identity would slot in.

Each machine also needs the runtime prerequisites above (`gh` authenticated,
`jira-cli` initialized + Keychain token) and its own `~/.config/magpie/config.json`.
