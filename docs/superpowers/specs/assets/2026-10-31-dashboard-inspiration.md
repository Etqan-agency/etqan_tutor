# Etqan Tutor dashboard: inspiration board (2026-10-31)

Research pass for the premium redesign. Theme: emerald `#146A51`, warm white `#FAF9F5`, muted gold `#B79A58`, charcoal `#202522`, with the gold arch line-drawing behind pages (`dashboard/src/ui/arch-backdrop.tsx`).

**Source rule.** Every URL below was fetched during this pass on 2026-10-31. Pages that blocked fetching (Toddle 401, ClassDojo help 403) and products with no public design material (Zid, Foodics, Qoyod) are named as gaps, not cited. Pixel values marked **[Etqan]** are our proposals. None of the sources publish row heights or Arabic type sizes, so those values are not borrowed.

---

## 1. App shell and navigation

**Linear: "Behind the latest design refresh" (March 2026)** — https://linear.app/now/behind-the-latest-design-refresh
- Borrow: its two principles, "Don't compete for attention you haven't earned" and "Structure should be felt not seen". The sidebar is "a few notches dimmer" than the content, icons are fewer and smaller, team icons lose their coloured backgrounds, dividers are fewer and softer, and header actions sit in predictable places.
- Borrow: a warm grey neutral in place of cool blue-grey. This matches our warm white. Their warning applies to us too: too much warmth turns muddy.
- Don't copy: tabs and the Electron history buttons. They are desktop-app chrome that a web dashboard doesn't need.

**Linear: "How we redesigned the Linear UI"** — https://linear.app/now/how-we-redesigned-the-linear-ui (and changelog https://linear.app/changelog/2024-03-20-new-linear-ui)
- Borrow: themes generated from three inputs (base, accent, contrast) instead of about 98 variables, built in LCH so equal lightness looks equally bright. This fits per-academy branding: derive the whole palette from the academy's primary colour plus a contrast setting.
- Borrow: Inter Display for headings and Inter for UI text, a split we can mirror with a display cut for page titles only.
- Don't copy: the "magic blue" chrome. Linear limited the blue on purpose, and we should treat emerald the same way, as an accent and not a surface.

**Vercel: new dashboard navigation (default since 2026-02-26)** — https://vercel.com/changelog/dashboard-navigation-redesign-rollout
- Borrow: horizontal tabs replaced by a **resizable, hideable sidebar**, with the same items at team and project level, the most common workflows first, and "projects as filters" (switch from the team view to the same page scoped to one project in one click). For us: "All classes" ↔ one class, "All students" ↔ one student.
- Borrow: a **floating bottom bar on mobile, built for one-handed use**. It suits parents and students, who mostly arrive on phones.
- Don't copy: the developer-first ordering. Our order comes from each role's daily job.

**Stripe Dashboard: navigation basics** — https://docs.stripe.com/dashboard/basics
- Borrow: the sidebar runs in sections. First the core objects (Home, Balances, Transactions, Customers, Product catalog), then a **Shortcuts** section of pinned and recently visited pages, then Products, with lesser ones folded under **More**. Press `?` for a keyboard-shortcut sheet.
- Borrow: Home also "surfaces important notifications, like unresolved disputes". Alerts belong on Home, not in a separate inbox page.
- Don't copy: the breadth. Stripe has more than 15 product areas. An academy admin needs about 8 top-level items.

