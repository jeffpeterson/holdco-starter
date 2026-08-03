/**
 * holdco-inbox — Cloudflare Email Worker
 *
 * Receives inbound mail to any fleet address (e.g. <id>@bot.example.com — the
 * Reply-To on operators' outgoing mail) via Cloudflare Email
 * Routing, and writes each parsed message to a bound KV namespace, keyed by
 * message.to (address-agnostic). holdco reads them with `bin/email-inbox`.
 *
 * SECURITY: this Worker holds NO secret. The KV namespace is attached as a
 * binding (env.INBOX) by Cloudflare at deploy time — there is no API key or token
 * inside the Worker. (This is why we use KV, not a GitHub Gist: a Gist write would
 * require putting a GitHub PAT inside the Worker, i.e. a secret living off-server.)
 *
 * Binding (set at deploy, see wrangler.toml / the MCP deploy):
 *   INBOX  — kv_namespace, holdco-inbox
 *
 * KV layout: key `msg:<epoch_ms>:<message-id>` -> JSON
 *   { id, received_at, from, from_header, reply_to, to, subject, text, read,
 *     verified, signing_domain, dkim, spf, dmarc }
 *
 * `id` is the KV key itself (unique, not the attacker-controllable Message-ID
 * header), so `bin/email-inbox --mark-read <id>` is always unambiguous.
 *
 * Flood protection: the raw MIME read is capped (MAX_RAW_BYTES) and every put
 * carries a 90-day TTL so old mail auto-expires instead of wedging the inbox.
 */

import PostalMime from "postal-mime";

// Cap raw MIME we parse — a single huge message can't blow up the Worker or KV.
const MAX_RAW_BYTES = 64 * 1024;
// Auto-expire stored mail after 90 days so a flood can't accumulate forever.
const KV_TTL_SECONDS = 90 * 24 * 60 * 60;

export default {
  async email(message, env, ctx) {
    const raw = await streamToString(message.raw, MAX_RAW_BYTES);

    // Sender authenticity (defense-in-depth). Cloudflare's gateway already
    // REJECTS, before this Worker runs, mail that fails both SPF and DKIM and
    // mail violating the sender domain's published DMARC policy. The residual
    // spoof class that still reaches us: a domain with no DMARC (or p=none),
    // spoofed with a misaligned-but-passing SPF/DKIM. So we grade in-Worker with
    // an ALLOWLIST — `verified` is true ONLY for an explicitly aligned pass.
    // Grade against the header `From:` domain (the identity DMARC/DKIM alignment
    // protects), NOT message.from (the envelope MAIL FROM — e.g. a bounce domain).
    const grade = gradeAuth(authResultsHeader(message.headers), fromDomainOf(message.headers, message.from));

    const key = `msg:${Date.now()}:${(message.headers.get("message-id") || crypto.randomUUID()).replace(/[<>]/g, "")}`;

    // Parse with postal-mime, the standard Workers MIME parser. Best-effort: a
    // parse that throws must never bounce mail that would otherwise land, so
    // the body falls back to the hand-rolled walk below.
    let parsed = null;
    try {
      parsed = await PostalMime.parse(raw);
    } catch (err) {
      console.error(`inbox MIME parse failed for ${key}: ${err}`);
    }

    const entry = {
      id: key,
      received_at: new Date().toISOString(),
      from: message.from,
      from_header: message.headers.get("from") || null,
      reply_to: message.headers.get("reply-to") || null,
      to: message.to,
      subject: message.headers.get("subject") || "(no subject)",
      text: bodyText(parsed, raw),
      read: false,
      verified: grade.verified,
      signing_domain: grade.signing_domain,
      dkim: grade.dkim,
      spf: grade.spf,
      dmarc: grade.dmarc,
    };

    await env.INBOX.put(key, JSON.stringify(entry), { expirationTtl: KV_TTL_SECONDS });
  },
};

// --- sender authenticity grading --------------------------------------------

