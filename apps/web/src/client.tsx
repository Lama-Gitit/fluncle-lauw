import * as Sentry from "@sentry/tanstackstart-react";
import { StartClient } from "@tanstack/react-start/client";
import { StrictMode } from "react";
import { hydrateRoot } from "react-dom/client";
import { BROWSER_SENTRY_DSN, SENTRY_RELEASE } from "./lib/sentry-config";

// Browser error tracking. init() installs the global `error` +
// `unhandledrejection` handlers, so unhandled client exceptions are captured
// with stacks. Errors only, free-tier posture (ratified): no tracing, no session
// replay, no PII. Production builds only — `import.meta.env.PROD` is `false`
// under vite dev, so a dev session sends nothing.
if (import.meta.env.PROD) {
  Sentry.init({
    dsn: BROWSER_SENTRY_DSN,
    release: SENTRY_RELEASE,
    sendDefaultPii: false,
    tracesSampleRate: 0,
  });
}

// Deploy-skew self-heal. A tab left open across a deploy holds HTML that
// references the OLD build's hashed chunks; a later lazy navigation then 404s
// (FLUNCLE-WEB-4, 2026-07-26 — eight deploys in one day made it visible). Vite
// fires `vite:preloadError` for exactly this, so reload once to pick up the
// fresh build instead of surfacing a broken page. The sessionStorage guard
// keeps a genuinely-missing chunk (or an offline client) from reload-looping:
// one attempt per page, then the error propagates to Sentry as usual.
window.addEventListener("vite:preloadError", (event) => {
  const guard = "fluncle-chunk-reload";

  if (sessionStorage.getItem(guard) === window.location.href) {
    return;
  }

  sessionStorage.setItem(guard, window.location.href);
  event.preventDefault();
  window.location.reload();
});

hydrateRoot(
  document,
  <StrictMode>
    <StartClient />
  </StrictMode>,
);
