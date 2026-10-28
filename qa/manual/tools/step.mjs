#!/usr/bin/env node
// One "manual" step in a real Chromium: open the page, do a few actions the way a person
// would, take a screenshot, and report what happened. The session (cookies, localStorage)
// persists per --session, so consecutive calls behave like one person using the app.
//
// usage: node step.mjs --session qa-admin-ar --lang ar --viewport 1440x900 \
//          --url http://qa.etqan.localhost/app/people/students \
//          --actions '[{"click":"role=button[name=\"Add student\"]"}]' \
//          --shot ../screens/M04/M04-step-012.png [--full] [--text 2500] [--keep]
//
// actions (each object has one key, run in order):
//   {"goto": "/app/..."}           relative to the --url origin, or absolute
//   {"click": "<locator>"}         any Playwright locator string: text=, role=, css, xpath
//   {"dblclick": "<locator>"}
//   {"fill": ["<locator>", "value"]}
//   {"fillLabel": ["Label text", "value"]}
//   {"clickRole": ["button", "Save"]}      getByRole(role, {name}) (exact: false)
//   {"select": ["<locator>", "value-or-label"]}
//   {"check": "<locator>"} / {"uncheck": "<locator>"}
//   {"press": "Enter"} or {"press": ["<locator>", "Tab"]}
//   {"upload": ["<locator>", "/abs/path/file"]}
//   {"hover": "<locator>"}
//   {"wait": 800}                  milliseconds
//   {"waitFor": "<locator>"}       until visible (10 s)
//   {"back": true} / {"reload": true}
//   {"eval": "js expression"}      result is printed
//   {"shotEl": ["<locator>", "/abs/out.png"]}  extra element screenshot
import { chromium } from "playwright";
import fs from "node:fs";
import path from "node:path";

const argv = process.argv.slice(2);
const arg = (k, d) => { const i = argv.indexOf(`--${k}`); return i < 0 ? d : (argv[i + 1] ?? true); };
const flag = (k) => argv.includes(`--${k}`);
const here = path.dirname(new URL(import.meta.url).pathname);
const sessions = path.resolve(here, "../sessions");
fs.mkdirSync(sessions, { recursive: true });

const session = arg("session", "anon");
const lang = arg("lang", "en");
const [vw, vh] = String(arg("viewport", "1440x900")).split("x").map(Number);
const url = arg("url");
const actions = JSON.parse(arg("actions", "[]"));
const shot = arg("shot");
const textMax = Number(arg("text", 2000));
const statePath = path.join(sessions, `${session}.json`);

const browser = await chromium.launch();
const context = await browser.newContext({
  viewport: { width: vw, height: vh },
  locale: lang === "ar" ? "ar-EG" : "en-US",
  storageState: fs.existsSync(statePath) ? statePath : undefined,
  isMobile: vw < 500,
  hasTouch: vw < 500,
});
await context.addInitScript((l) => { try { localStorage.setItem("etqan-locale", l); } catch {} }, lang);
const page = await context.newPage();
const consoleErrors = [];
const failed = [];
page.on("console", (m) => { if (m.type() === "error") consoleErrors.push(m.text().slice(0, 300)); });
page.on("pageerror", (e) => consoleErrors.push(`pageerror: ${String(e).slice(0, 300)}`));
page.on("response", (r) => { if (r.status() >= 400) failed.push(`${r.status()} ${r.request().method()} ${r.url().replace(/^https?:\/\/[^/]+/, "")}`); });
page.on("requestfailed", (r) => failed.push(`FAILED ${r.method()} ${r.url().replace(/^https?:\/\/[^/]+/, "")} ${r.failure()?.errorText ?? ""}`));

const origin = url ? new URL(url).origin : undefined;
const loc = (s) => page.locator(s).first();
const log = [];
let error = null;
try {
  if (url) await page.goto(url, { waitUntil: "networkidle", timeout: 30000 });
  for (const a of actions) {
    const [k, v] = Object.entries(a)[0];
    log.push(k);
    if (k === "goto") await page.goto(v.startsWith("http") ? v : origin + v, { waitUntil: "networkidle", timeout: 30000 });
    else if (k === "click") await loc(v).click({ timeout: 10000 });
    else if (k === "dblclick") await loc(v).dblclick({ timeout: 10000 });
    else if (k === "fill") await loc(v[0]).fill(v[1], { timeout: 10000 });
    else if (k === "fillLabel") await page.getByLabel(v[0]).first().fill(v[1], { timeout: 10000 });
    else if (k === "clickRole") await page.getByRole(v[0], { name: v[1] }).first().click({ timeout: 10000 });
    else if (k === "select") { const s = loc(v[0]); await s.selectOption(v[1]).catch(() => s.selectOption({ label: v[1] })); }
    else if (k === "check") await loc(v).check({ timeout: 10000 });
    else if (k === "uncheck") await loc(v).uncheck({ timeout: 10000 });
    else if (k === "press") Array.isArray(v) ? await loc(v[0]).press(v[1]) : await page.keyboard.press(v);
    else if (k === "upload") await loc(v[0]).setInputFiles(v[1]);
    else if (k === "hover") await loc(v).hover({ timeout: 10000 });
    else if (k === "wait") await page.waitForTimeout(Number(v));
    else if (k === "waitFor") await loc(v).waitFor({ state: "visible", timeout: 10000 });
    else if (k === "back") await page.goBack({ waitUntil: "networkidle" });
    else if (k === "reload") await page.reload({ waitUntil: "networkidle" });
    else if (k === "eval") log.push(`eval => ${JSON.stringify(await page.evaluate(v)).slice(0, 500)}`);
    else if (k === "shotEl") { fs.mkdirSync(path.dirname(v[1]), { recursive: true }); await loc(v[0]).screenshot({ path: v[1] }); }
    else throw new Error(`unknown action ${k}`);
    await page.waitForLoadState("networkidle", { timeout: 8000 }).catch(() => {});
  }
} catch (e) {
  error = String(e.message || e).split("\n").slice(0, 3).join(" | ");
}
await page.waitForTimeout(300);
if (shot) { fs.mkdirSync(path.dirname(path.resolve(shot)), { recursive: true }); await page.screenshot({ path: shot, fullPage: flag("full") }); }
let text = "";
try { text = (await page.locator("body").innerText()).replace(/\n{3,}/g, "\n\n").slice(0, textMax); } catch {}
const dir = await page.evaluate(() => document.documentElement.dir || "ltr").catch(() => "?");
if (!flag("nosave")) await context.storageState({ path: statePath });
await browser.close();
console.log(JSON.stringify({ url: page.url(), dir, error, actions: log, consoleErrors, failedRequests: failed.slice(0, 20), screenshot: shot ? path.resolve(shot) : null, text }, null, 1));