// Cloudflare Email Routing records SPF/DKIM/DMARC verdicts in the
// `ARC-Authentication-Results` header; older docs/runtimes used the bare
// `Authentication-Results`. Read whichever is present (ARC first, it's the one
// Cloudflare actually stamps). Empty string if neither — grade stays unverified,
// never a false positive.
function authResultsHeader(headers) {
  return headers.get("arc-authentication-results") || headers.get("authentication-results") || "";
}

// The domain of the header `From:` ("Name <a@b.com>" -> "b.com"), which is what
// DMARC/DKIM alignment and the verdicts' header.from/header.d refer to. Falls
// back to the envelope MAIL FROM only if there's no parseable header From.
function fromDomainOf(headers, envelopeFrom) {
  const m = String(headers.get("from") || "").match(/@([a-z0-9.\-]+)/i);
  if (m) return m[1].toLowerCase();
  return (String(envelopeFrom).split("@")[1] || "").toLowerCase().trim();
}

// ALLOWLIST grade. `verified` is true ONLY when the auth-results header carries
//   - an explicit `dmarc=pass` whose header.from domain aligns with From:, OR
//   - an explicit `dkim=pass` whose header.d aligns with From:.
// A bare `dkim=pass` with a non-matching header.d (e.g. a relay's gappssmtp.com)
// is NOT verified. dmarc=none, spf=softfail, dkim=fail etc. are all unverified.
function gradeAuth(authRaw, fromDomain) {
  const lc = String(authRaw).toLowerCase();

  // Raw verdict tokens for debugging (RFC 8601: pass/fail/none/neutral/softfail/
  // temperror/permerror). A header can carry several results per method (relay +
  // origin), so report `pass` if any passed, else the first token seen.
  const verdict = (method) => {
    const tokens = [...lc.matchAll(new RegExp(`\\b${method}=(pass|fail|none|neutral|softfail|temperror|permerror)\\b`, "g"))].map((m) => m[1]);
    return tokens.includes("pass") ? "pass" : (tokens[0] || null);
  };
  const dkim = verdict("dkim");
  const spf = verdict("spf");
  const dmarc = verdict("dmarc");

  let verified = false;
  let signing_domain = null;

  // A methodspec's result and its properties live in the same `;`-delimited
  // segment, so split first to bind e.g. `dkim=pass` to its own `header.d=`.
  for (const seg of lc.split(";")) {
    if (/\bdmarc=pass\b/.test(seg)) {
      const hf = (seg.match(/header\.from=([a-z0-9.\-]+)/) || [])[1];
      if (hf && domainsAlign(hf, fromDomain)) { verified = true; signing_domain ||= hf; }
    }
    if (/\bdkim=pass\b/.test(seg)) {
      const hd = (seg.match(/header\.d=([a-z0-9.\-]+)/) || [])[1];
      if (hd && domainsAlign(hd, fromDomain)) { verified = true; signing_domain ||= hd; }
    }
  }
  return { verified, signing_domain, dkim, spf, dmarc };
}

// Relaxed alignment: the signing/header domain equals From:, or is its
// organizational-domain parent (e.g. d=example.com authenticates from=ops.example.com).
// We have no public-suffix list on the Worker, so "parent" is a literal suffix
// match — fine for our single-registrable-domain fleet; a sibling on a shared
// public suffix (e.g. *.co.uk) is the known gap, noted in docs/EMAIL.md.
function domainsAlign(signer, fromDomain) {
  if (!signer || !fromDomain) return false;
  return signer === fromDomain || fromDomain.endsWith("." + signer);
}

// Exported for unit tests only; the Worker runtime uses just the default export.
export { gradeAuth, domainsAlign, fromDomainOf, extractText, bodyText };

// --- helpers -----------------------------------------------------------------

