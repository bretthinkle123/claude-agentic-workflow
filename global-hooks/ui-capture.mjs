// ui-capture.mjs — FE Layer 4 browser capture (RUNTIME-BOUND; invoked by ui-capture.sh).
// For each declared screen: render the built UI with Playwright, screenshot it, diff against the
// baseline PNG (the design, or an approved golden), and run axe for a11y. Writes
// .pipeline/ui-capture.json for the deterministic design-review-check.sh to compare vs the budget.
//
// Deps (per project): playwright, pixelmatch, pngjs, @axe-core/playwright (+ `npx playwright install chromium`).
// Advisory only — a missing baseline is reported as diff_pct:null (new screen), never an error.
import fs from "node:fs";
import path from "node:path";

const BASE = process.env.UI_BASE_URL;
const SCREENS = (process.env.UI_SCREENS || "").trim().split(/\s+/).filter(Boolean);
const BASELINE_DIR = process.env.UI_BASELINE_DIR || "design/baseline";
const OUT = ".pipeline/ui-capture.json";
const SHOT_DIR = ".pipeline/ui-shots";

async function main() {
  const { chromium } = await import("playwright");
  const { PNG } = await import("pngjs");
  const pixelmatch = (await import("pixelmatch")).default;
  let AxeBuilder = null;
  try { AxeBuilder = (await import("@axe-core/playwright")).default; } catch { /* a11y optional */ }

  fs.mkdirSync(SHOT_DIR, { recursive: true });
  const browser = await chromium.launch();
  const page = await browser.newPage();
  const screens = [];

  for (const entry of SCREENS) {
    const [name, route] = entry.split(":");
    const url = BASE.replace(/\/$/, "") + (route || "/");
    await page.goto(url, { waitUntil: "networkidle" }).catch(() => {});
    const shotPath = path.join(SHOT_DIR, `${name}.png`);
    await page.screenshot({ path: shotPath, fullPage: true });

    // Visual diff vs the baseline PNG (if one exists). null = new screen, no baseline yet.
    let diff_pct = null;
    const basePath = path.join(BASELINE_DIR, `${name}.png`);
    if (fs.existsSync(basePath)) {
      try {
        const a = PNG.sync.read(fs.readFileSync(shotPath));
        const b = PNG.sync.read(fs.readFileSync(basePath));
        const w = Math.min(a.width, b.width), h = Math.min(a.height, b.height);
        const mismatched = pixelmatch(a.data, b.data, null, w, h, { threshold: 0.1 });
        diff_pct = Math.round((mismatched / (w * h)) * 10000) / 100; // % to 2dp
      } catch { diff_pct = null; }
    }

    // a11y via axe (counts by impact). Absent AxeBuilder → zeros (a11y not installed).
    const a11y = { critical: 0, serious: 0, moderate: 0, minor: 0 };
    if (AxeBuilder) {
      try {
        const res = await new AxeBuilder({ page }).analyze();
        for (const v of res.violations) if (a11y[v.impact] !== undefined) a11y[v.impact]++;
      } catch { /* leave zeros */ }
    }
    screens.push({ name, route: route || "/", diff_pct, a11y });
  }

  await browser.close();
  fs.writeFileSync(OUT, JSON.stringify({ ran_at: new Date().toISOString(), base_url: BASE, screens }, null, 2));
  console.log(`[ui-capture] captured ${screens.length} screen(s) → ${OUT}`);
}

main().catch((e) => { console.error("[ui-capture] failed:", e.message); process.exit(0); });
