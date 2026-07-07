# CursorMeterFS

<p align="center">
  <img src="docs/screenshots/icon.png" width="128" alt="CursorMeterFS">
</p>

<p align="center">
  <strong>Monitor your Codex, Claude Code, and Cursor quotas in real time — zero setup required.</strong><br>
  One menu bar app, three providers, tabbed side by side — detects every account automatically, always in sight.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13.0%2B-blue?style=flat-square&logo=apple" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Swift-5.9-orange?style=flat-square&logo=swift" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="MIT">
  <img src="https://img.shields.io/badge/Providers-Codex%20%7C%20Claude%20%7C%20Cursor-purple?style=flat-square" alt="Codex, Claude, Cursor">
</p>

> **Started as a Cursor-only usage tracker** — that's where the name comes from. It has
> since grown into a multi-provider monitor that also watches your Codex and Claude Code
> quotas, all from the same lightweight menu bar app.

---

## Screenshots

<p align="center">
  <img src="docs/screenshots/menubar.png" alt="Menu Bar Icon" width="300">
  &nbsp;&nbsp;
  <img src="docs/screenshots/popover.png" alt="Popover" width="220">
</p>

<p align="center">
  <img src="docs/screenshots/settings-general.png" alt="Settings — General" width="300">
  &nbsp;&nbsp;
  <img src="docs/screenshots/settings-notifications.png" alt="Settings — Notifications" width="300">
</p>

<p align="center">
  <img src="docs/screenshots/icon-styles.png" alt="Icon Styles" width="500">
</p>

---

## Why CursorMeterFS?

Instead of opening three different web dashboards, a single glance at your menu bar tells
you how much of each provider's quota you've used, which model consumed how many tokens,
and what you've spent — for Codex, Claude Code, and Cursor at once.

| | CursorMeterFS | Each provider's own dashboard |
|---|---|---|
| Always visible | ✅ One menu bar icon for all three | ❌ (open a browser, per provider) |
| Unified view | ✅ Tabbed: Codex · Claude · Cursor | ❌ Separate sites, separate logins |
| Notifications | ✅ Alerts on threshold breach | ❌ |
| Recent requests / cost | ✅ Model + tokens + estimated cost | Varies by provider |
| No manual login needed | ✅ Auto-detected from local sign-in | — |
| Admin access required | ❌ Never | — |
| Third-party dependencies | ❌ Zero | — |

---

## Features

### Multi-Provider, One Menu Bar
A tabbed popover switches between **Codex**, **Claude Code**, and **Cursor**. Each tab
shows exactly what that provider's API returns — quota windows, reset timers, and plan
info are fully dynamic, never hardcoded. Enable or disable any provider individually in
Settings.

### Zero-Setup Auth, Per Provider
No admin access, ever. Each provider is picked up from the credentials you already have:
Cursor from its local `state.vscdb` (read-only) and the macOS Keychain, Codex from
`~/.codex/auth.json` (with a local session-log fallback if the API is unreachable), and
Claude Code from `~/.claude/.credentials.json` or the login Keychain. No copying session
IDs, no pasting tokens.

### Adaptive Refresh
The default refresh mode backs off automatically when you're idle, on Low Power Mode, or
under thermal pressure — polling stays responsive while you're active and quiets down
when you're not, instead of burning battery on a fixed timer. Fixed intervals (1–30 min)
and manual refresh are also available.

### Dynamic Quota Tracking
Quota lanes are rendered from whatever each API actually returns — session limits, weekly
limits, model-scoped limits (e.g. "Sonnet only") — never a hardcoded model name or limit.
If your plan changes, the numbers update automatically on the next refresh.

### 6 Menu Bar Icon Styles
Pick the style that fits your menu bar best: **Battery**, **Circular**, **Minimal %**,
**Minimal #**, **Segments**, **Dual Bar**, **Gauge**. Each works in **Mono** (follows
system color) or **Color** (green / orange / red) mode.

### Cost Estimates
For Codex and Claude Code, local token counts are matched against a pricing table to show
an estimated USD cost — computed entirely on-device, no network call involved. Cursor
shows its own on-demand spend and hard limit directly from the API instead.

### Recent Request Details
See which model handled each request, how many tokens were used, and the approximate
cost — all from the popover (Cursor), or a per-model usage breakdown where per-request
detail isn't available.

### Smart Notifications
- **70% (Warning):** "You've used a large portion of your quota"
- **90% (Critical):** "You've reached a critical level"
- **Reset:** Fresh-start notification when a quota resets
- All thresholds are configurable; each notification fires at most once per billing cycle.

