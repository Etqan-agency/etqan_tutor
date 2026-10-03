# Merges

One paragraph per merge, newest last (spec 2026-10-02 §5).

**2026-10-03 — B8a site settings depth (B8, plan 16).** backend#5 → `ad8cd27`, dashboard#4 → `c79c18e`,
marketing#2 → `cc02b56`, meta#12 → `65335dd`; pointers bumped on `master` in `594639f`. Meta CI green
(staging-sim included). Bounces: 0. Adds validated tracking IDs (D2), site status/closed-site mode, and
branding/socials settings, all off by default. Deploy note: ship marketing with or before backend.
Known local-only flake: `families.spec` races `features.spec` under parallel local e2e (CI is serial).
Earlier the same day: meta#11 (`80d6b09`) made `just` gate recipes match CI.

**B3a** (expenses & donations, plan 15) merged 2026-10-03: backend#6 → main 2fa9a40, dashboard#5 → main 7bd37d6, meta#15; pointers bumped on master b9389eb. CI green, 0 bounces.
