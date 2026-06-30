# Vendored: codex-imagegen-cli

Source: https://github.com/jdmnk/codex-imagegen-cli
Pinned commit: a739870aa9d600cfd0c382b6c06f38d0b1f5108b (v0.1.0)
Vendored: 2026-06-27
License: Apache-2.0 (see LICENSE)

Only the importable package `codex_imagegen_cli/` is vendored (sole runtime dep:
pillow). Used by `bin/imagegen` as the default engine: it reuses the on-box Codex
ChatGPT login (`~/.codex/auth.json`) to call the hosted image_generation tool at
chatgpt.com/backend-api/codex — billing the Codex/ChatGPT subscription, NOT the
OpenAI Images API. No OPENAI_API_KEY required.

Vetted on vendoring: stdlib-only networking (urllib); only outbound hosts are
chatgpt.com (image gen, bearer from auth.json) and auth.openai.com/oauth/token
(standard OAuth refresh). Token never printed; refreshed token written back to the
same auth.json (same as the official codex CLI). No telemetry/exfiltration.
subprocess is used only to read `codex --version` for a request header.

Caveat: this is an UNOFFICIAL, undocumented Codex surface (alpha). It may break
after a Codex update or policy change. If it stops working, bin/imagegen errors
clearly; the OpenAI-API path remains available via `imagegen --openai`.

To update: re-pull upstream, re-vet cli.py's network calls, bump the pinned commit.
