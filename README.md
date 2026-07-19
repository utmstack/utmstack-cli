# UTMStack CLI

The SIEM-aware coding and security agent — a branded distribution of
[opencode](https://github.com/anomalyco/opencode) that ships with UTMStack's
SIEM tooling, the ThreatWinds model provider, and a curated set of skills and
subagents already configured.

## Install

Find your platform below and copy the matching command. The installer detects
your CPU architecture automatically — there is one command per operating
system, not per architecture.

### macOS — Apple Silicon (M1–M4) and Intel

```bash
curl -fsSL https://raw.githubusercontent.com/utmstack/utmstack-cli/main/install | bash
```

### Linux — x86_64 and ARM64

```bash
curl -fsSL https://raw.githubusercontent.com/utmstack/utmstack-cli/main/install | bash
```

### Windows — x64 and ARM64 (PowerShell)

```powershell
irm https://raw.githubusercontent.com/utmstack/utmstack-cli/main/install.ps1 | iex
```

Run this in **PowerShell**, not `cmd.exe`. If you prefer Git Bash or WSL, use
the macOS/Linux command above instead — it works there too.

### What gets installed

| | Location |
|---|---|
| macOS / Linux | `~/.utmstack/bin/utmstack` |
| Windows | `%USERPROFILE%\.utmstack\bin\utmstack.exe` |

The installer adds that directory to your `PATH` and also installs the
[UTMStack MCP server](https://github.com/utmstack/MCP), which provides the SIEM
tools. Open a new terminal afterwards so `PATH` takes effect.

Set `UTMSTACK_SKIP_MCP=1` to skip the MCP server. Set `UTMSTACK_VERSION=1.2.3`
to install a specific version instead of the latest.

### Supported platforms

Every combination below gets a prebuilt binary:

| Operating system | Architecture | Notes |
|---|---|---|
| macOS 12+ | Apple Silicon (`arm64`) | |
| macOS 12+ | Intel (`x64`) | includes a no-AVX2 build for older Macs |
| Linux (glibc) | `x86_64` | Ubuntu 22.04+, RHEL 9+, Debian 12+ |
| Linux (glibc) | `arm64` / `aarch64` | |
| Windows 10/11 | `x64` | |
| Windows 11 | `ARM64` | Surface, and Parallels VMs on Apple Silicon |

**Older or virtualised x64 CPUs**: many cloud VMs lack AVX2. The installer
detects this and fetches a `-baseline` build automatically — no action needed.

**Alpine / musl Linux** is not covered by these binaries, which are built
against glibc. Build from source there (see below).

**32-bit systems** are not supported.

## First run

```bash
utmstack-mcp init     # connect your UTMStack server (URL + credentials)
utmstack              # start the CLI, then /connect to paste your ThreatWinds API key
```

`utmstack-mcp init` validates your credentials against the live API before
saving them, and writes them to a `0600` file outside any CLI config — so no
credentials end up in shell history or in a config file you might share.

## What ships out of the box

**SIEM tools** — the `utmstack` MCP server is enabled by default: alert search
and triage, log explorer and SQL, incidents, correlation rules, data filters,
agent inventory, and remote command execution on endpoints.

Remote command execution is **opt-in per server** (`allowAgentCommands`). It
grants a root/SYSTEM shell on an endpoint, and SIEM log content — which is
partly written by attackers — reaches the model through log and alert search.
Enable it only where you want that capability.

**Models** — the `threatwinds` provider is preconfigured
(`silas-1.6-pro` by default, `silas-1.6` for small tasks). Add your API key with
`/connect` in the TUI or `utmstack providers login`.

**Skills and subagents** — 26 skills and 9 subagents are embedded in the binary
and extracted to your config directory on first run, covering planning, code
review, systematic debugging, test-driven development, and web testing. They are
version-gated: an upgrade refreshes them without touching skills you added.

## Configuration

Config lives in `~/.config/utmstack/utmstack.json` (`%APPDATA%\utmstack` on
Windows). The defaults are written on first run and are yours to edit — the CLI
never overwrites an existing config.

The directory is separate from opencode's, so this CLI and a stock opencode
install coexist without touching each other's settings. An `opencode.json` in
the same directory is still read, with `utmstack.json` taking precedence.

## Building from source

```bash
bun install
cd packages/opencode
OPENCODE_VERSION=1.0.0 bun run script/build.ts --single
```

The binary lands in `dist/opencode-<platform>-<arch>/bin/utmstack`. Embedded
skills and agents are regenerated from `packages/opencode/src/assets` on every
build; `bundled-assets.gen.ts` is generated and not tracked in git.

## Upstream

This is a fork of opencode. Branding and defaults are confined to a small set of
files so upstream changes remain straightforward to merge:

| Path | Purpose |
|---|---|
| `packages/core/src/global.ts` | app name — relocates every config/data/cache directory |
| `packages/opencode/src/index.ts` | script name, bootstrap invocation |
| `packages/opencode/src/config/utmstack-bootstrap.ts` | seeds default config, extracts embedded assets |
| `packages/opencode/src/config/config.ts` | reads `utmstack.json` ahead of `opencode.json` |
| `packages/opencode/src/plugin/threatwinds.ts` | makes `threatwinds` a first-class auth provider |
| `packages/opencode/script/gen-bundled-assets.ts` | embeds skills and agents into the binary |
| `packages/opencode/script/build.ts` | binary name, release asset naming, archive hygiene |
| `packages/opencode/src/installation/index.ts` | update checks point at this repo, not upstream |
| `packages/tui/src/logo.ts`, `packages/opencode/src/cli/ui.ts` | wordmarks |
| `install` | installer, plus the MCP install step |

Skills and subagents come from
[osmontero/opencode-skills](https://github.com/osmontero/opencode-skills).

Upstream opencode documentation is preserved in `README.upstream.md`.

## License

opencode's license applies to the upstream code. See [LICENSE](LICENSE).