### Secure by Design
Credentials are read locally and never leave your Mac. Nothing is written back to
`state.vscdb`, `auth.json`, or `.credentials.json` — refreshed tokens are kept in memory
only. Network access is restricted to each provider's own API host
(`cursor.com`, `chatgpt.com`, `api.anthropic.com`).

---

## Requirements

- **macOS 13.0 (Ventura)** or later
- A local sign-in for **at least one** of the following (all three can run side by side):
  - **[Cursor](https://cursor.com)** — Free, Pro, or Ultra
  - **Codex CLI** (`codex`) — signed in via ChatGPT
  - **Claude Code** (`claude`) — signed in via Claude Pro/Max or a Claude Console account
- **Xcode 15+** (for building from source)

---

## Installation

### Option 1 — Release DMG *(fastest)*

1. Download the latest `CursorMeterFS-vX.Y.Z.dmg` from the [Releases](../../releases) page.
2. Open the DMG → drag CursorMeterFS to **Applications**.
3. On first launch, macOS Gatekeeper will block the app because it isn't notarized (see
   ["Why does macOS say this app isn't safe?"](#why-does-macos-say-this-app-isnt-safe) below).
   Clear it with **one** of these:
   - **Terminal (recommended, works on every macOS version):**
     ```bash
     xattr -cr /Applications/CursorMeterFS.app
     ```
     Then open the app normally.
   - **GUI:** Try to open the app (it will be blocked) → go to
     **System Settings → Privacy & Security** → scroll down to the security notice for
     CursorMeterFS → click **Open Anyway** → confirm in the dialog that appears.
4. The CursorMeterFS icon appears in your menu bar — done.

#### Why does macOS say this app isn't safe?

CursorMeterFS is signed but **not notarized** — notarization requires an Apple Developer
Program membership ($99/year), which this free, open-source project doesn't carry. The
warning is about *identity verification*, not a finding about the code itself. You don't
have to take that on faith — you can verify it independently:

- **Read the source.** The entire app is open source right here in this repo — nothing
  is obfuscated or built from code you can't see.
- **Read the security review.** [`security-report/SECURITY-REPORT.md`](security-report/SECURITY-REPORT.md)
  documents the app's data access, network, and storage behavior in detail.
- **Verify the release build wasn't tampered with.** Every release is built by GitHub
  Actions directly from the tagged source and published with a signed
  [build provenance attestation](../../attestations) and a SHA-256 checksum (see the
  release notes) — so you can confirm the DMG you downloaded matches what CI produced,
  independent of Apple's notarization.
- **Check what it actually touches.** See [Token Security](#token-security) below: no
  credentials are ever written to disk, network access is restricted to each provider's
  own API host, and nothing is logged.

---

### Option 2 — Build from Source *(Xcode)*

#### 1. Install the dependency

```bash
brew install xcodegen
```

> Don't have Homebrew? [brew.sh](https://brew.sh)

#### 2. Clone the repo

```bash
git clone https://github.com/furkansarikaya/CursorMeterFS.git
cd CursorMeterFS
```

#### 3. Generate the Xcode project

```bash
xcodegen generate
```

#### 4. Open and run in Xcode

```bash
open CursorMeterFS.xcodeproj
```

Once Xcode opens:

1. Click the **CursorMeterFS** project in the left panel.
2. Go to **Signing & Capabilities**.
3. Select your Apple ID under **Team** — a *Personal Team* is free and sufficient.
4. Press **⌘R** to run.

Xcode will download any missing dependencies on the first build.

---

### Option 3 — Terminal Build & Run *(no Xcode UI)*

No admin rights required — useful when you can't install a DMG.

```bash
# 1. Dependency
brew install xcodegen

# 2. Clone
git clone https://github.com/furkansarikaya/CursorMeterFS.git
cd CursorMeterFS

# 3. Generate Xcode project
xcodegen generate

# 4. Build (unsigned — for local development)
xcodebuild \
  -scheme CursorMeterFS \
  -configuration Release \
  -destination "platform=macOS" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  build

# 5. Run
open "$(xcodebuild \
  -scheme CursorMeterFS \
  -configuration Release \
  -showBuildSettings 2>/dev/null \
  | awk '/BUILT_PRODUCTS_DIR/{print $3}')/CursorMeterFS.app"
```

> **Note:** An unsigned build runs only on your own Mac and cannot be submitted to the App Store.

---

## Permission Prompts

On first launch macOS may show a few permission dialogs — **these are expected and safe:**

| Permission | Why It's Needed | If You Deny |
|------------|----------------|-------------|
| **"CursorMeterFS wants to access data from other apps"** | Cursor's local database (`state.vscdb`) is read read-only to retrieve your session | Auto-detection won't work |
| **"CursorMeterFS wants to use the 'Claude Code-credentials' keychain item"** | Claude Code's own login item is read to get your session — this is a one-time grant per build; click **Always Allow** | Claude tab shows "not signed in" |
| **Keychain access (Cursor)** | The retrieved token is saved encrypted in the macOS Keychain so the database isn't read again on subsequent launches | The database is re-read on every launch |
| **Notification permission** | Alerts are sent when usage thresholds are crossed | Notifications won't appear; the app continues working |

> All permissions can be changed later under **System Settings → Privacy & Security**. If a
> Keychain prompt reappears repeatedly, see [Keychain Prompt Reappears](#keychain-prompt-reappears-after-every-rebuild) below —
> it's a code-signing quirk of local development builds, not a bug in the release DMG.

---

## Usage

### First Launch

On startup, CursorMeterFS checks each provider's local sign-in and settles into the menu
bar showing whichever ones it found. **No login required inside the app.** A provider tab
without credentials shows a "not signed in" state with a hint on how to sign in to that
tool — it doesn't block the others.

### Menu Bar Icon

The icon reflects the currently selected provider's most relevant quota window:

| Color | Meaning |
|-------|---------|
| 🟢 Green | Quota is healthy (below 70%) |
| 🟠 Orange | Approaching the warning threshold |
| 🔴 Red | Critical — most of the quota has been consumed |

- **Left click** → Open / close the usage popover
- **Right click** → Quick menu (Refresh / Settings / Quit)

### Popover

A tab strip switches between **Codex**, **Claude**, and **Cursor**. Each tab shows:

- **Plan badge** and quota lanes (session / weekly / model-scoped — whatever that
  provider's API returns), each with a percentage bar, reset countdown, and pace
  indicator (ahead of / behind schedule for the billing period)
- **Cost or on-demand spend:** estimated USD cost (Codex/Claude) or on-demand spend and
  hard limit (Cursor), when applicable
- **Recent Requests / model breakdown:** model name, token count, approximate cost, or a
  per-model usage bar when per-request detail isn't available (optional, toggle in Settings)

---

## Settings

Open via right-click → **Settings**, or the gear icon at the bottom of the popover.

### General

| Setting | Description |
|---------|-------------|
| **Providers** | Per-provider row (Codex / Claude / Cursor) showing the detected account and connection status, with a toggle to enable or disable each one independently |
| **Refresh Interval** | Adaptive (recommended — backs off automatically when idle, on Low Power Mode, or under thermal pressure) or a fixed interval (1 / 2 / 5 / 15 / 30 min / Manual) |
| **Show Recent Requests** | Display the last N requests in the popover |
| **Menu Bar Icon Style** | Battery / Circular / Minimal % / Minimal # / Segments / Dual Bar / Gauge |
| **Icon Color Mode** | Mono (follows system color) / Color (green–orange–red) |
| **Export to JSON** | `~/.cursormeterfs/usage.json` — aggregate percentages and counts only, for integration with external tools |
| **Start at Login** | Launch automatically when your Mac starts |

### Notifications

| Setting | Description |
|---------|-------------|
| **Enable Notifications** | Master switch for all threshold and reset alerts |
| **Warning Threshold** | Send a warning notification at this percentage (default 70%) |
| **Critical Threshold** | Send a critical notification at this percentage (default 90%) |
| **Notify on Billing Cycle Reset** | Notify when a quota resets |
| **Send Test Notification** | Verify that notifications are working |

---

## How It Works

Each provider is a self-contained data source — CursorMeterFS never asks you to log in
itself, it reads what's already there:

| Provider | Identity source | Quota API | Offline fallback |
|----------|-----------------|-----------|-------------------|
| **Cursor** | `state.vscdb` (read-only SQLite) | `cursor.com/api/*` | — |
| **Codex** | `~/.codex/auth.json` | `chatgpt.com/backend-api/wham/usage` | Last `token_count.rate_limits` from `~/.codex/sessions/**` |
| **Claude** | `~/.claude/.credentials.json` → Keychain `Claude Code-credentials` | `api.anthropic.com/api/oauth/usage` | — |

Nothing is ever written back to `state.vscdb`, `auth.json`, or `.credentials.json`.
Refreshed tokens are held in memory only for the lifetime of the process.

### Technical Flow (Cursor example)

```
state.vscdb  (read-only, one-time)
  └─ cursorAuth/accessToken  (JWT)
       └─ JWT.sub → userId
            └─ sessionToken = userId%3A%3AaccessToken
                 │
                 ├─ GET  cursor.com/api/usage?user=<userId>
                 │        → used / max requests / reset date
                 │
                 ├─ POST cursor.com/api/dashboard/get-monthly-invoice
                 │        → model / tokens / cost per request
                 │
                 └─ POST cursor.com/api/dashboard/get-hard-limit
                          → spending limit

Token → Keychain (encrypted, device-local)
NSStatusItem icon updated
Threshold crossed → Notification sent
```

Codex and Claude follow the same shape: read the local credential, call that provider's
own usage endpoint, render whatever quota windows it returns — no model names or limits
are hardcoded for any provider.

### Token Security

| Topic | Behavior |
|-------|----------|
| Token storage | macOS Keychain (Cursor session token, Claude's own `Claude Code-credentials` item); Codex/Claude's own local auth files are read, never copied elsewhere |
| Refreshed tokens | Kept in memory only — never written back to disk |
| Database access | `SQLITE_OPEN_READONLY` on `state.vscdb` — writes are strictly impossible |
| Network | Only each provider's own API host (`cursor.com`, `chatgpt.com`, `api.anthropic.com`), ATS-restricted, host validated on every call |
| Logs | Tokens and emails are never logged |
| JSON export | Only percentages, counts, and dates — no credentials |
| Third-party | No external Swift packages; Apple system frameworks only |

---

## Troubleshooting

### Auto-Detection Not Working

**Cursor:**
```bash
# Check whether Cursor's token exists (read-only)
sqlite3 ~/Library/Application\ Support/Cursor/User/globalStorage/state.vscdb \
  "SELECT key, length(value) FROM ItemTable WHERE key LIKE 'cursorAuth%';"
```
If a `cursorAuth/accessToken` row appears, the token is present. Restart Cursor, then click **Settings → Retry Detection**.

**Codex:** Confirm `~/.codex/auth.json` exists — sign in with `codex` if it doesn't.

**Claude:** Confirm `~/.claude/.credentials.json` exists, or that a `Claude Code-credentials` item exists in Keychain Access (login keychain) — sign in with `claude` if not.

> Don't copy and paste tokens manually for any provider. CursorMeterFS handles this automatically and securely.

### Data Not Updating

- Right-click → **Refresh** to trigger a manual update, or use each provider tab's own retry action.
- Every provider's API is unofficial/undocumented to some degree and may change without notice. If data can't be fetched, the last known values are shown with an error badge instead of the app breaking.

### Notifications Not Arriving

Go to **System Settings → Notifications → CursorMeterFS** and verify that notifications are enabled. You can also confirm with the **"Send Test Notification"** button in Settings.

### Keychain Prompt Reappears After Every Rebuild

If you're building from source and the "wants to use the 'Claude Code-credentials' keychain
item" prompt keeps coming back even after clicking **Always Allow**, this is a local
development artifact, not a bug: Debug builds are ad-hoc signed
(`CODE_SIGN_IDENTITY = "-"`), and an ad-hoc signature is derived from the binary's own
hash. Every time you change the code and rebuild, that hash changes, so macOS treats the
new build as a different app and the keychain access grant from the previous build no
longer matches — it has to ask again.

This **does not affect the release DMG** — once installed, that exact binary is never
rebuilt on your Mac, so the grant persists normally. For a smoother local dev loop:
- Just click **Always Allow** each time; it's expected during active development.
- Or sign your local build with your own **Personal Team** in Xcode's *Signing &
  Capabilities* (Option 2 above) instead of the project's default ad-hoc identity — a
  certificate-based signature stays stable across rebuilds, so the grant persists too.
  Note that running `xcodegen generate` regenerates the project from `project.yml`, which
  resets signing back to ad-hoc — you'll need to reselect your team afterward.

---

## Contributing

1. Fork this repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Commit your changes
4. Open a pull request

The CI pipeline runs `xcodegen generate` + `xcodebuild` + unit tests automatically on every PR.

---

## Known Limitations

- All three providers' quota APIs are **unofficial and undocumented** to varying degrees and may break with an update on their end.
- Auto-detection may not work if Cursor is installed in a non-standard location (outside `/Applications`).
- Some dashboard endpoints may not return quota data for Cursor Free plan accounts.
- Cost estimates for Codex/Claude are computed locally from a pricing table and are approximate, not billing-accurate.

---

## License

MIT — see [LICENSE](LICENSE)

---

<p align="center">
  <em>Not affiliated with Cursor, OpenAI, or Anthropic.</em>
</p>
