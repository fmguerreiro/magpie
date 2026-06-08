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

## Build and run

```
swift build -c release
```

To run as a proper menu-bar agent (no Dock icon), wrap the binary in an app
bundle with `LSUIElement` set, then `open` it.
