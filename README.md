# Proxyn

A native iOS app for monitoring and managing Proxmox VE — a single node or a whole cluster — without opening a browser.

SwiftUI, iOS 18+, no third-party dependencies. The app talks directly to the Proxmox REST API on your servers; nothing goes through a service run by anyone else.

## Features

**Monitoring** — Cluster CPU (weighted by core count), memory, storage (shared storage counted once) and network throughput. Interactive RRD charts for the past hour, day, week, month or year. Alerts for lost quorum, offline nodes, full storage, low memory and failed tasks.

**Guests** — Start, shut down, reboot, suspend, resume, force stop and reset. Snapshots (with RAM), backups (take, restore, protect, delete), clone, migrate, resize disks, edit CPU and memory, start at boot, protection, firewall. Guest-agent IP addresses. noVNC and xterm.js consoles.

**Nodes** — Status, load, hardware, disks and SMART health, network interfaces, services, pending package updates, task history, start/stop all guests, reboot, shut down, shell.

**Storage** — Usage grouped by node, content browser with search and filters, delete and protect volumes, download ISOs and container templates to a storage from a URL.

**Activity** — Cluster task history grouped by day, live task logs, stop running tasks, scheduled backup and replication jobs.

**Widgets** — Cluster, Guest (configurable, with a Start button), Nodes, Storage and Activity for the Home Screen, plus Lock Screen accessories. Widgets deep-link to the matching screen.

**Demo mode** — "Try the Demo" loads a simulated three-node cluster served in-process (`Shared/Networking/DemoBackend.swift`). Every screen and action works against it, which is also what App Review uses.

## Security

| | |
|---|---|
| Secrets | Passwords and token secrets in the Keychain (`AfterFirstUnlockThisDeviceOnly`), shared with the widget through the app group |
| Authentication | Ticket + CSRF token, or `PVEAPIToken`; TOTP two-factor; automatic ticket renewal |
| Certificates | System trust, or trust on first use: the user confirms a SHA-256 fingerprint which is then pinned. Turning verification off is an explicit, separate setting |
| Destructive actions | Always confirmed. Widgets and swipe actions can only *start* guests |
| Privacy | No analytics, no tracking, no third-party code. Privacy manifests for the app and the widget extension |

## Building

Requirements: Xcode 26 or later.

```bash
open Proxyn.xcodeproj
```

The project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen). Regenerate after adding or moving files:

```bash
xcodegen generate
```

Before archiving for the App Store:

1. Set your team on the **Proxyn** and **ProxynWidgets** targets.
2. Replace `com.proxyn.app` and `com.proxyn.app.widgets` with identifiers you own (`project.yml`).
3. Register an App Group, then use its identifier in both `.entitlements` files and in `AppGroup.identifier` (`Shared/Models/ServerProfile.swift`).

The full App Store Connect sheet — metadata, privacy answers, review notes, screenshots — is kept separately; the privacy policy to host is in `docs/privacy-policy.md`.

## Tests

The platform-independent core is also a Swift package, so it runs on macOS without a simulator:

```bash
swift test
```

The suite covers tolerant decoding, formatting, cluster aggregates, alert identity, the TLS trust policy, deep links and end-to-end client calls against the demo backend. CI (`.github/workflows/ci.yml`) runs the tests and a Release device build.

## Architecture

```
Shared/            compiled into the app and the widget extension
  Core/            formatting, Keychain, logging, shared widget store, deep links
  Models/          Proxmox resources, metrics, cluster snapshot, server profile
  Networking/      API client (actor), typed endpoints, TLS policy, demo backend
  UI/              palette and typography (app + widgets only)
Proxyn/
  App/             entry point, launch animation, tab shell, deep-link routing
  Design/          small set of shared components and charts
  Features/        Overview, Nodes, Guests, Storage, Activity, Console, Settings, Onboarding
  Store/           AppModel (@Observable): polling, actions, task tracking, toasts
ProxynWidgets/     WidgetKit extension and App Intents
Tests/             Swift Testing suite for the core
```

- `ProxmoxClient` is an actor: one per server, serialising ticket renewal.
- Screens read an immutable `ClusterSnapshot` built from one `/cluster/resources` call, with every aggregate computed once. On a failed refresh the previous snapshot stays on screen with an explanation.
- Decoding is deliberately tolerant: Proxmox returns the same field as a number, string or boolean depending on version and endpoint.
- Every mutating action goes through `AppModel.perform`, which tracks the Proxmox task until it finishes.

## Design

Built on native components — `TabView`, `NavigationStack`, `List`, `Form`, Swift Charts, `ContentUnavailableView` — so navigation, Dynamic Type, VoiceOver, light and dark appearance and iPad all behave like the rest of iOS. One accent colour, taken from Proxmox orange and tuned per appearance for contrast, marks what's interactive and CPU load; state uses muted green, amber and red; everything else uses the system's label and background colours.

---

Proxmox is a registered trademark of Proxmox Server Solutions GmbH. Proxyn is an independent project and isn't affiliated with or endorsed by Proxmox Server Solutions GmbH.
