import { readOptionalEnv } from "./env";

type SignupAlert = {
  crewNumber?: number;
};

/**
 * Tell the operator that a new account joined the crew.
 *
 * The alert deliberately carries no email address, display name, or user id: the
 * operational channel only needs the event and the non-identifying crew ordinal.
 * `wait=true` makes Discord confirm that it stored the message instead of returning
 * a fire-and-forget 204 that can hide a failed delivery.
 */
export async function notifyDiscordSignup({ crewNumber }: SignupAlert): Promise<void> {
  const configuredUrl = await readOptionalEnv("DISCORD_ALERT_WEBHOOK");

  if (!configuredUrl) {
    return;
  }

  const webhookUrl = new URL(configuredUrl);
  webhookUrl.searchParams.set("wait", "true");

  const suffix = crewNumber == null ? "" : ` — crew #${crewNumber}`;
  const response = await fetch(webhookUrl, {
    body: JSON.stringify({
      allowed_mentions: {
        parse: [],
      },
      content: `New crew member signed up${suffix}.`,
    }),
    headers: {
      "Content-Type": "application/json",
    },
    method: "POST",
  });

  if (!response.ok) {
    const message = await response.text();

    throw new Error(`Discord signup alert failed: ${response.status} ${message}`);
  }
}