**Notion: sidebar** — https://www.notion.com/help/navigate-with-the-sidebar
- Borrow: sections with collapsible headings, a per-section "Show N items" (5 to all) with a "More" link, fixed utility rows at the bottom (Help, Trash), `cmd/ctrl+\` to toggle, and a drag-resizable edge.
- Don't copy: user-customisable tabs and sections. That is too much configuration for teachers and parents.

**shadcn/ui Sidebar (our primitive)** — https://ui.shadcn.com/docs/components/sidebar
- Borrow as-is: `SIDEBAR_WIDTH 16rem`, `SIDEBAR_WIDTH_MOBILE 18rem` in a `Sheet`, `cmd/ctrl+B` toggle, `collapsible="icon"`, `variant="inset"`, `SidebarGroupLabel`, `SidebarMenuBadge` for counts, and `isActive`. For RTL: `<Sidebar dir="rtl" side="right">`, pass `dir` to `SheetContent`, and flip the trigger icon with `rtl:rotate-180`.
- Don't copy: the `floating` variant on dense admin pages. The shadow competes with the arch.

**Quran.com (built with Tarteel)** — https://tarteel.ai/blog/quran-com-and-tarteel-partnership-an-all-new-quran-com/
- Borrow: a **⌘K command bar "anywhere on the site"** that jumps by name *or number* (surah, verse, page), with full RTL layout. Our audience already knows this pattern from Quran.com: jump to a student, class, session or invoice number.

---

## 2. Data tables and lists

**Vercel Geist Table** — https://vercel.com/geist/table
- Borrow: Title Case noun headers (in English), `tabular-nums` on numeric columns, column widths through `col` elements, a striped or interactive body, and a footer summary row.
- Borrow: **an em dash "—" for unknown or not-applicable values**, never `N/A`, `null` or blank. The Empty State renders *outside* the table, not as an empty `tbody`.
- Borrow: sortable headers are `<button>`s. The arrow is decorative, and the button announces the next sort state.

**Vercel design rules** — https://vercel.com/design.md
- Borrow: text columns and their headers align to the start, **numeric columns and their headers align to the end** (totals and placeholders included), and cells use `vertical-align: baseline`. Use compact density only for lookup tables.
- Borrow: "Use colour only when it adds meaning, and always pair it with a non-colour cue. Do not colour a favourable figure green by default." Reject badges for ordinary metadata.
- Borrow: prefer spacing and type before borders or surfaces, and avoid nested cards.
- Don't copy: the outright rejection of shadows, glass and gradients for every surface. We keep one ornament layer (the arch) by design.

**Stripe Apps: full-page list and detail** — https://docs.stripe.com/stripe-apps/patterns/full-page-apps
- Borrow: a status column as a mapped cell (`Active→positive`, `At risk→warning`, `Churned→negative`), clickable rows that open a detail route, `pageSize: 10` pagination, and a detail page with **breadcrumbs back to the list** in a two-column layout (primary content plus a metadata side column). Create and edit flows run in a drawer (FocusView) that keeps the user's place.

**Stripe Apps: filter controls** — https://docs.stripe.com/stripe-apps/patterns/filter-controls
- Borrow: one chip per filterable attribute. An unset chip shows "+ Status" and opens a menu. A set chip shows "Status: Active ×". A **"Clear filters" link sits at the end and appears only while a filter is active**. Chip labels match the column headers. Filter before paginating so the counts stay true.

**Stripe Apps: empty state** — https://docs.stripe.com/stripe-apps/patterns/empty-state
- Borrow the copy rules: the title says what's missing, with a period ("No students yet."). The description stays under 14 words and says when data appears. The action echoes the title ("Add student", not "Get started").
- Borrow: **a filtered-to-zero list never offers "create your first"**. It says "No students match your filters." and offers Clear filters.
- Borrow: a section-level empty state is a dashed 1px border, the title in regular body weight, and the description as a centred secondary caption.
- Borrow the render order: loading → error (with retry) → empty → content.

**Stripe Apps: loading** — https://docs.stripe.com/stripe-apps/patterns/loading
- Borrow: **spinner delay of 200–300 ms** for normal fetches (0 ms for operations known to be slow, 100 ms for view transitions). Size the indicator to its scope (page, section or cell). **Never wrap the tabs or filter bar in the loading state**, because users lose their context. Buttons use a `pending` state that also disables them.
- Adapt: for tables, prefer skeleton rows at the real row height over a spinner, so the layout doesn't shift.

**Mobile card fallback.** None of the fetched sources specify one. **[Etqan]** Below 640px, each row becomes a card. The primary identifier (name) goes top-start, the status badge top-end, and two or three key fields sit underneath as label/value pairs. The whole card is the tap target, and row actions go into a `⋯` menu at the end.

---

## 3. KPI cards and role home screens

**Stripe: home charts** — https://support.stripe.com/questions/dashboard-home-page-charts-for-business-insights
- Borrow: an "overview" widget set the admin can Add, Edit or reorder. It has three controls: **date range**, **time unit** (adjusts automatically: hourly or daily for short ranges, weekly or monthly for long ones) and **comparison period**. Every delta names what it compares against.
- Don't copy: multi-currency estimate footnotes. Show a single academy currency instead.

**Stripe Apps: overview page** — https://docs.stripe.com/stripe-apps/patterns/full-page-apps
- Borrow: "progressive" overviews that lead with the summary and let details follow. A two-column overview has a wide primary column (charts at about 182px high) and a narrow secondary column of modules.

**Canvas LMS: dashboard (Illinois State guide)** — https://help.illinoisstate.edu/technology/support-topics/canvas/overview-of-canvas
- Borrow for **teachers**: Canvas offers three views. Card View shows favourite courses as cards with quick links (assignments, announcements, discussions, files). List View is an agenda that opens on today, with a **Today** button. Recent Activity runs about four weeks. A persistent **To Do sidebar** holds upcoming work and recent feedback. For our teachers: today's sessions as an agenda, then "To do" (attendance to mark, recitations to grade, reports due).
- Don't copy: the course-card colour wheel. It fights the brand, so use a neutral card with a small coloured class marker.

**Google Classroom: guardian summaries** — https://support.google.com/edu/classroom/answer/7075223?hl=en
- Borrow for **parents**: the guardian view is exactly three blocks: **Missing work** (late when sent), **Upcoming work** (today and tomorrow for daily, the coming week for weekly) and **Class activity** (recent teacher posts). The parent home should lead with these for each child, plus a child switcher.
- Don't copy: email-only delivery. We have a live home screen and web push.

**Salla 4.0 (Saudi merchant dashboard)** — https://help.salla.sa/en/article/salla-4-0-new-platform/sv8h94gami0nwmahx50iawf7
- Borrow: "every section… in one organised, clear place", switching stores without leaving the page (our academy switcher), and a **custom dashboard showing only the metrics the merchant picks**. Bulk "select all" acts across all statuses.
- Don't copy: "more than 60 analysis tools". Admins need four headline KPIs and a link to reports.

**Gaps.** Toddle (support page 401) and ClassDojo (help centre 403) could not be fetched, so they aren't cited. From search snippets only: Toddle's parent home is a card list with "Assignments and deadlines" split into Upcoming, Overdue and No due date, and a child switcher. This agrees with Google Classroom's model.

---

## 4. Premium RTL and Arabic patterns

**Material Design bidirectionality (M1; the M2/M3 pages render client-side and couldn't be fetched)** — https://m1.material.io/usability/bidirectionality.html (mirror: https://www.mdui.org/en/design/1/usability/bidirectionality.html)
- Mirror: back/forward and other directional arrows, the order of nav and overflow icons, checkboxes to the right of their labels, **progress bars filling right→left**, calendar days right→left, "next" on the left, and icons that depict text lines.
- Don't mirror: **clock, refresh and history** (they still turn clockwise), **search** (right-handed), the camera, physical objects, the off-state slash, **media controls**, **charts and graphs**, and **numbers, times and phone numbers**. LTR words such as URLs stay LTR.

**Wikimedia Codex bidirectionality** — https://doc.wikimedia.org/codex/latest/style-guide/bidirectionality.html
- Borrow: also mirror steppers, paginations, sliders and toggles. Don't mirror **check marks**, time items, currency symbols, URLs and emails. **Phone numbers stay left-aligned in both directions.** Keep each list aligned in one direction, and give each item its own `lang`/`dir`.

**W3C Arabic Layout Requirements (alreq)** — https://www.w3.org/TR/alreq/
- Borrow: digits always run LTR. **Regional digit choice is real**: Morocco and Algeria use European digits, while Egypt, Saudi Arabia and Iraq use Arabic-Indic digits. So make digits an academy setting (`Intl.NumberFormat('ar', {numberingSystem})`), not hard-coded.
- In Arabic text the **% sign comes before the number** with no space. "Arabic ascenders and descenders extend much further than those of the Latin script", so Arabic needs more line height.

**Salla embedded-app design guidelines** — https://docs.salla.dev/embedded-sdk/design-guidelines
- Borrow: **one typeface family for Arabic and English** (PingARLT, in Regular, Medium and Bold only), Hugeicons with consistent stroke weight, semantic colour tokens with light and dark pairs, a near-white workspace background (`#f8f8f8`), and a dark-teal primary (`#004d5b`). That primary shows a deep green-teal reads as premium in the Saudi market, which validates our emerald.
- Don't copy: their mint secondary (`#73fcd7`), which is too loud beside gold.

