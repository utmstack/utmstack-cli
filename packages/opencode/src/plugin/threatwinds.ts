import type { Hooks, PluginInput } from "@opencode-ai/plugin"

/**
 * Auth for the ThreatWinds LLM provider.
 *
 * `threatwinds` is defined in the shipped default config rather than in
 * opencode's provider database. Config-defined providers do not appear in
 * `utmstack providers login` or the TUI `/connect` dialog on their own —
 * registering this built-in auth hook is what makes it a first-class auth
 * provider there.
 *
 * There is deliberately ONE method. With a single method the CLI selects it
 * automatically and the TUI skips the "select auth method" dialog; a second
 * option puts a filter field on that screen, and users type their token into
 * the filter instead of choosing a method.
 */

export function portalURL(): string {
  const base = process.env.UTMSTACK_PORTAL_URL ?? "https://portal.threatwinds.com"
  return `${base.replace(/\/+$/, "")}/apikeys`
}

export async function ThreatWindsAuthPlugin(_input: PluginInput): Promise<Hooks> {
  return {
    auth: {
      provider: "threatwinds",
      methods: [
        {
          type: "api",
          label: `Paste your ThreatWinds API key (get one at ${portalURL()})`,
        },
      ],
    },
  }
}
