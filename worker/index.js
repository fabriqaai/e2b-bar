const REPO_URL = "https://github.com/fabriqaai/e2b-bar";
const RELEASES_URL = `${REPO_URL}/releases`;
const LATEST_DMG_URL = `${REPO_URL}/releases/latest/download/E2BBar.dmg`;
const CANONICAL_HOST = "e2b.bar";
const SCREENSHOT_URL = "https://e2b.bar/screenshot.webp";
const REDIRECT_HOSTS = new Set(["www.e2b.bar", "e2bbar.app", "www.e2bbar.app"]);

export default {
  async fetch(request) {
    const url = new URL(request.url);

    if (REDIRECT_HOSTS.has(url.hostname)) {
      url.hostname = CANONICAL_HOST;
      return Response.redirect(url.toString(), 301);
    }

    if (url.pathname === "/download") {
      return Response.redirect(LATEST_DMG_URL, 302);
    }

    if (url.pathname === "/releases") {
      return Response.redirect(RELEASES_URL, 302);
    }

    if (url.pathname === "/github") {
      return Response.redirect(REPO_URL, 302);
    }

    if (url.pathname === "/healthz") {
      return new Response("ok\n", {
        headers: { "content-type": "text/plain; charset=utf-8" },
      });
    }

    return new Response(renderPage(), {
      headers: {
        "content-type": "text/html; charset=utf-8",
        "cache-control": "public, max-age=300",
      },
    });
  },
};