**Arabic type** — https://design.google/library/modernizing-arabic-typography-type-design · https://fontsource.org/fonts/noto-sans-arabic/about
- Borrow: pair Arabic and Latin from **one matched family** (Google names Cairo, El Messiri and Lemonada, with Cairo's Latin and Arabic "neatly aligned"). Noto Sans Arabic ships **`tnum`** (tabular figures), weights 100–900 and a width axis down to 62.5, useful for dense tables. Check `tnum` in whichever font we ship.
- **[Etqan]** Arabic UI text 1px larger than Latin at each step (body 15 vs 14), line-height 1.7 vs 1.5, no letter-spacing, no uppercase, at most semibold (600) in UI text.

**Gap.** Zid, Foodics and Qoyod publish no dashboard design guidance that could be fetched, so they aren't cited.

---

## 5. Ornament that stays out of the data's way

**Etqan's current implementation (baseline)** — `dashboard/src/ui/arch-backdrop.tsx`, `index.css` §arch-backdrop. This is already the right model: a mask-painted `--accent` (no second colour), top-anchored, `min(46rem,85vh)` tall, fading through `linear-gradient(#000 55%, transparent)`, opacity 0.55 light and 0.4 dark, `aria-hidden`, `pointer-events:none`, cards opaque, and a "quiet" variant for dense pages.

**MDN `mask-image`** — https://developer.mozilla.org/en-US/docs/Web/CSS/mask-image
- Borrow: gradients are valid masks, so intersect the arch mask with a linear fade (as we do) or a **radial vignette** (`radial-gradient(black 50%, transparent 60%)`) to keep the centre column clear on wide screens. Baseline support has been widely available since 2023-12. A mask that fails to load paints nothing, which is a safe failure for decoration.

**MDN `forced-colors`** — https://developer.mozilla.org/en-US/docs/Web/CSS/@media/forced-colors
- Borrow: in forced-colours mode `background-color` is overridden with system colours, and decoration should not be "restored". **Action: add `@media (forced-colors: active) { .arch-backdrop { display:none } }`**. `index.css` has no such rule today.

**Mishkat (Quran and Sunnah app, brand and UI case study)** — https://contra.com/p/rcAFe7Mo-mishkat-brand-and-digital-experience-design-build
- Borrow: arches, geometric patterns, lanterns and crescents carry the **brand surfaces** (billboards, the marketing site), while **"inside the app, motifs are applied more lightly so content has room"**. Serif headings carry warmth, sans UI text carries the work, and the strongest brand colour is reserved for actions.
- Don't copy: alternating deep-colour page bands. They compete with data.

**Linear (principle)** — https://linear.app/now/behind-the-latest-design-refresh
- Apply "structure should be felt not seen" to ornament. The arch should register in peripheral vision only. If a user can trace a line of it while reading a number, it is too strong.

---

## Top 12 actionable rules for Etqan

1. **Shell:** shadcn `Sidebar` `variant="inset"`, 16rem wide, `collapsible="icon"`, `⌘/Ctrl+B`; RTL `side="right"`. The sidebar surface sits one step dimmer than the content (Linear). Inactive items 14px in `muted-foreground`. The active item gets an emerald 8–10% tint, emerald text and medium weight, with no bar or glow.
2. **Grouping:** at most 4 labelled groups per role (admin: Overview · Teaching · People · Finance · then Settings pinned at the bottom). Group labels 12px medium muted, never uppercase in Arabic. Counts go in `SidebarMenuBadge`.
3. **Topbar 56px [Etqan]:** breadcrumb at start (Stripe detail pattern: List › Item), a search trigger showing `⌘K`, then notifications, academy switcher and avatar at end. ⌘K jumps by name *or number* (Quran.com).
4. **Mobile:** below 768px the sidebar becomes an 18rem Sheet from the inline-start edge (right in RTL). Parent and student roles also get a 4–5 item bottom bar for one-handed use (Vercel).
5. **Tables [Etqan values]:** rows 44px desktop and 52px touch; header 12px semibold muted on a faint tint. Uppercase plus 0.04em tracking **only in LTR**; Arabic headers stay 13px semibold sentence case. Text columns start-aligned, **numeric columns and their headers end-aligned with `tabular-nums`**, `vertical-align: baseline`, and "—" for missing values (Vercel).
6. **Status:** a badge is dot plus label, never colour alone. Use 4 semantic tones only (positive, warning, negative, neutral). Don't make good numbers green by default (Vercel).
7. **States:** render loading → error (with Retry) → empty → content. Skeleton rows match row height. Spinners wait 250ms. The filter bar and tabs stay visible while loading (Stripe).
8. **Empty copy:** "No students yet." plus a sentence under 14 words plus a matching action ("Add student"). When filtered to zero: "No students match your filters." plus Clear filters, never a create CTA (Stripe).
9. **Filters:** chips above the table, labelled like the column headers. "Clear filters" appears only while one is active. Filter before paginating (Stripe).
10. **Role homes:** Admin gets 4 KPI cards (label 13px muted, value 28px semibold tabular, delta with "vs last month") plus an alerts strip (Stripe). Teacher gets today's session agenda first, then To do (attendance, grading, reports) (Canvas). Parent gets a child switcher, then Missing · Upcoming · Recent activity (Google Classroom).
11. **Bidi:** wrap every number, phone, email, URL and ID in `<bdi>` or `dir="ltr"`. Phone numbers stay LTR and start-aligned. In Arabic, `%` comes before the number. The digit system is an academy setting via `Intl.NumberFormat` (alreq). Arabic text runs +1px with line-height 1.7. Mirror chevrons, arrows, steppers and progress (`rtl:-scale-x-100`). Never mirror clock, refresh, search, check, play or charts (Material, Codex).
12. **Ornament:** the arch stays top-anchored, faded by 55% height, at opacity ≤0.55 light and ≤0.4 dark, and at 0.25 on table, invoice and report pages. Cards stay opaque, and nothing numeric ever sits directly on the line-work. Hide the arch for `forced-colors` and print. Inside the app it frames the page; it never decorates components (Mishkat, Linear).