async function streamToString(stream, maxBytes = Infinity) {
  const reader = stream.getReader();
  const chunks = [];
  let len = 0;
  while (len < maxBytes) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value);
    len += value.length;
  }
  // Drain any remainder so the stream closes cleanly, but don't keep it.
  reader.cancel().catch(() => {});
  const total = Math.min(len, maxBytes);
  const buf = new Uint8Array(total);
  let o = 0;
  for (const c of chunks) {
    if (o >= total) break;
    const slice = o + c.length > total ? c.subarray(0, total - o) : c;
    buf.set(slice, o);
    o += slice.length;
  }
  return new TextDecoder("utf-8").decode(buf);
}

function splitHeadersBody(block) {
  const m = block.match(/\r?\n\r?\n/);
  if (!m) return [block, ""];
  return [block.slice(0, m.index), block.slice(m.index + m[0].length)];
}

function parseHeaders(headerBlock) {
  const headers = {};
  // Unfold continuation lines (leading whitespace) then split.
  const unfolded = headerBlock.replace(/\r?\n[ \t]+/g, " ");
  for (const line of unfolded.split(/\r?\n/)) {
    const i = line.indexOf(":");
    if (i === -1) continue;
    headers[line.slice(0, i).trim().toLowerCase()] = line.slice(i + 1).trim();
  }
  return headers;
}

function decodeBody(body, cte) {
  cte = (cte || "7bit").toLowerCase();
  if (cte === "base64") {
    try { return atob(body.replace(/\s+/g, "")); } catch { return body; }
  }
  if (cte === "quoted-printable") {
    return body
      .replace(/=\r?\n/g, "")
      .replace(/=([0-9A-Fa-f]{2})/g, (_, h) => String.fromCharCode(parseInt(h, 16)));
  }
  return body;
}

// The stored body. postal-mime is a real MIME parser; it — not the hand-rolled
// walk below — decides what the body is. extractText stays as the fallback for
// a parse that threw: it reads the common shapes, but real senders compose MIME
// it does not, which is how letters carrying both html and text arrived with an
// empty body.
function bodyText(parsed, raw) {
  const text = (parsed?.text || "").trim();
  if (text) return text;
  const html = (parsed?.html || "").trim();
  if (html) return stripHtml(html);
  return extractText(raw);
}

function stripHtml(html) {
  return html.replace(/<[^>]+>/g, " ").replace(/&nbsp;/g, " ")
    .replace(/[ \t]+\n/g, "\n").trim();
}

// Recursively walk MIME to find the first text/plain part (falls back to stripped text/html).
function extractText(raw, depth = 0) {
  if (depth > 8) return "";
  const [headerBlock, body] = splitHeadersBody(raw);
  const headers = parseHeaders(headerBlock);
  // Match types case-insensitively but read the boundary off the ORIGINAL
  // header — boundaries are case-SENSITIVE, and lowercasing the whole
  // Content-Type silently loses every mixed-case one.
  const ct = headers["content-type"] || "text/plain";
  const type = ct.toLowerCase();

  if (type.startsWith("multipart/")) {
    const bm = ct.match(/boundary="?([^";]+)"?/i);
    if (!bm) return "";
    const boundary = "--" + bm[1];
    const parts = body.split(boundary).slice(1, -1);
    let htmlFallback = "";
    for (const part of parts) {
      const trimmed = part.replace(/^\r?\n/, "");
      const pct = (parseHeaders(splitHeadersBody(trimmed)[0])["content-type"] || "").toLowerCase();
      const text = extractText(trimmed, depth + 1);
      if (pct.startsWith("text/plain") && text.trim()) return text.trim();
      if (pct.startsWith("multipart/") && text.trim()) return text.trim();
      if (pct.startsWith("text/html") && !htmlFallback) htmlFallback = text;
    }
    return (htmlFallback || "").trim();
  }

  const decoded = decodeBody(body, headers["content-transfer-encoding"]);
  if (type.startsWith("text/html")) return stripHtml(decoded);
  return decoded.trim();
}
