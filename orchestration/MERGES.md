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

**B8c** (articles, plan 24) merged 2026-10-04: backend#10 → main 6eb6420, dashboard#9 → main e906267, marketing#4 → main 0e7d3c8, meta#19 → 855cf72; pointers bumped on master 9b88017. Meta CI green incl. staging-sim, 0 bounces.

**B2b** (plan 21) merged 2026-10-04: backend#12 → main 463db80, dashboard#11 → main 4531174, meta#21 → 407de91 (also carries the B2c–B2g specs); pointers bumped on master 1c3cb33. Meta CI green incl. staging-sim, 0 bounces. Earlier: meta#22 made `just e2e` retry once (ERR_NETWORK_CHANGED from other streams containers, found by B2).

**B3b** (online payments: gateways, links, fee; plan 20) merged 2026-10-04: backend#11 → main 1629430, dashboard#10 → main ffdb80a, meta#20 → cc00f5f (also carries Plan 26 B3g docs); pointers bumped on master 1ef4473. Meta CI green incl. staging-sim, 0 bounces. Feature online_payments is off by default. Before switching it on: set ETQAN_SECRETS_KEY (Fernet) and leave GATEWAYS_SIMULATE unset in that environment.

**meta#23 + infra#2** (2026-10-04): Referrer-Policy no-referrer on /app/quick-login* in the local, e2e and production edges (requested by B9 for B9b S-11b); infra bumped on master 1590861.

**B8d** (media, plan 27) merged 2026-10-04: backend#13 → main 0e34580, dashboard#12 → main f6b118a, marketing#5 → main 3763ebe, meta#24 → ab604d9; pointers bumped on master c0a54b0. Meta CI green incl. staging-sim, 0 bounces.

**B9b** (sign-in: switches, two-factor, impersonation, quick-login link; plan 23) merged 2026-10-05: backend#14 → main 3af447a, dashboard#13 → main deed0ab, meta#25 → 92bf2bd; pointers bumped on master caee462. Meta CI green incl. staging-sim, 0 bounces.

**B2c** (plan 25) merged 2026-10-05: backend#15 → main 7ee81c4, dashboard#14 → main 866dad3, meta#26 → 8d9625a; pointers bumped on master 1fb0606. Meta CI green incl. staging-sim, 0 bounces. Dashboard#14 also updated the B2a e2e spec b2-session-classes (disposal banner check).

**B8e** (page builder, plan 30; B8 last slice) merged 2026-10-05: backend#17 → main 596f669, dashboard#16 → main 40d7724, marketing#6 → main 3d50f3c, meta#28 → 87b79fa; pointers bumped on master 166d66b. Meta CI green incl. staging-sim, 0 bounces; e2e 42/42. Deploy note (E-13): ship the backend first. Phase B8 complete (B8a to B8e).

**master CI flake** (2026-10-05): run 37255240218 on b05a107 failed e2e only, b8-page-builder.spec.ts (an admin builds and publishes a blocks page) timing out at a click on both attempts; submodule trees identical to 87b79fa, which passed. Rerun of the failed job passed; no revert. Watch this spec (owned by the conductor now that B8 is merged).

**B3c** (PayPal, plan 22) merged 2026-10-05: backend#16 → main a94dbbb, dashboard#15 → main 5411766, meta#27 → beec9e3 (also carries the B3d and B3h specs and the B3 re-slice); pointers bumped on master e12456f. Meta CI green after one rerun of e2e (failed only on the b8-page-builder flake; not B3c code), 0 bounces. Page-builder fix: dashboard#17 → main 1bb4d3b; meta#29 repointed and re-running CI.

**Page-builder fix** (conductor, 2026-10-05): dashboard#17 → main 1bb4d3b, meta#29 → efe033e. Root cause of the flaky b8-page-builder e2e: after a new blocks page saved, PageEditor (same route component) rendered null until the new page loaded and then replaced local blocks with the server copy, dropping a block added during the save. Fix seeds the created page into the query cache and skips the block reload for the page just created; vitest regression test added.

**B3afix** (finance dialogs keep the chosen currency; fix for a B3a race) merged 2026-10-05: dashboard#18 → main 37b907c, meta#30 → c8fb337; dashboard bumped on master aa926cf. Meta CI green incl. staging-sim, 0 bounces. B3 did not rerun local e2e after its rebase (its stack held unfinished B3g migrations); CI e2e on a trunk backend was the gate.

**B2d** (archives, plan 31) merged 2026-10-05: backend#18 → main 96ef5dd, dashboard#19 → main 5de2317, meta#31 → be60e0a; pointers bumped on master 8d7c64c. Meta CI green incl. staging-sim, 0 bounces; e2e 44 with no retries. Outside B2 files: dashboard commit 2454f3b edits the billing InvoiceForm under a ledger claim (taken 18f9add, released dbf3735); shared seed tests test_seed_dev/test_seed_staging now count non-archived rows only.

**B9c** (registration and one-time code reset incl. Twilio SMS backend, plan 28) merged 2026-10-05: backend#19 → main 7a05ba4, dashboard#20 → main aab8ea5, meta#32 → 19f5719; pointers bumped on master ae23674. Meta CI green incl. staging-sim, 0 bounces. Production SMS needs TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN and TWILIO_FROM (E1); until set, the phone option stays hidden.

**B6a** (learning, plan 32; B6 first slice) merged 2026-10-05: backend#20 → main 82bc5ed, dashboard#21 → main 87f2413, meta#33 → 69bb813; pointers bumped on master cc20742. Meta CI green incl. staging-sim, 0 bounces. Locally b9-sign-in phone timed out under load (passes alone); B9 asked to check it.

**B3g** (payment links and records, plan 26) merged 2026-10-05: backend#21 → main acaf496, dashboard#22 → main 1361e95, meta#34 → 838fa59 (also carries B3h spec review fixes); pointers bumped on master 39e9c01. Meta CI green incl. staging-sim, 0 bounces. Requests: R2 (B3d pricing hook) delegated by B2 to B3 under a claim, marked done; R1 (SubscriptionTermsCard line) stays with B2 and can land now.

**meta#37 + dashboard#27** (conductor, 2026-10-06): `just secrets` (gitleaks over tracked files, part of `just lint`), and the two slow axe tests raised (ProfileEditForm 30s to 90s, it took ~42s on every CI run after the billing fix; RegisterPage 60s to 120s). dashboard → main e29be1c; master 894a996. E2 (Actions billing) resolved by the owner earlier today.

**B9d** (languages, plan 29; B9 last slice) merged 2026-10-07: backend#22 → main 96f38fa, dashboard#23 → main e6545d3, meta#35; pointers bumped on master 2b8b600. Meta CI green; 1 earlier bounce (gitleaks false positive, fixed). Phase B9 complete (B9a to B9d).
