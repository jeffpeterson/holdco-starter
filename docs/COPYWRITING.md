# Fleet copywriting: a brand-voice system to kill AI slop

> **STATUS: APPROVED + IMPLEMENTED (2026-06-27).** Rolled out to the template and the
> marketing-facing ventures. The owner approved the system and made four decisions that
> **override the design in Part 2/3 below where they conflict** — read these first:
>
> 1. **Scope = ALL customer-visible strings** — marketing copy *and* product UI / microcopy /
>    button labels / empty states / error messages / transactional email. Not just marketing.
> 2. **No separate `copywriter` persona.** The copywriter is **folded into the existing
>    `designer` persona**, which now carries the universal anti-slop kit + a **voice-gate**
>    critique-and-rewrite mode. (Wherever Part 2/3 says "the `copywriter` persona / agent," read
>    "the `designer` persona in voice-gate mode.")
> 3. **Measurement = self-check rubric only.** The designer self-checks its output against the
>    anti-slop checklist + the venture's `BRAND.md`. **No LLM-as-judge pass** was built — it
>    remains a documented future option (§1.6), not day-one.
> 4. **`BRAND.md` lives at the venture repo root** (§2.1's recommended location).
>
> **What shipped:** `templates/new-venture/` gained the anti-slop kit + voice-gate in
> `designer.md`, a root `BRAND.md` stub, a `/copy` command, and checklist lines in the designer's
> "Finish honestly" + `launch-check`; the operator persona/AGENTS.md/PLAYBOOK now require all
> customer-visible copy to pass the voice gate against `BRAND.md`. The same machinery + a
> `BRAND.md` **stub** applies to every **marketing-facing** venture; infra/non-marketing ventures
> (no customer copy) are exempt. Each operator authors its own `BRAND.md` voice and runs a one-time
> voice sweep — queued as per-venture work-orders (holdco does not write the voice). Affected
> operators need a graceful restart to pick up the new `designer` persona.

## The problem (owner's words)

> "Our copywriting across the board has the symptom of seeming AI-assistant generated
> (affectionately known as AI slop). My intuition is that each venture needs a copywriter
> persona that is prompted with a brand persona guide, and the operators pass all copy through
> this copywriter persona. Then this copywriter can write all the copy and keep it in the
> correct voice and style."

The owner's intuition is correct and matches the consensus that has formed in the marketing/AI
field over the last year. This doc confirms it with research, then designs it concretely for our
persona-panel architecture.

---

## Part 1 — Research: how teams fight AI slop and enforce brand voice

### 1.1 Why LLM copy reads as slop (root cause)

An LLM cold-prompted for marketing copy regresses to the **mean of the internet** — it outputs
the statistically-average phrasing of everything it was trained on. "When you prompt ChatGPT
cold, you're asking a tool trained on the entire internet to somehow channel your specific brand
voice" — so you get bland, generic, on-trend-but-faceless text. The fix is never "a better
one-shot prompt"; it's **grounding the model in brand-specific material and gating the output**
([Averi.ai](https://www.averi.ai/how-to/ai-content-that-doesn-t-sound-like-ai-the-brand-voice-system-that-actually-works),
[Klaviyo](https://www.klaviyo.com/blog/stop-the-ai-slop)).

### 1.2 The concrete tells of AI-generated copy (what to ban)

A living, citable list of the patterns that scream "an assistant wrote this." Sources:
[Wikipedia: Signs of AI writing](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing),
[axcontent](https://axcontent.com.au/blog/how-to-fix-your-ai-generated-content),
[Ruben Hassid](https://ruben.substack.com/p/its-not-x-its-y).

- **The antithesis tic:** "It's not just X — it's Y," "not only X but also Y." The single
  loudest tell; AI sprinkles it everywhere.
- **Rule-of-three abuse:** listing exactly three adjectives/clauses when it has nothing to say
  ("fast, simple, and powerful").
- **Em-dash overuse** as the default connector (the "ChatGPT hyphen"). Em dashes are fine; the
  *frequency* and uniform usage is the tell.
- **The banned lexicon (2026):** delve, realm, harness, unlock, tapestry, paradigm, cutting-edge,
  leverage, synergy, innovative, game-changer, seamless, robust, empower, streamline, elevate,
  scalable, holistic, revolutionize, transformative, "in today's fast-paced world," "in the realm
  of," "more than just," "designed to," "whether you're … or …," "the world of." *This list
  decays — words that were fine in 2024 sound robotic now; treat it as living.*
- **Structural tells:** every paragraph the same length; bullet lists where prose belongs;
  bolded lead-ins on every list item; a tidy "In conclusion / Ultimately" wrap-up; hedging
  everywhere ("can help," "may," "often").
- **Tone tells:** relentlessly upbeat, vague enthusiasm, zero specificity, no opinion, no concrete
  numbers or named details, perfectly balanced "on the other hand" both-sidesing.

### 1.3 Brand-voice guide formats that work *as LLM prompts*

The strong recurring finding: an LLM brand guide is **not** a traditional brand book. It must be
**explicit, specific, and example-heavy** because "AI can't infer what you mean — it needs
explicit rules and real examples" ([Oxford College of Marketing](https://blog.oxfordcollegeofmarketing.com/2025/08/04/ai-brand-voice-guidelines-keep-your-content-on-brand-at-scale/),
[CXL LLM tone-of-voice framework](https://cxl.com/blog/llm-tone-of-voice/),
[Search Engine Land](https://searchengineland.com/guide/how-to-train-in-house-llms-on-brand-voice)).
Components that consistently appear:

1. **3–5 voice adjectives — each defined behaviorally.** Adjectives alone are useless; every LLM
   already thinks it's "conversational but professional." You must say *what the adjective means
   in practice*: "**Direct** = lead with the point in sentence one; never bury it in paragraph
   three" beats "punchy."
2. **Behavioral rules, not vibes.** "Two-sentence paragraphs" beats "concise." "Lead with the
   counter-intuitive finding" beats "engaging."
3. **A three-tier lexicon:** **Always-use** / **Sometimes-use** / **Never-use** word lists
   (e.g. a B2B tool: "implementation" always, "solution" sometimes, "revolutionary" never).
4. **On-voice / off-voice example pairs.** "Off: *A new feature was launched to improve
   operational efficiency.* On: *We shipped a small fix that saves teams hours a week.*" These
   double as few-shot exemplars.
5. **10–15 reference snippets** that perfectly represent the brand across formats (headline, email
   opener, social post, product string) — the model pattern-matches against them.
6. **Formatting preferences** (paragraph length, list usage, punctuation, capitalization, emoji
   policy) and **per-scenario tone shifts** (error message vs. launch announcement vs. pricing).

The whole thing should fit on roughly **one page** — long enough to be specific, short enough to
prepend to every generation cheaply.

### 1.4 The "editor/copywriter persona as a gate" pattern

Role-prompting an LLM into a specific editorial persona measurably improves
**alignment/format-following/preference-satisfaction** — exactly the class of task copywriting is
([Learn Prompting: Role Prompting](https://learnprompting.org/docs/advanced/zero_shot/role_prompting),
[WaterCrawl](https://watercrawl.dev/blog/Role-Prompting)). The robust production pattern is a
**two-pass / gated** flow: a draft pass, then a **separate critique-and-rewrite pass** by an
editor persona that holds the voice spec and the anti-slop checklist. A fresh persona whose *only*
job is voice catches what a generalist drafting under task pressure misses. Universal advice
across every marketing source: **a human/expert review gate is the actual differentiator, not the
model** — AI is a draft engine, the editor makes it on-brand
([Merritt Group](https://www.merrittgrp.com/mg-blog/avoid-ai-slop-guide-for-marketers-and-pr/),
[MarTech](https://martech.org/3-strategies-for-killing-ai-slop-in-your-email-copy/)).

### 1.5 Few-shot / style-transfer technique

Including good *and* bad examples in-prompt (few-shot) "significantly improves the quality and
consistency of AI-generated outputs." Style transfer works best when the exemplars are analyzed
across four dimensions — **lexis, syntax, tone, semantics** — and turned into explicit guidelines
rather than left implicit ([Latitude](https://latitude.so/blog/how-examples-improve-llm-style-consistency),
[arXiv StyleAdaptedLM](https://arxiv.org/html/2507.18294v1)). Practical upshot for us: BRAND.md's
example pairs are not decoration — they are the highest-signal part of the prompt, so the
copywriter persona should always load them.

### 1.6 Measuring voice consistency (kept lightweight)

Heavy options exist (LLM-as-judge scoring, embedding-similarity to a reference corpus,
[Towards AI on LLM-as-judge styling](https://pub.towardsai.net/how-to-make-llms-write-stylishly-6691be12b970)),
and ultimately you "pair adherence with engagement/conversion to confirm stronger voice → better
outcomes" ([Fullcast](https://www.fullcast.com/content/brand-voice-guide/)). For our fleet we
deliberately start with the **cheapest mechanism that works**: a self-check rubric the copywriter
runs on its own output (passes the tells list? hits the 3–5 adjectives? respects the lexicon?),
plus the existing `bullhorn`/`hipster` panel reading BRAND.md during audits. LLM-as-judge scoring
is a documented *later* upgrade, not day-one ceremony.

### Strongest sources

1. **[Wikipedia: Signs of AI writing](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing)** — the
   most exhaustive, continuously-updated catalogue of concrete tells. Best basis for our ban list.
2. **[CXL — LLM tone-of-voice framework](https://cxl.com/blog/llm-tone-of-voice/)** — the clearest
   "behavioral instruction, not adjectives" framework with always/sometimes/never lexicon and
   correct/incorrect pairs. Best basis for BRAND.md's structure.
3. **[Averi.ai — the brand voice system that actually works](https://www.averi.ai/how-to/ai-content-that-doesn-t-sound-like-ai-the-brand-voice-system-that-actually-works)**
   — argues a *system* (ground + gate) beats prompt-tweaking; matches the owner's instinct exactly.
4. **[Search Engine Land — train LLMs on your brand voice (+ template)](https://searchengineland.com/guide/how-to-train-in-house-llms-on-brand-voice)**
   — a concrete fill-in brand-voice prompt template we can adapt for the BRAND.md stub.

---

## Part 2 — The design (fitted to our persona-panel architecture)

Three new pieces, each mapping onto a pattern we already have. The guiding principle:
**universal anti-slop rules live in the persona (fix once, every venture inherits); brand-specific
voice lives in `BRAND.md` (authored per venture).** That split is what keeps it both consistent
and lightweight.

### 2.1 `BRAND.md` — the per-venture brand persona guide (the new artifact)

- **Lives at the venture repo root** (peer of `AGENTS.md` / `BUSINESS-PLAN.md`), so it's
  discoverable and one merge unit. The `designer` persona already says "Read the brand guide (if
  the venture has one)" — this formalizes that dangling reference.
- **Authored by the operator during incubation**, as part of the BUSINESS-PLAN greenlight (the
  voice falls straight out of the positioning work the operator already does). It is *not* holdco's
  job, same as the business plan.
- **LLM-optimized format** (the §1.3 structure), kept to ~one page:
  - 3–5 voice adjectives, each defined behaviorally
  - Audience + what we sound like / never sound like
  - Behavioral do/don't rules (paragraph length, opener style, CTA style)
  - Lexicon: Always-use / Sometimes-use / Never-use
  - 6–10 on-voice / off-voice example pairs (the few-shot gold)
  - Per-channel notes (landing headline vs. transactional email vs. social vs. error string)
- It deliberately does **not** repeat the universal AI-tells ban list — that's in the copywriter
  persona, inherited by all.

### 2.2 `copywriter` — a new persona (the voice owner + gate)

- **Lives at `.claude/agents/copywriter.md`** alongside the panel. It is a **builder-class**
  persona (write tools), but a narrow one: its only domain is **words a customer reads**.
- **Carries the universal anti-slop kit** (the §1.2 tells + ban list + the self-check rubric) so
  every venture's copywriter is born knowing how to not sound like AI. Improving this one file
  upgrades the whole fleet's copy at once — the holdco leverage move.
- **Two modes, one persona:**
  - **write** — given a brief + `BRAND.md`, produce on-voice copy (headlines, email, product
    strings, social).
  - **gate/rewrite** — given existing/draft copy, rewrite to voice and report which tells it
    removed. This is the two-pass editor gate from §1.4.
- **Reads `BRAND.md` first, every time.** If `BRAND.md` is missing/stub, it says so and writes a
  sane default rather than blocking.
- **Collision rule with `designer`:** copy is the copywriter's; layout/markup/visuals are the
  designer's. In practice the designer builds the page with placeholder/first-draft copy and the
  copywriter does the voice pass on the copy strings (disjoint: the designer owns the template,
  the copywriter owns the copy file/strings), OR for pure-copy work (an email, a tweet) the
  copywriter writes and commits directly. Same disjoint-files discipline the builders already use.

### 2.3 The gate: how the operator routes copy through it (kept lightweight)

The owner's requirement is "**operators pass ALL copy through this copywriter.**" We make that a
**one-call reflex, not a process**:

- **`/copy` command** (`.claude/commands/copy.md`) — a thin wrapper that hands the target copy (or
  brief) + `BRAND.md` to the `copywriter` subagent in gate-or-write mode. One line for the operator.
- **A single checklist line** added in two existing places so it can't be skipped:
  - the **`designer` persona's "Finish honestly"** step: *no outward-facing copy ships without a
    copywriter voice pass against `BRAND.md`.*
  - the **`launch-check` command**: *all customer-visible copy has passed the copywriter gate.*
- That's the entire process. No new docs to maintain, no sign-off ceremony — just "any string a
  customer reads goes through `/copy` before it ships," enforced at the two natural choke points
  (build-finish and launch).

### Why this shape (vs. alternatives)

- **Why a builder persona, not a read-only panel voice?** The owner wants the copywriter to *write*
  copy, and read-only panelists (like `bullhorn`) can't edit. `bullhorn` still audits
  positioning/funnel; the `copywriter` owns the words. Complementary, not redundant.
- **Why split universal-tells (persona) from brand-voice (`BRAND.md`)?** One is fleet-wide and
  improves by editing one template file; the other is unique per venture. Mixing them would force
  re-authoring the ban list in every venture and lose the leverage.
- **Why a command + checklist, not a hook/CI gate?** Lightweight by design — operators already
  live in this loop; a heavyweight enforced gate is the kind of process operators route around.
  (A CI lint that greps for the worst tells is a possible *later* hardening, noted not required.)

---

## Part 3 — Template change + rollout

### 3.1 Template change (every FUTURE venture born with it)

In `templates/new-venture/`:

1. **Add `.claude/agents/copywriter.md`** — the persona with the universal anti-slop kit + the two
   modes + the self-check rubric.
2. **Add `BRAND.md`** (root) — a stub with the §2.1 sections and `{{TITLE}}`/`{{TAGLINE}}`
   placeholders + inline "fill this in" guidance, mirroring how `BUSINESS-PLAN.md` ships as a stub.
3. **Add `.claude/commands/copy.md`** — the `/copy` gate wrapper.
4. **Edit `.claude/agents/designer.md`** — add the "copy ships only after a copywriter pass" line
   to "Finish honestly," and the copywriter/designer collision rule.
5. **Edit `.claude/commands/launch-check.md`** — add the "all copy passed the gate" checklist line.
6. **Edit the `operator` persona + `docs/PLAYBOOK.md`** — make "author `BRAND.md`" an explicit step
   of the BUSINESS-PLAN greenlight (right when positioning is fresh).
7. **Edit `.claude/agents/README.md`** — list `copywriter` in the builders table.
8. **Prove the scaffold still works** per CLAUDE.md: `bin/holdco new` into a temp `VENTURES_ROOT`,
   confirm `rake tasks:index` runs and `./<name>` is executable.

### 3.2 Rollout to existing ventures (persona-driven, not hand-fed)

Marketing-facing ventures get it; infra/non-marketing ones are exempt.

| Venture | Status | Action |
|---|---|---|
| a launching consumer venture | launching | Full rollout — highest priority (live-facing copy now) |
| a venture building toward launch | building | Full rollout before launch |
| an incubating venture | incubating | Author `BRAND.md` as part of its business plan; persona ships when it greenlights |
| a live infra/trading venture | live | **Exempt** — no outward marketing copy |

Mechanism, per the CLAUDE.md meta-role (change the operator durably; don't hand-feed tasks):

1. After greenlight, update the **template** first (3.1).
2. For each in-scope venture, **file a board task** (`bin/holdco api:task <id> "Adopt copywriter
   brand-voice system"`) describing the three sub-steps, and let each operator pull it on its own
   loop:
   - author `BRAND.md` from its own positioning,
   - copy in the `copywriter` persona + `/copy` command + the two checklist edits,
   - run a **one-time voice sweep** of existing customer-facing copy (landing, emails, product
     strings) through the new gate.
3. Holdco reviews the first venture's `BRAND.md` + swept copy as the pattern, then lets the rest
   proceed.

### 3.3 Open questions for the owner

> **RESOLVED 2026-06-27 — see the status header.** All copy → in scope; copywriter folded into
> `designer` (no separate persona); `BRAND.md` at repo root; self-check rubric only (no
> LLM-as-judge). The questions below are kept for the record.


- **Scope of "all copy":** include in-app/product microcopy and transactional emails, or just
  marketing surfaces? (Recommend: all customer-visible strings, with per-channel tone notes in
  `BRAND.md`.)
- **Voice ownership boundary:** comfortable with copy as a *separate* builder from `designer`
  (cleanest), or fold the copywriter capability into `designer` to avoid a handoff? (Recommend:
  separate — a dedicated voice gate is the whole point of §1.4.)
- **`BRAND.md` location:** repo root (recommended, peer of AGENTS.md) vs. `docs/BRAND.md`.
- **Measurement appetite:** start with the self-check rubric only (recommended), or invest now in
  an LLM-as-judge voice score?

---

*Prepared as a decision for the owner. On greenlight, the implementation is delegated (template
edits + the per-venture board tasks); nothing here touches a venture or the live template until
then.*
