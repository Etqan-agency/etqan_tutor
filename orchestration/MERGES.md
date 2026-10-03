# Merges

One paragraph per merge, newest last (spec 2026-10-02 §5).

**2026-10-03 — B8a site settings depth (B8, plan 16).** backend#5 → `ad8cd27`, dashboard#4 → `c79c18e`,
marketing#2 → `cc02b56`, meta#12 → `65335dd`; pointers bumped on `master` in `594639f`. Meta CI green
(staging-sim included). Bounces: 0. Adds validated tracking IDs (D2), site status/closed-site mode, and
branding/socials settings, all off by default. Deploy note: ship marketing with or before backend.
Known local-only flake: `families.spec` races `features.spec` under parallel local e2e (CI is serial).
Earlier the same day: meta#11 (`80d6b09`) made `just` gate recipes match CI.

**B3a** (expenses & donations, plan 15) merged 2026-10-03: backend#6 → main 2fa9a40, dashboard#5 → main 7bd37d6, meta#15; pointers bumped on master b9389eb. CI green, 0 bounces.

**B2a** (session classes, plan 17) merged 2026-10-03: backend#7 → main dd81cfa, dashboard#6 → main 7939e34, meta#16 → cacd19c; pointers bumped on master 51d1124. Meta CI green incl. staging-sim, 0 bounces. Gates: backend 2514 (98.22%), dashboard 1001 (94.8% lines), e2e 27/27.

**B8b** (FAQs, ads, redirects, plan 19) merged 2026-10-03: backend#8 → main 5bf7573, dashboard#7 → main 4a0332d, marketing#3 → main 50041f7, meta#17 → 4ba8e2f; pointers bumped on master 510ae06. Meta CI green incl. staging-sim, 0 bounces.

**B9a** (uploads, file library, contracts, system status, plan 18) merged 2026-10-03: backend#9 → main 2e4c231, dashboard#8 → main 9d3a1d4, meta#18 → 4351dd6; pointers bumped on master 2d6c526. Meta CI green incl. staging-sim, 0 bounces; e2e 32/32. E1 resolved by the owner: Twilio for B9c SMS.
