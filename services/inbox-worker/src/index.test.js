// Unit tests for the ALLOWLIST sender-authenticity grade (run: `node --test`).
//
// The grade must verify ONLY an explicitly aligned dmarc=pass / dkim=pass, and
// must reject the residual spoof class that reaches the Worker (no-DMARC domains
// spoofed with a misaligned-but-passing SPF/DKIM) — the denylist this replaced
// wrongly trusted dmarc=none / spf=softfail / misaligned dkim=pass.

import { test } from "node:test";
import assert from "node:assert/strict";
import { gradeAuth } from "./index.js";

// [name, auth-results header, From: domain, expect verified, expect signing_domain]
const cases = [
  // Genuine bot.example.com self-send (captured live). dmarc=pass + aligned dkim.
  ["genuine bot.example.com",
    "i=1; mx.cloudflare.net; dkim=pass header.d=cloudflare-smtp.net header.s=cf2024-1; dkim=pass header.d=bot.example.com header.s=cf-bounce; dmarc=pass header.from=bot.example.com policy.dmarc=reject; spf=none smtp.helo=x; spf=pass smtp.mailfrom=bounces@cf-bounce.bot.example.com",
    "bot.example.com", true, "bot.example.com"],

  // Genuine owner mail: example.com publishes NO DMARC, so even real mail is dmarc=none.
  // Must still verify via the aligned DKIM signature — the reason an allowlist
  // needs the dkim path, not just dmarc=pass.
  ["genuine owner@example.com (dmarc=none, dkim aligned)",
    "mx.cloudflare.net; dkim=pass header.d=example.com header.s=google; dmarc=none header.from=example.com; spf=pass smtp.mailfrom=example.com",
    "example.com", true, "example.com"],

  // Spoofed owner: attacker DKIM-signs their own domain, From: owner@example.com.
  ["spoofed owner@example.com (dkim header.d=evil.com)",
    "mx.cloudflare.net; dkim=pass header.d=evil.com header.s=s1; dmarc=none header.from=example.com; spf=pass smtp.mailfrom=evil.com",
    "example.com", false, null],

  // Relay-signed only (Google Groups / gappssmtp): dkim=pass but unaligned.
  ["relay gappssmtp non-alignment",
    "mx.cloudflare.net; dkim=pass header.d=acme.com.gappssmtp.com header.s=x; dmarc=fail; spf=softfail",
    "acme.com", false, null],

  // The exact denylist gaps the old /\b(dmarc|spf|dkim)=fail\b/ missed:
  ["dmarc=none only", "mx; dmarc=none header.from=example.com; spf=pass", "example.com", false, null],
  ["spf=softfail only", "mx; spf=softfail smtp.mailfrom=example.com", "example.com", false, null],

  // dmarc=pass but for a different header.from than the displayed From:.
  ["dmarc=pass misaligned header.from",
    "mx; dmarc=pass header.from=evil.com; dkim=pass header.d=evil.com", "example.com", false, null],

  // Relaxed alignment: an org-domain parent DKIM signature authenticates a subdomain From.
  ["relaxed parent alignment (d=example.com, from=ops.example.com)",
    "mx; dkim=pass header.d=example.com header.s=s; dmarc=none", "ops.example.com", true, "example.com"],

  // No auth-results header at all (older runtime) — never a false positive.
  ["empty header", "", "example.com", false, null],

  // dkim=fail must not verify even if the domain matches.
  ["dkim=fail aligned domain", "mx; dkim=fail header.d=example.com; dmarc=fail", "example.com", false, null],
];

for (const [name, header, from, wantVerified, wantSigner] of cases) {
  test(name, () => {
    const g = gradeAuth(header, from);
    assert.equal(g.verified, wantVerified, `verified for "${name}"`);
    assert.equal(g.signing_domain, wantSigner, `signing_domain for "${name}"`);
  });
}

// --- body extraction ---------------------------------------------------------
// Letters carrying BOTH html and text were landing with an empty body. The
// hand-rolled walk reads a canonical two-part multipart/alternative fine, so
// the break was in MIME it had never seen — which is why postal-mime, a real
// parser, now decides the body and the walk is only the fallback.

import PostalMime from "postal-mime";
import { extractText, bodyText } from "./index.js";

const ALTERNATIVE = [
  `Content-Type: multipart/alternative; boundary="B0UND"`,
  ``,
  `--B0UND`,
  `Content-Type: text/plain; charset=utf-8`,
  ``,
  `hello plain`,
  `--B0UND`,
  `Content-Type: text/html; charset=utf-8`,
  ``,
  `<p>hello html</p>`,
  `--B0UND--`,
  ``,
].join("\r\n");

test("postal-mime reads the html+text shape that arrived body-less", async () => {
  const parsed = await PostalMime.parse(ALTERNATIVE);
  assert.equal(bodyText(parsed, ALTERNATIVE), "hello plain");
});

test("bodyText prefers the parsed text over the hand-rolled walk", () => {
  assert.equal(bodyText({ text: "from postal-mime" }, ALTERNATIVE), "from postal-mime");
});

test("bodyText strips the parsed html when there is no text part", () => {
  assert.equal(bodyText({ html: "<p>only html</p>" }, ""), "only html");
});

test("bodyText falls back to extractText when the parse threw", () => {
  assert.equal(bodyText(null, ALTERNATIVE), "hello plain");
});

test("extractText preserves a mixed-case multipart boundary", () => {
  const raw = [
    `Content-Type: multipart/mixed; boundary="FIXTURE-BOUNDARY"`,
    ``,
    `--FIXTURE-BOUNDARY`,
    `Content-Type: text/plain; charset=utf-8`,
    ``,
    `hello from scanner`,
    `--FIXTURE-BOUNDARY--`,
    ``,
  ].join("\r\n");
  assert.equal(extractText(raw), "hello from scanner");
});
