import fs from "node:fs"; import { chromium } from "playwright-core";
const out = process.argv[2]; const { concepts, svgs } = JSON.parse(fs.readFileSync("logos.json"));
const b = await chromium.launch({ executablePath: process.env.EXE }); const p = await b.newPage({ deviceScaleFactor: 2 });
const shot = async (svg, h, bg, file) => {
  await p.setContent(`<style>html,body{margin:0;background:${bg}}div{display:inline-block;padding:${bg==="transparent"?0:h/3}px}svg{height:${h}px;width:auto;display:block}</style><div>${svg}</div>`);
  await p.locator("div").screenshot({ path: file, omitBackground: bg === "transparent" });
};
let n = 0;
for (const c of concepts) {
  const v = svgs[c.id], dir = `${out}/assets/concept-${c.id.toLowerCase()}/png`; fs.mkdirSync(dir, { recursive: true });
  const stem = `etqan-tutor-${c.id.toLowerCase()}-${c.key}`;
  await shot(v.light.horizontal, 64, "transparent", `${dir}/${stem}-horizontal-light@2x.png`);
  await shot(v.dark.horizontal, 64, "#022217", `${dir}/${stem}-horizontal-dark-preview@2x.png`);
  await shot(v.light.stacked, 140, "transparent", `${dir}/${stem}-stacked-light@2x.png`);
  for (const s of [16, 32, 64, 180]) { await p.setContent(`<style>body{margin:0}</style>${v.favicon.replace(/width="48" height="48"/, `width="${s}" height="${s}"`)}`); await p.locator("svg").screenshot({ path: `${dir}/${stem}-favicon-${s}.png`, omitBackground: true, scale: "css" }); }
  n += 7;
}
// size test sheet: symbol at 16/24/32/64 for all concepts at 1x
await p.setViewportSize({ width: 560, height: 520 });
await p.setContent(`<style>body{margin:0;background:#FAF9F5;font:12px sans-serif;padding:12px}.r{display:flex;gap:18px;align-items:center;height:60px}svg{display:block;width:auto}</style>` + concepts.map(c => `<div class=r><b style="width:20px">${c.id}</b>${[16,24,32,64].map(s => svgs[c.id].light.symbol.replace('<svg ', `<svg style="height:${s}px" `)).join("")}${[16,32].map(s => svgs[c.id].favicon.replace('<svg ', `<svg style="height:${s}px" `)).join("")}</div>`).join(""));
await p.screenshot({ path: `${out}/screenshots/size-test-16-24-32-64.png`, fullPage: true, scale: "css" });
console.log("png", n); await b.close();