function renderPage() {
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>E2BBar - E2B sandboxes in your macOS menu bar</title>
    <meta name="description" content="Open-source macOS menu bar app for monitoring E2B sandboxes with metrics, logs, lifecycle events, files, processes, ports, and safe actions." />
    <meta name="theme-color" content="#f7f5ef" />
    <link rel="canonical" href="https://e2b.bar/" />
    <meta property="og:title" content="E2BBar" />
    <meta property="og:description" content="Open-source E2B sandbox monitoring for your macOS menu bar." />
    <meta property="og:type" content="website" />
    <meta property="og:url" content="https://e2b.bar/" />
    <meta property="og:image" content="${SCREENSHOT_URL}" />
    <meta name="twitter:card" content="summary_large_image" />
    <meta name="twitter:image" content="${SCREENSHOT_URL}" />
    <script type="application/ld+json">${JSON.stringify(schema()).replace(/</g, "\\u003c")}</script>
    <style>${styles()}</style>
  </head>
  <body>
    <div class="grain" aria-hidden="true"></div>
    <header class="masthead">
      <a class="brand" href="/" aria-label="E2BBar home">
        <span class="mark">E2B</span>
        <span>E2BBar</span>
      </a>
      <nav aria-label="Primary">
        <a href="/github">GitHub</a>
        <a href="/releases">Releases</a>
        <a class="nav-button" href="/download">Download</a>
      </nav>
    </header>

    <main>
      <section class="hero">
        <div class="copy">
          <p class="eyebrow">Open-source macOS menu bar app</p>
          <h1>E2B sandboxes in your menu bar.</h1>
          <p class="dek">Add your E2B API key once, then watch running and paused sandboxes from macOS: metrics, logs, lifecycle events, expiration alerts, port links, files, processes, and safe actions.</p>
          <div class="actions">
            <a class="button primary" href="/download">Download latest version</a>
            <a class="button secondary" href="/github">View source</a>
          </div>
          <p class="fine">macOS 14+ - open source - releases on GitHub</p>
        </div>

        <figure class="screenshot-frame" aria-label="E2BBar running on macOS">
          <img src="/screenshot.webp" width="1500" height="1198" alt="E2BBar menu bar app showing a running E2B sandbox, inline metrics, actions, and searchable logs." />
        </figure>
      </section>

      <section class="features" aria-label="Features">
        <article>
          <span>01</span>
          <h2>Connect your E2B key</h2>
          <p>Paste an API key from the E2B dashboard. E2BBar stores it locally in Keychain and starts listing your sandboxes.</p>
        </article>
        <article>
          <span>02</span>
          <h2>Monitor from macOS</h2>
          <p>See state, CPU, memory, disk, TTL, logs, lifecycle events, and expiration alerts without keeping the dashboard open.</p>
        </article>
        <article>
          <span>03</span>
          <h2>Use quick tools</h2>
          <p>Open port URLs, inspect files and processes, edit network rules, extend TTLs, and keep destructive actions hidden until enabled.</p>
        </article>
      </section>

      <section class="download">
        <div>
          <p class="eyebrow">Download</p>
          <h2>Install the latest E2BBar.</h2>
          <p>Get the newest signed macOS build, browse older versions, or inspect the code on GitHub.</p>
        </div>
        <div class="download-actions">
          <a class="button primary" href="/download">Download latest version</a>
          <a class="button secondary" href="/releases">Previous releases</a>
          <a class="button secondary" href="/github">Source code</a>
        </div>
      </section>
    </main>

    <footer>
      <span>E2BBar</span>
      <a class="fabriqa-link" href="https://fabriqa.ai" target="_blank" rel="noreferrer">
        <svg viewBox="0 0 64 65" width="18" height="18" aria-hidden="true">
          <rect x="0" y="0" width="64" height="11" rx="6" fill="#b8572d"></rect>
          <rect x="0" y="18" width="49.49" height="11" rx="6" fill="currentColor"></rect>
          <rect x="0" y="36" width="34.99" height="11" rx="6" fill="currentColor"></rect>
          <rect x="0" y="54" width="20.48" height="11" rx="6" fill="currentColor"></rect>
        </svg>
        fabriqa.ai
      </a>
      <a href="https://e2b.dev">E2B</a>
      <a href="/github">GitHub</a>
      <a href="/releases">Releases</a>
    </footer>
  </body>
</html>`;
}

function schema() {
  return {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    name: "E2BBar",
    applicationCategory: "DeveloperApplication",
    operatingSystem: "macOS 14+",
    description: "Open-source macOS menu bar app for monitoring E2B sandboxes with metrics, logs, lifecycle events, files, processes, ports, and safe actions.",
    url: "https://e2b.bar",
    image: SCREENSHOT_URL,
    downloadUrl: LATEST_DMG_URL,
    codeRepository: REPO_URL,
    license: "https://github.com/fabriqaai/e2b-bar",
  };
}

function styles() {
  return `:root {
  color-scheme: light;
  --paper: #f7f5ef;
  --paper-2: #ece8dc;
  --ink: #17140f;
  --muted: #665f53;
  --faint: #968e80;
  --line: rgba(23, 20, 15, .16);
  --line-strong: rgba(23, 20, 15, .28);
  --green: #168a5a;
  --green-deep: #0d5e42;
  --amber: #d8872e;
  --white: #fffdf7;
  --shadow: 0 22px 70px rgba(53, 45, 28, .18);
  --shell: min(1540px, calc(100% - clamp(32px, 6vw, 96px)));
}
* { box-sizing: border-box; }
html { background: var(--paper); }
body {
  margin: 0;
  min-height: 100vh;
  overflow-x: clip;
  color: var(--ink);
  background:
    linear-gradient(90deg, rgba(23,20,15,.04) 1px, transparent 1px) 0 0 / 72px 72px,
    linear-gradient(0deg, rgba(23,20,15,.035) 1px, transparent 1px) 0 0 / 72px 72px,
    radial-gradient(circle at 78% 14%, rgba(22,138,90,.14), transparent 30rem),
    var(--paper);
  font-family: ui-sans-serif, -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", sans-serif;
  -webkit-font-smoothing: antialiased;
  text-rendering: optimizeLegibility;
}
a { color: inherit; text-decoration: none; }
.grain {
  pointer-events: none;
  position: fixed;
  inset: 0;
  opacity: .18;
  background-image: repeating-radial-gradient(circle at 0 0, rgba(23,20,15,.16) 0, rgba(23,20,15,.16) 1px, transparent 1px, transparent 4px);
  mix-blend-mode: multiply;
}
.masthead {
  position: relative;
  z-index: 2;
  width: var(--shell);
  margin: 0 auto;
  padding: 24px 0 18px;
  display: flex;
  justify-content: space-between;
  align-items: center;
}
.brand, nav { display: flex; align-items: center; gap: 12px; }
.brand { font-weight: 740; letter-spacing: 0; }
.mark {
  width: 40px;
  height: 28px;
  display: grid;
  place-items: center;
  color: var(--white);
  background: var(--green-deep);
  border-radius: 6px;
  font-size: 12px;
  font-weight: 850;
}
nav { color: var(--muted); font-size: 14px; }
nav a { padding: 8px 10px; border-radius: 7px; }
nav a:hover { background: rgba(23,20,15,.07); color: var(--ink); }
.nav-button { color: var(--white); background: var(--ink); }
nav .nav-button:hover { color: var(--white); background: var(--green-deep); }
main {
  position: relative;
  z-index: 1;
  width: var(--shell);
  margin: 0 auto;
}
.hero {
  min-height: min(780px, calc(100vh - 88px));
  display: grid;
  grid-template-columns: minmax(390px, .78fr) minmax(520px, 1.22fr);
  gap: clamp(28px, 4vw, 72px);
  align-items: center;
  padding: clamp(42px, 6vh, 76px) 0 clamp(50px, 7vh, 88px);
}
.copy {
  position: relative;
  z-index: 2;
  min-width: 0;
  max-width: 600px;
}
.eyebrow {
  margin: 0 0 18px;
  color: var(--green-deep);
  font-size: 12px;
  font-weight: 760;
  letter-spacing: .16em;
  text-transform: uppercase;
}
h1, h2, p { margin: 0; }
h1 {
  max-width: 10ch;
  font-size: clamp(52px, 5.8vw, 104px);
  line-height: .92;
  letter-spacing: 0;
}
.dek {
  max-width: 560px;
  margin-top: clamp(20px, 2.2vw, 28px);
  color: var(--muted);
  font-size: clamp(17px, 1.15vw, 21px);
  line-height: 1.5;
}
.actions, .download-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 12px;
  margin-top: 30px;
}
.button {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-height: 44px;
  padding: 0 18px;
  border-radius: 7px;
  font-weight: 720;
  border: 1px solid var(--line-strong);
}
.button.primary {
  color: var(--white);
  background: var(--ink);
  border-color: var(--ink);
}
.button.primary:hover { background: var(--green-deep); border-color: var(--green-deep); }
.button.secondary { background: rgba(255,253,247,.56); }
.button.secondary:hover { background: var(--white); }
.fine {
  margin-top: 14px;
  color: var(--faint);
  font-size: 13px;
}
.screenshot-frame {
  margin: 0;
  width: 100%;
  max-width: 920px;
  transform: rotate(.7deg);
  filter: drop-shadow(var(--shadow));
  justify-self: end;
}
.screenshot-frame img {
  display: block;
  width: 100%;
  height: auto;
  border: 1px solid rgba(23,20,15,.18);
  border-radius: 12px;
  background: var(--white);
}
.features {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 1px;
  margin: 24px 0 72px;
  background: var(--line);
  border: 1px solid var(--line);
}
.features article {
  min-height: 230px;
  padding: 26px;
  background: color-mix(in srgb, var(--paper) 88%, white);
}
.features span {
  color: var(--green-deep);
  font-weight: 800;
  font-size: 12px;
}
.features h2, .download h2 {
  margin-top: 28px;
  font-size: clamp(26px, 3vw, 42px);
  line-height: 1;
}
.features p, .download p {
  margin-top: 14px;
  color: var(--muted);
  line-height: 1.6;
}
.download {
  display: grid;
  grid-template-columns: 1fr auto;
  gap: 28px;
  align-items: end;
  padding: 42px;
  margin: 0 0 56px;
  border: 1px solid var(--line);
  background: var(--white);
  border-radius: 8px;
}
footer {
  position: relative;
  z-index: 1;
  width: var(--shell);
  margin: 0 auto;
  padding: 24px 0 42px;
  display: flex;
  gap: 18px;
  color: var(--faint);
  font-size: 14px;
}
footer span { color: var(--ink); font-weight: 760; margin-right: auto; }
footer a:hover { color: var(--ink); }
.fabriqa-link {
  display: inline-flex;
  align-items: center;
  gap: 7px;
}
.fabriqa-link svg {
  color: var(--ink);
  flex: 0 0 auto;
}
@media (max-width: 1120px) {
  .masthead { align-items: flex-start; gap: 18px; }
  nav { flex-wrap: wrap; justify-content: flex-end; }
  .hero { grid-template-columns: 1fr; min-height: auto; }
  .copy { max-width: 760px; }
  h1 { max-width: 11ch; }
  .screenshot-frame { width: 100%; max-width: none; transform: none; justify-self: stretch; }
  .features { grid-template-columns: 1fr; }
  .download { grid-template-columns: 1fr; padding: 28px; }
}
@media (max-width: 560px) {
  .masthead, main, footer { width: min(100% - 24px, 1180px); }
  .masthead { flex-direction: column; }
  nav { justify-content: flex-start; }
  h1 { font-size: clamp(42px, 14vw, 68px); }
  footer { flex-wrap: wrap; }
  footer span { width: 100%; }
}
@media (prefers-reduced-motion: no-preference) {
  .button, nav a { transition: background-color .16s ease, color .16s ease, border-color .16s ease, transform .16s ease; }
  .button:hover { transform: translateY(-1px); }
}`;
}
