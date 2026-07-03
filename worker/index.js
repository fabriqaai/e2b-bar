const REPO_URL = "https://github.com/fabriqaai/e2b-bar";
const RELEASES_URL = `${REPO_URL}/releases`;
const LATEST_DMG_URL = `${REPO_URL}/releases/latest/download/E2BBar.dmg`;
const CANONICAL_HOST = "e2b.bar";
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
    <meta name="description" content="A tiny open-source macOS menu bar app for watching running and paused E2B sandboxes, resource totals, expiration timing, and metadata." />
    <meta name="theme-color" content="#f7f5ef" />
    <link rel="canonical" href="https://e2b.bar/" />
    <meta property="og:title" content="E2BBar" />
    <meta property="og:description" content="E2B sandboxes in your macOS menu bar." />
    <meta property="og:type" content="website" />
    <meta property="og:url" content="https://e2b.bar/" />
    <meta name="twitter:card" content="summary" />
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
          <h1>E2B sandboxes, without opening another tab.</h1>
          <p class="dek">E2BBar sits in your menu bar and shows running and paused sandboxes, resource totals, expiration timing, metadata, and quick links back to the places you actually use.</p>
          <div class="actions">
            <a class="button primary" href="/download">Download latest DMG</a>
            <a class="button secondary" href="/github">View source</a>
          </div>
          <p class="fine">macOS 14+ - free and open source - GitHub Releases</p>
        </div>

        <div class="menubar-demo" aria-label="E2BBar menu preview">
          <div class="system-bar">
            <span>Finder</span><span>File</span><span>Edit</span>
            <strong>E2B 2</strong>
          </div>
          <div class="menu">
            <div class="menu-head">
              <span class="big">2</span>
              <span>
                <strong>running sandboxes</strong>
                <small>1 paused - 4c - 2GB memory</small>
              </span>
              <em>OK</em>
            </div>
            <div class="tile-row">
              <span><small>Fetched</small><b>3</b></span>
              <span><small>CPU</small><b>4c</b></span>
              <span><small>Next</small><b>18m</b></span>
            </div>
            <div class="row active">
              <i></i>
              <span><b>nextjs-agent</b><small>running - e2b-code - expires in 18m</small></span>
            </div>
            <div class="row">
              <i></i>
              <span><b>qa-runner</b><small>paused - 2c / 1GB RAM / metadata</small></span>
            </div>
          </div>
        </div>
      </section>

      <section class="features" aria-label="Features">
        <article>
          <span>01</span>
          <h2>Watch live sandboxes</h2>
          <p>Filter running or paused sandboxes, see resource totals, and notice expiring work before it disappears.</p>
        </article>
        <article>
          <span>02</span>
          <h2>Built for API keys</h2>
          <p>Your E2B key is stored in macOS Keychain. The app validates key format before sending requests.</p>
        </article>
        <article>
          <span>03</span>
          <h2>Small on purpose</h2>
          <p>No account sync, no background service, no dashboard clone. Just a useful status item for E2B users.</p>
        </article>
      </section>

      <section class="download">
        <div>
          <p class="eyebrow">Distribution</p>
          <h2>Latest DMG is always one URL.</h2>
          <p>Use the direct download for the newest build, or browse older GitHub releases when you need a specific version.</p>
        </div>
        <div class="download-actions">
          <a class="button primary" href="/download">Latest DMG</a>
          <a class="button secondary" href="/releases">Previous releases</a>
        </div>
      </section>
    </main>

    <footer>
      <span>E2BBar</span>
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
    description: "A macOS menu bar app for watching E2B sandboxes.",
    url: "https://e2b.bar",
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
}
* { box-sizing: border-box; }
html { background: var(--paper); }
body {
  margin: 0;
  min-height: 100vh;
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
  width: min(1180px, calc(100% - 40px));
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
  width: min(1180px, calc(100% - 40px));
  margin: 0 auto;
}
.hero {
  min-height: min(760px, calc(100vh - 88px));
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(360px, 520px);
  gap: clamp(32px, 6vw, 88px);
  align-items: center;
  padding: clamp(46px, 7vw, 92px) 0;
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
  max-width: 760px;
  font-size: clamp(48px, 8vw, 106px);
  line-height: .88;
  letter-spacing: 0;
}
.dek {
  max-width: 650px;
  margin-top: 28px;
  color: var(--muted);
  font-size: clamp(18px, 1.4vw, 22px);
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
.menubar-demo {
  transform: rotate(1.5deg);
  filter: drop-shadow(var(--shadow));
}
.system-bar {
  display: flex;
  gap: 18px;
  align-items: center;
  height: 36px;
  padding: 0 16px;
  color: rgba(255,255,255,.75);
  background: #201d18;
  border-radius: 10px 10px 0 0;
  font-size: 13px;
}
.system-bar strong { margin-left: auto; color: #fff; }
.menu {
  background: rgba(255,253,247,.96);
  border: 1px solid var(--line);
  border-top: 0;
  border-radius: 0 0 10px 10px;
  overflow: hidden;
}
.menu-head {
  display: grid;
  grid-template-columns: auto 1fr auto;
  gap: 14px;
  align-items: center;
  padding: 18px;
}
.big {
  font-size: 46px;
  line-height: 1;
  font-weight: 760;
  font-variant-numeric: tabular-nums;
}
.menu small { display: block; color: var(--muted); margin-top: 2px; }
.menu em {
  font-style: normal;
  color: var(--green-deep);
  background: rgba(22,138,90,.12);
  border-radius: 999px;
  padding: 4px 8px;
  font-size: 12px;
  font-weight: 800;
}
.tile-row {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 8px;
  padding: 0 14px 14px;
}
.tile-row span {
  padding: 9px 10px;
  background: rgba(23,20,15,.06);
  border-radius: 7px;
}
.tile-row b { font-variant-numeric: tabular-nums; }
.row {
  display: grid;
  grid-template-columns: 12px 1fr;
  gap: 11px;
  padding: 13px 18px;
  border-top: 1px solid var(--line);
}
.row i {
  width: 10px;
  height: 10px;
  margin-top: 5px;
  border-radius: 999px;
  background: var(--amber);
}
.row.active i { background: var(--green); }
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
  width: min(1180px, calc(100% - 40px));
  margin: 0 auto;
  padding: 24px 0 42px;
  display: flex;
  gap: 18px;
  color: var(--faint);
  font-size: 14px;
}
footer span { color: var(--ink); font-weight: 760; margin-right: auto; }
footer a:hover { color: var(--ink); }
@media (max-width: 860px) {
  .masthead { align-items: flex-start; gap: 18px; }
  nav { flex-wrap: wrap; justify-content: flex-end; }
  .hero { grid-template-columns: 1fr; min-height: auto; }
  .menubar-demo { transform: none; }
  .features { grid-template-columns: 1fr; }
  .download { grid-template-columns: 1fr; padding: 28px; }
}
@media (max-width: 560px) {
  .masthead, main, footer { width: min(100% - 24px, 1180px); }
  .masthead { flex-direction: column; }
  nav { justify-content: flex-start; }
  h1 { font-size: clamp(42px, 15vw, 70px); }
  .system-bar span:nth-child(n+3) { display: none; }
  .tile-row { grid-template-columns: 1fr; }
  footer { flex-wrap: wrap; }
  footer span { width: 100%; }
}
@media (prefers-reduced-motion: no-preference) {
  .button, nav a { transition: background-color .16s ease, color .16s ease, border-color .16s ease, transform .16s ease; }
  .button:hover { transform: translateY(-1px); }
}`;
}
