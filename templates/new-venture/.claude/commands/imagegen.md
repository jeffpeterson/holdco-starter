---
description: Generate a raster image (icon, mockup, hero/marketing image, OG/social card) from a
  freeform prompt via codex's image generator (bills the Codex/ChatGPT subscription, no API key).
  Headless and parallel — fire several at once, no waiting. Returns the saved file path(s).
argument-hint: "<freeform image prompt>  [--quality low|medium|high] [--size WxH] [--background transparent]"
disable-model-invocation: true
---

## Generate image: $ARGUMENTS

Run the fleet `imagegen` command (a Bash tool on PATH). It reuses the on-box Codex login to call
codex's hosted image generator (billing the Codex/ChatGPT subscription, no `OPENAI_API_KEY`), saves a
PNG into `assets/imagegen/` with a slugged filename, then prints the absolute path.

```bash
imagegen "$ARGUMENTS"
```

- It prints the saved path as the final stdout line — hand that path to whatever consumes the asset
  (page, email, favicon, OG tag) and wire it in. Move it into `public/`/the build dir if that's where
  the venture serves images from; don't leave a shipped asset only under `assets/imagegen/`.
- **`assets/imagegen/` is gitignored scratch** — generated candidates won't be committed; to ship an
  image, move/copy the chosen one into the venture's tracked assets location and commit it explicitly.
- **Runs in PARALLEL.** Each call is its own independent process; there is no shared "codex" to wait
  on. Need several assets? Fire them concurrently and collect the paths:
  ```bash
  imagegen "favicon: origami fox, teal" --background transparent --size 1024x1024 &
  imagegen "OG card: product hero on cream" --size 1536x1024 &
  imagegen "blog header: misty alpine valley" --size 1536x1024 &
  wait
  ```
- Quality: `--quality low` for quick drafts, `medium` (default) for most assets, `high` for finals or
  dense text. Sizes: `1024x1024` (square), `1536x1024` (landscape), `1024x1536` (portrait).
  `--background transparent` gives clean cutout icons/logos.
- If it errors about Codex login, `codex login` (ChatGPT flow) may need refreshing; if it's a rate
  limit, the Codex plan window is full — wait or retry. A separate-billing OpenAI Images API path is
  available with `imagegen --openai "…"` (needs `OPENAI_API_KEY`).

For compositing or editing an existing image, fall back to codex's imagegen skill directly
(`$CODEX_HOME/skills/.system/imagegen/`) — this command covers the common generate-from-prompt case.
