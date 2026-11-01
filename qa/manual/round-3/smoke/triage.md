# Smoke round 3: triage

Agent 2 (smoke triage), 2026-11-01. Each item was reproduced with `qa/manual/tools/step.mjs`
(sessions `r3-smoke-triage-{en,ar}`, qa-admin). The before shots are in `qa/manual/screens/r3/smoke/fix/`.

| Smoke ID | Result | Area | Severity | Type | Easy | Status |
|---|---|---|---|---|---|---|
| SMOKE-M04-01 | ETQAN-QA-1800 (follow-up of QA-1036) | M04 | P4 | spacing/icon | yes | OPEN |
| SMK-M06-01 | ETQAN-QA-1801 | M06 | P3 | UI/layout | yes | OPEN |
| SMK-M06-02 | ETQAN-QA-1802 | M06 | P4 | responsive | yes | OPEN |
| SMK-M07-01 | ETQAN-QA-1803 (same class as QA-218/1077) | M07 | P3 | RTL | yes | OPEN |
| SMK-M08-01 | ETQAN-QA-1804 (includes a sweep list of other bare `<bdi>{full_name}</bdi>` cells) | M08 | P3 | RTL | yes | OPEN |
| SMK-M08-02 | ETQAN-QA-1805 | M08 | P4 | UI/layout | yes | OPEN |
| M09-SMOKE-001 | ETQAN-QA-1806 (related to QA-1212) | M09 | P3 | responsive | yes | OPEN |
| SMOKE-M12-01 | ETQAN-QA-1807 | M12 | P4 | spacing/icon | yes | OPEN |
| SMOKE-M12-02 (note) | ETQAN-QA-1808: judged a bug. It breaks the documented `PersonName` rule (ETQAN-QA-120: in EN the Arabic part comes first), and the System codes Redeemed column shows the same thing | M12 | P4 | RTL (consistency) | yes | OPEN |

## Rejected
None. All nine reproduced as reported.

## Observations by the smoke agents that were not filed (agreed)
- M07-M08: the Payment records search placeholder at EN 375 is cut off ("…transaction or invoic"). The
  placeholder is cosmetic, and the full text is in the label.
- M07-M08: AR session 170 shows the subscription as «ب». This is test data.
- M09-M10: the Broadcasts actions column header is `sr-only` on purpose (`BroadcastsPage.tsx:128`).
- M09-M10: the near-white chat group avatar is an uploaded test image.
- M05-M06: "At the administration's disposal" is covered by D-M09-2 / D-M11-1.
