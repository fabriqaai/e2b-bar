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
    <title>E2BBar - macOS menu bar for E2B sandboxes</title>
    <meta name="description" content="E2BBar is an open-source macOS menu bar app for monitoring E2B sandboxes, metrics, logs, lifecycle events, files, processes, ports, and usage alerts." />
    <meta name="theme-color" content="#f5f1e8" />
    <link rel="canonical" href="https://e2b.bar/" />
    <meta property="og:title" content="E2BBar" />
    <meta property="og:description" content="Open-source E2B sandbox monitoring from your macOS menu bar." />
    <meta property="og:type" content="website" />
    <meta property="og:url" content="https://e2b.bar/" />
    <meta property="og:image" content="${SCREENSHOT_URL}" />
    <meta name="twitter:card" content="summary_large_image" />
    <meta name="twitter:image" content="${SCREENSHOT_URL}" />
    <script type="application/ld+json">${JSON.stringify(schema()).replace(/</g, "\\u003c")}</script>
    <style>${styles()}</style>
  </head>
  <body>
    <header class="top">
      <a class="wordmark" href="/" aria-label="E2BBar home">
        <span class="cube">E2B</span>
        <span>E2BBar</span>
      </a>
      <nav aria-label="Primary">
        <a href="/github">Source</a>
        <a href="/releases">Releases</a>
        <a href="/download">Download</a>
      </nav>
    </header>

    <main>
      <section class="hero" aria-labelledby="title">
        <p class="kicker">Open-source macOS menu bar app</p>
        <div class="hero-grid">
          <h1 id="title">E2BBar</h1>
          <div class="intro">
            <p>E2B sandboxes, visible without another browser tab.</p>
            <div class="actions" aria-label="Download and source links">
              <a class="primary" href="/download">Download</a>
              <a href="/github">View source</a>
            </div>
          </div>
        </div>
      </section>

      <figure class="screenshot">
        <img src="/screenshot.webp" width="1500" height="1198" alt="E2BBar showing a running E2B sandbox, inline CPU memory disk metrics, sandbox actions, and searchable logs." />
      </figure>

      <section class="plain" aria-labelledby="does">
        <h2 id="does">What it does</h2>
        <div class="rows">
          <p>Paste your E2B API key once. E2BBar stores it in Keychain and lists your running and paused sandboxes.</p>
          <p>See CPU, memory, disk, TTL, lifecycle events, logs, ports, files, processes, and network controls from the menu bar.</p>
          <p>Configure local alerts for expiration, concurrent sandboxes, starts per day, and estimated daily cost.</p>
          <p>Keep destructive actions hidden until you explicitly enable them.</p>
        </div>
      </section>

      <section class="split" aria-labelledby="start">
        <div>
          <h2 id="start">Get started</h2>
          <ol>
            <li>Download the macOS app.</li>
            <li>Open Settings and paste your E2B API key.</li>
            <li>Keep an eye on your sandboxes from the menu bar.</li>
          </ol>
        </div>
        <div class="links">
          <a class="primary" href="/download">Download</a>
          <a href="/releases">Previous versions</a>
          <a href="/github">Code on GitHub</a>
        </div>
      </section>
    </main>

    <footer>
      <span>E2BBar</span>
      <a class="fabriqa" href="https://fabriqa.ai" target="_blank" rel="noreferrer">
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
    description: "Open-source macOS menu bar app for monitoring E2B sandboxes, metrics, logs, lifecycle events, usage alerts, files, processes, ports, and safe actions.",
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
  --paper: #f5f1e8;
  --ink: #15130f;
  --muted: #615b50;
  --quiet: #91897b;
  --line: rgba(21, 19, 15, .16);
  --line-strong: rgba(21, 19, 15, .36);
  --green: #0c6f4b;
  --orange: #b8572d;
  --white: #fffaf0;
  --shell: min(1120px, calc(100% - 40px));
}
* { box-sizing: border-box; }
html { background: var(--paper); }
body {
  margin: 0;
  min-height: 100vh;
  color: var(--ink);
  background: var(--paper);
  font-family: ui-sans-serif, -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", sans-serif;
  -webkit-font-smoothing: antialiased;
  text-rendering: optimizeLegibility;
}
body::before {
  content: "";
  position: fixed;
  inset: 0;
  pointer-events: none;
  background:
    linear-gradient(90deg, transparent 0, transparent calc(100% - 1px), rgba(21,19,15,.05) calc(100% - 1px)) 0 0 / 80px 80px,
    linear-gradient(0deg, transparent 0, transparent calc(100% - 1px), rgba(21,19,15,.04) calc(100% - 1px)) 0 0 / 80px 80px;
  mask-image: linear-gradient(to bottom, black, transparent 78%);
}
a {
  color: inherit;
  text-decoration-thickness: 1px;
  text-underline-offset: 5px;
}
.top,
main,
footer {
  position: relative;
  width: var(--shell);
  margin: 0 auto;
}
.top {
  min-height: 72px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 24px;
}
.wordmark,
nav,
.actions,
.links,
footer,
.fabriqa {
  display: flex;
  align-items: center;
}
.wordmark {
  gap: 10px;
  font-weight: 740;
  text-decoration: none;
}
.cube {
  display: inline-grid;
  place-items: center;
  width: 38px;
  height: 30px;
  border: 1px solid var(--line-strong);
  border-radius: 6px;
  color: var(--green);
  font-size: 12px;
  font-weight: 850;
  letter-spacing: 0;
  background: rgba(255, 250, 240, .54);
}
nav {
  gap: 18px;
  color: var(--muted);
  font-size: 14px;
}
nav a,
.links a,
.actions a {
  text-decoration: none;
}
nav a:hover,
footer a:hover,
.links a:hover,
.actions a:hover {
  color: var(--green);
}
.hero {
  padding: clamp(58px, 10vw, 150px) 0 clamp(42px, 6vw, 80px);
}
.kicker {
  margin: 0 0 16px;
  color: var(--green);
  font-size: 12px;
  font-weight: 780;
  letter-spacing: .14em;
  text-transform: uppercase;
}
.hero-grid {
  display: grid;
  grid-template-columns: minmax(0, .96fr) minmax(280px, .66fr);
  gap: clamp(28px, 7vw, 88px);
  align-items: end;
}
h1,
h2,
p {
  margin: 0;
}
h1 {
  font-family: "Iowan Old Style", "Palatino", "Palatino Linotype", ui-serif, Georgia, serif;
  font-size: clamp(72px, 11vw, 132px);
  font-weight: 700;
  line-height: .86;
  letter-spacing: 0;
}
.intro {
  padding-bottom: clamp(4px, 1vw, 18px);
}
.intro p {
  max-width: 410px;
  color: var(--muted);
  font-size: clamp(21px, 2.2vw, 31px);
  line-height: 1.15;
}
.actions,
.links {
  flex-wrap: wrap;
  gap: 14px;
  margin-top: 28px;
}
.actions a,
.links a {
  min-height: 42px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border-bottom: 1px solid var(--line-strong);
  font-weight: 720;
}
.actions .primary,
.links .primary {
  min-width: 126px;
  padding: 0 18px;
  color: var(--white);
  background: var(--ink);
  border: 1px solid var(--ink);
  border-radius: 6px;
}
.actions .primary:hover,
.links .primary:hover {
  color: var(--white);
  background: var(--green);
  border-color: var(--green);
}
.screenshot {
  margin: 0 0 clamp(64px, 9vw, 120px);
  border-top: 1px solid var(--line);
  border-bottom: 1px solid var(--line);
  padding: clamp(16px, 2.4vw, 26px) 0;
}
.screenshot img {
  display: block;
  width: 100%;
  height: auto;
  border: 1px solid var(--line-strong);
  border-radius: 6px;
  background: var(--white);
}
.plain,
.split {
  border-top: 1px solid var(--line);
  padding: clamp(32px, 6vw, 72px) 0;
}
.plain {
  display: grid;
  grid-template-columns: minmax(180px, .36fr) 1fr;
  gap: clamp(26px, 7vw, 96px);
}
h2 {
  font-size: clamp(25px, 3.2vw, 43px);
  line-height: 1.02;
  letter-spacing: 0;
}
.rows {
  display: grid;
  gap: 0;
}
.rows p {
  padding: 18px 0;
  border-top: 1px solid var(--line);
  color: var(--muted);
  font-size: clamp(17px, 1.7vw, 22px);
  line-height: 1.42;
}
.rows p:first-child {
  border-top: 0;
  padding-top: 0;
}
.split {
  display: grid;
  grid-template-columns: 1fr auto;
  gap: clamp(26px, 6vw, 80px);
  align-items: end;
}
ol {
  margin: 22px 0 0;
  padding-left: 1.25em;
  color: var(--muted);
  font-size: clamp(17px, 1.5vw, 20px);
  line-height: 1.7;
}
.links {
  justify-content: flex-end;
  max-width: 360px;
}
footer {
  min-height: 96px;
  gap: 18px;
  border-top: 1px solid var(--line);
  color: var(--quiet);
  font-size: 14px;
}
footer span {
  color: var(--ink);
  font-weight: 760;
  margin-right: auto;
}
.fabriqa {
  gap: 7px;
}
.fabriqa svg {
  color: var(--ink);
  flex: 0 0 auto;
}
@media (max-width: 820px) {
  :root { --shell: min(100% - 28px, 1120px); }
  .top {
    min-height: 86px;
    align-items: flex-start;
    padding-top: 18px;
  }
  nav {
    flex-wrap: wrap;
    justify-content: flex-end;
    gap: 12px;
  }
  .hero-grid,
  .plain,
  .split {
    grid-template-columns: 1fr;
  }
  h1 {
    font-size: clamp(72px, 25vw, 150px);
  }
  .intro p {
    max-width: 620px;
  }
  .links {
    justify-content: flex-start;
  }
  footer {
    flex-wrap: wrap;
    align-content: center;
    padding: 22px 0;
  }
  footer span {
    width: 100%;
  }
}
@media (max-width: 480px) {
  .top {
    display: block;
  }
  nav {
    justify-content: flex-start;
    margin-top: 18px;
  }
  .hero {
    padding-top: 42px;
  }
  .actions a,
  .links a {
    width: 100%;
  }
}
@media (prefers-reduced-motion: no-preference) {
  a {
    transition: color .16s ease, background-color .16s ease, border-color .16s ease;
  }
}`;
}
