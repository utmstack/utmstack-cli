/**
 * UTMStack first-run bootstrap.
 *
 * Seeds the global config with UTMStack defaults (the ThreatWinds LLM provider
 * and the utmstack MCP server) and extracts the skills and agents that are
 * embedded in this binary.
 *
 * Two rules govern this file:
 *
 *  - It never overwrites user edits. The config is written only when absent,
 *    and bundled assets are re-extracted only when the build's asset version
 *    changes.
 *  - It never throws into the CLI's startup path. A failure here degrades the
 *    experience; it must not prevent the CLI from running.
 */

import fs from "fs"
import path from "path"

import { Global } from "@opencode-ai/core/global"

import { BUNDLED_ASSETS, BUNDLED_ASSETS_VERSION } from "./bundled-assets.gen"

const APP = "utmstack"

/**
 * Global config directory.
 *
 * This deliberately reuses Global.Path.config rather than recomputing the XDG
 * lookup. An earlier version resolved paths independently and drifted from the
 * config loader, so the seeded config was written somewhere the CLI never read.
 */
export function configDir(): string {
  return Global.Path.config
}

/** The default configuration shipped with the CLI. */
export function defaults() {
  const aiBaseURL = process.env.UTMSTACK_AI_URL ?? "https://apis.threatwinds.com/api/ai/v1"
  return {
    $schema: "https://opencode.ai/config.json",
    model: "threatwinds/silas-1.6-pro",
    small_model: "threatwinds/silas-1.6",
    provider: {
      threatwinds: {
        api: "openai",
        name: "ThreatWinds",
        options: { baseURL: aiBaseURL },
        models: {
          "silas-1.6": {
            name: "Silas 1.6",
            reasoning: true,
            limit: { context: 229376, output: 10000 },
          },
          "silas-1.6-pro": {
            name: "Silas 1.6 Pro",
            reasoning: true,
            limit: { context: 229376, output: 10000 },
          },
        },
      },
    },
    mcp: {
      // Installed alongside this CLI by the same installer.
      utmstack: {
        type: "local",
        command: ["utmstack-mcp"],
        enabled: true,
      },
    },
  }
}

function configFile(): string {
  return path.join(configDir(), `${APP}.json`)
}

/** Write the default config if the user has none yet. Returns true if written. */
export function seedConfig(): boolean {
  const file = configFile()
  try {
    if (fs.existsSync(file)) return false
    if (fs.existsSync(path.join(configDir(), "utmstack.jsonc"))) return false
    // Deliberately not checking for opencode.json/opencode.jsonc: the CLI
    // auto-creates a near-empty opencode.jsonc containing only "$schema", so
    // treating it as "already configured" would skip seeding entirely. Our
    // file takes precedence in the loader's filename order anyway.
    fs.mkdirSync(configDir(), { recursive: true })
    fs.writeFileSync(file, JSON.stringify(defaults(), null, 2) + "\n", { mode: 0o600 })
    return true
  } catch (err) {
    console.error(`${APP}: could not write default config:`, err)
    return false
  }
}

/**
 * Extract embedded skills and agents into the config directory.
 *
 * A version marker gates re-extraction, and a manifest records what the last
 * build wrote so files dropped in a later release can be pruned without
 * touching skills the user added themselves.
 */
export function extractBundledAssets(): void {
  const dir = configDir()
  const versionFile = path.join(dir, "bundled-assets.version")
  const manifestFile = path.join(dir, "bundled-assets.manifest")

  try {
    if (fs.existsSync(versionFile)) {
      const current = fs.readFileSync(versionFile, "utf8").trim()
      if (current === BUNDLED_ASSETS_VERSION) return
    }

    const previous: string[] = fs.existsSync(manifestFile)
      ? fs
          .readFileSync(manifestFile, "utf8")
          .split("\n")
          .map((l) => l.trim())
          .filter(Boolean)
      : []

    const written: string[] = []
    for (const asset of BUNDLED_ASSETS) {
      const target = path.join(dir, asset.path)
      fs.mkdirSync(path.dirname(target), { recursive: true })
      fs.writeFileSync(target, asset.base64 ? Buffer.from(asset.content, "base64") : asset.content)
      written.push(asset.path)
    }

    // Remove only files a previous build of ours wrote and this one no longer ships.
    for (const stale of previous.filter((p) => !written.includes(p))) {
      try {
        fs.rmSync(path.join(dir, stale), { force: true })
      } catch {
        // A file the user moved or deleted is not an error.
      }
    }

    fs.writeFileSync(manifestFile, written.join("\n") + "\n")
    fs.writeFileSync(versionFile, BUNDLED_ASSETS_VERSION + "\n")
  } catch (err) {
    console.error(`${APP}: failed to extract bundled skills/agents:`, err)
  }
}

export function bootstrap(): void {
  seedConfig()
  extractBundledAssets()
}
