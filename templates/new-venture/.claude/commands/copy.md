---
description: Voice gate — run customer-visible copy through the designer's anti-slop voice gate
  against this venture's BRAND.md. Pass a string/file/brief; get back on-voice copy plus the tells
  that were removed. Use before any copy a customer reads ships.
argument-hint: "<copy, file path, or brief to write/rewrite>"
disable-model-invocation: true
---

## Voice gate: $ARGUMENTS

Hand $ARGUMENTS to the **designer** subagent in **voice-gate mode** (see
`.claude/agents/designer.md` → "Voice"). The designer owns customer-visible copy and carries the
universal anti-slop kit; this command is the one-call reflex that routes copy through it.

Invoke the designer (`Agent`, `subagent_type: designer`) with:

1. **Read `BRAND.md`** (repo root) first — the venture's voice adjectives, do/don't rules,
   Always/Sometimes/Never lexicon, and on-voice/off-voice example pairs. If it's missing or still
   a stub, proceed with sane on-voice copy and flag that `BRAND.md` needs authoring.
2. **If $ARGUMENTS is existing/draft copy (or a file of strings):** critique it as a hostile
   editor against the anti-slop checklist **and** `BRAND.md`, name every tell found (banned
   lexicon, antithesis "not just X, it's Y", rule-of-three, em-dash overuse, uniform paragraphs,
   detail-free upbeat tone), then **rewrite** it on-voice.
3. **If $ARGUMENTS is a brief (write new copy):** produce on-voice copy grounded in `BRAND.md`.
4. **Self-check** the result against the rubric: passes the tells list, hits BRAND.md's voice
   adjectives, respects its lexicon, carries a concrete detail/number/opinion where it counts.

Return the final copy plus a short list of the tells removed. Edit the strings in place (disjoint
files) and commit only when the work is a copy change the operator asked to ship.
