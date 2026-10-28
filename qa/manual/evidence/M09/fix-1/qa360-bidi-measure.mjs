import { createRequire } from "module";
const require = createRequire(process.cwd() + "/");
const { chromium } = require("playwright");
const b = await chromium.launch(); const p = await b.newPage();
await p.setContent('<html dir="rtl"><body></body></html>');
const r = await p.evaluate(() => {
  const fmt = (n) => new Intl.NumberFormat("ar", {style:"currency",currency:"EGP",minimumFractionDigits:2}).format(n);
  const variants = {
    pos: fmt(3000), neg: fmt(-1000),
    absMinus: (() => { const s = fmt(1000); return s.replace(/[0-9]/, (d)=>"-"+d); })(),
    absLrmMinus: (() => { const s = fmt(1000); return s.replace(/[0-9]/, (d)=>"‎-"+d); })(),
    signDisplayNegLrm: (() => { const s = fmt(1000); return s.replace(/[0-9]/, (d)=>"⁦-"+d).replace(/(\d)(?!.*\d)/, "$1⁩"); })(),
  };
  const out = {};
  for (const [k, txt] of Object.entries(variants)) {
    const span = document.createElement("span"); span.dir = "ltr"; span.textContent = txt; document.body.appendChild(span); document.body.appendChild(document.createElement("br"));
    const range = document.createRange(); const node = span.firstChild;
    const pos = (re) => { const i = txt.search(re); range.setStart(node, i); range.setEnd(node, i+1); return Math.round(range.getBoundingClientRect().x); };
    out[k] = { codes: [...txt].map(c=>c.charCodeAt(0)>127?c.charCodeAt(0).toString(16):c).join(" "), digitX: pos(/[0-9]/), curX: pos(/[؀-ۿ]/), minusX: txt.includes("-") ? pos(/-/) : null };
  }
  return out;
});
console.log(JSON.stringify(r, null, 1)); await b.close();
