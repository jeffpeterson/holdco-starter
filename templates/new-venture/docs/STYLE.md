# Code style — the fleet's default

This is the code style the fleet writes by default — holdco tooling, venture code, template
scaffolds. It's an opinionated **functional-first** house style: small composable parts, examples
over prose, no speculative abstraction. The ten rules below are JS-flavored; the Ruby/Rails and
CSS sections carry the same *values* into those languages' native idiom — do the same for any
language not covered here.

If you're adapting this starter to a different house style, this is the file to edit — every
builder persona is told to read it before writing code, so changing it here retunes the whole
fleet.

## The ten rules

1. **`export let name = curried => arrow`** — small, config-first / data-last, composable.
   **2-space indent** (every language), no semicolons, single quotes, loose `==` by default. One
   expression per function wherever possible. `let` by default; `const` only for true module
   constants (often SCREAMING_CASE). Named `function`/`function*` where you need recursion,
   hoisting, `this`, or a generator — arrow is the default, not a mandate. **Code and comments wrap
   at 80 columns**; when an arrow function runs long, break after the `=>` (or the `=`) and
   continue on the next line, indented — see `always` in the module-shape example below.
2. **`///` doctests over prose.** Executable examples (`input -> output`, `~>` for async/pattern-
   match, `/// let …` for setup, `// /` to skip one) are the spec, docs, and test suite at once.
   Prose comments are reserved for *rationale* — especially for what is deliberately absent.
3. **No classes** unless the thing is a long-lived identity — and even then: public fields,
   arrow-bound methods, no deep or domain inheritance. Thin `extends` of platform identity types
   (`Error`, `CustomEvent`, `EventTarget`, `HTMLElement`) is idiomatic. Otherwise a factory closure
   returning a plain object of functions. Compose with `include`/`mix` mixins, not hierarchy. File
   taxonomy: PascalCase filename = one class/identity module (`Enum.js`), lowercase = a function
   vocabulary (`fp.js`). A class hierarchy tends to become cumbersome — prefer composition.
4. **Effects are data.** Record them as events/tuples appended to state or a log, resolved by a
   separate pass — never performed inline in the code that decides them. All communication is
   serialized through the store's state; nothing hides in closures.
5. **Dispatch with a `when`-style table** (value-dispatch on a computed tag, `_` default). A small
   `switch (typeOf(x))` inside a leaf function is fine; what's banned is the switch-shaped
   orchestrator that sequences phases. Prefer a ternary chain over a 3-case switch.
6. **Nil short-circuiting over defensive `if`s** — a `pipe` that stops on nil replaces most error
   plumbing. Errors are tiny `Error` subclasses used as control flow
   (`catch (e) { if (e instanceof NotFound) … }`) plus `??` defaults — no wrapping layers, no
   result types. Async is transparent: helpers only go async when an input is a promise; `pipe`
   awaits mid-stream.
7. **Plain JS, not TS.** Default to `.js` + `///` doctests; inline executable examples do the
   correctness work types are claimed to do. If a contract boundary genuinely needs types (an API
   other people consume), write a separate `.d.ts` file rather than weaving TS syntax through the
   source. Never: `as` casts, enums, `private`/`readonly` ceremony.
8. **Names: short, lowercase, evocative** (`ok`, `walk`, `beget`, `tap`, `when`). 2–8 chars is the
   norm; the composed call site must read like a sentence. **No verb-prefix ceremony** —
   `createContext`→`context`, `resolveIdent`→`ident`; use named imports so call sites read bare.
   This is the specific "generated-looking" smell to hand-edit out of LLM code. One refinement: a
   prefix that *disambiguates* earns its place — when two vocabularies share nouns in one module
   (parsing functions and AST constructors both want `number`), keep the primary constructors bare
   and prefix the secondary vocabulary (`parseNumber`). **Prefixes and namespaces are for
   disambiguation, never ceremony** — same test for a namespace import vs bare named imports. No
   `Manager`/`Factory`/`Impl`; variants get a suffix (`map`, `mapObj`), not an options bag.
9. **Don't build the speculative layer.** An abstraction must earn its place by removing code from
   callers, not by adding indirection. Leave a visible stub or a comment saying why the layer is
   absent (ship `cmp` with an empty `switch` and a TODO rather than a premature abstraction).
10. **Build a vocabulary, then compose it.** A file reads top-to-bottom as later exports made of
    earlier ones (`export let inc = add(1)`). Complexity comes from composition, never from a long
    body with phases. Primitives are protocol-extensible — `add` checks `has('add')` first so user
    types slot into the vocabulary. A hand-written module tops out ~600 lines; grow a system as
    many small files, never a monolith.

## The shape of a module

```js
export let id = x => x

export let always = x =>
  () => x

/// tap(inc)(1) -> 1
export let tap = f => (x, ...rest) => (f(x, ...rest), x)

export let inc = add(1)
export let reject = compose(filter, negate)
```

A function longer than ~10 lines is rare and always a genuine algorithm. There is no
"orchestrator" function. State is an immutable-ish plain value threaded through functions
("mutation" is copy-tweak-return: `beget(env, e => e.k = v)`). Generators for streams of
alternatives — laziness and backtracking fall out of `yield*`, not a scheduler class.

## Testing

No test framework dependency, ever. Doctests are *discovered*: a runner scans source files for
`///` lines, extracts them, and codegens a test module (`->` equality, `~>` pattern-match,
`/// let …` setup, `// /` skip). Scenario tests go in `*.test.js` using a tiny in-repo
`suite(name, ({it, equal, ok}) => …)` micro-framework; benchmarks in `*.bench.js`. CI is one job
that runs `bin/test`.

## The whole app

- **Platform is the framework.** Deno (permissions in the script shebang), no `package.json`, no
  bundler, no build step — browser and server run the same ES modules; shared `lib/` is
  isomorphic.
- **~Zero dependencies, vendored.** The rare dep is copied into `vendor/` via an import map and
  refreshed by a script. The server, test runner, DOM builder, store are all hand-rolled small
  files in `lib/`.
- **Pure core + thin imperative shell.** Apps split into a pure curried data module (`sim.js`:
  data-in-data-out, its own doctests) and a small DOM shell (`main.js`: module-level `let` state,
  `querySelector` bindings at top, `addEventListener`, template-literal `innerHTML` rendering or a
  variadic `tag()` builder, `requestAnimationFrame` loop). No JSX, no vdom, no reactive lib.
- **CSS: see the component system below.** HTML is minimal: unquoted attributes, one `type=module`
  script.
- **Server** is a hand-rolled ~60-line middleware `Application` (`app.use(fn)`, recursive stack)
  plus small composable middlewares. Deploy is a Dockerfile that runs the dev server.

## CSS — the component system

Designed to scale — one file + one import + a var contract per component, so adding UI never
touches existing files and re-skinning never touches structure.

- **One file per component**; PascalCase filename = the block (`Card.css` → `.Card`). The
  `components.css` manifest is nothing but `@import` lines — a new component is one file plus one
  import.
- **Three-separator naming:** block `.Card` (PascalCase); element `.Card_Head` (underscore,
  PascalCase); modifier/state `.Button-primary`, `.Card-sticky` (hyphen, lowercase).
- **Custom properties are the variant and theming mechanism** — the scaling trick. A component
  declares local vars at the top and consumes them (`--background: var(--button)` … `background:
  var(--background)`); a variant just *re-points* a var (`.Button-primary { --background:
  var(--primary) }`), never re-declares rules. Semantic tokens layer over primitives
  (`--danger: var(--red)` over `--red: red`) plus a calc-derived spacing scale (`--gap`,
  `--half-gap`, `--radius`); a theme is a var-override file. Structure and skin stay fully
  separable.
- **Lean on modern CSS:** zero-specificity `:where()`, `:is()`/`:has()`, native nesting `& + &`,
  container queries, `color-mix`, `color-scheme: light dark` with per-component dark overrides.
- No preprocessor, no Tailwind, no build step.

## Ruby / Rails — the class-macro idiom

Same values, Ruby's native idiom. One surface difference is deliberate: **rubocop-rails-omakase is
the arbiter of Ruby tokens** (double quotes, 2-space, guard clauses, hash-value shorthand) — defer
to it, which is why Ruby quotes are double where the JS quotes are single.

1. **Roll everything into a class macro.** A feature is *declared*, not written: `component :Card
   do; flag :slim; option :title; component :Head, :Body end` — zero method bodies; the machinery
   is generated once in a base class (`option`/`flag`/`component` via `define_method` in an
   anonymous `include Module.new`, so generated methods stay overridable with `super`). Host
   boilerplate folds the same way. When you see the same accessor/callback/wiring pattern twice,
   that's the macro telling you it wants to exist. Procedural helper bags are the debt, not the
   model.
2. **Metaprogramming is a named vocabulary, then composed.** Small primitives (`define_class`, a
   `Resolver` constant-lookup concern, ancestry-based dispatch) composed into macros — never one
   clever `method_missing` doing everything; each metaprogramming tool is a leaf behind a macro.
3. **Endless methods for one expression** — `def tag = href? ? :a : super`, aligned in blocks.
   Pipelines are `.then` chains (`model.all.then { policy_scope _1 }.then { sorted _1 }`) — the
   Ruby `pipe`. Ruby 3 throughout: pattern matching for real dispatch (`case value; in Op(rhs:
   /…/)`), method-object predicates (`when method(:association?)`), `Data.define` value objects,
   anonymous forwarding `(*, **, &)` / `(...)`, numbered block params, guard clauses with
   `and`/`or` as flow words. Bang-methods mutate; non-bang is pure/clone (`def query(...) =
   clone.query!(...)`). A hand-written file tops out ~200 lines, one class each, dirs as
   namespaces.
4. **Concerns, presenters, builders — not fat models or service objects.** Logic lives in
   `ActiveSupport::Concern` modules, builder POROs (`*_builder.rb`), and a presenter hierarchy
   resolved by `klass.ancestors`. Controllers are thin (`def index = respond_with objects`); Haml
   views are pure component composition (`= page.Body do`) with near-zero raw markup.
5. **Examples over prose.** Inline `#=>` examples (stdlib style) and runnable example blocks parked
   at the end of a file — the Ruby analog of `///` doctests. Prose comments stay 1–3 lines of
   rationale — never a paragraph essay. ActiveSupport-maximalist: reach for
   `extract!`/`compact_blank`/`.then` before writing a loop.
6. **Adopt gems freely — the opposite of the zero-dep JS stance** — but each gem earns its place by
   deleting a subsystem (Pundit auth, Kaminari pagination, Responders, Turbo, Haml, Chronic). Small
   gaps get a `core_ext/` monkeypatch, never a utility gem. Propshaft + importmap, no bundler, no
   Node build. The values that carry to JS-in-Rails: Turbo + delegated
   `addEventListener`/`closest()` listeners, progressive enhancement (a decorated `<select>` still
   works plain), no framework layer until earned.
7. **Testing: Minitest, never RSpec.** Declarative `test "full sentence" do`, FactoryBot, assert
   queries against `.to_sql`, and explicit *negative* security assertions (a `;DROP` sort key must
   `refute_includes "ORDER BY"`). Rake default: `rubocop test brakeman`.

## What to deliberately omit (and document in place)

The clearest statement of the values, from a hand-rolled flux store's comments:

- **No middleware/thunks** — logic scatters out of reducers into closures; kills debuggability.
- **No keyed/combined reducers** — every reducer sees the full state and every action.
- **No action creators** — an abstraction that only renames things doesn't get built.
- **No memoized selector layer** — subscribers get the whole state.

The proof the style scales: a complete logic-programming language in ~700 lines where every
feature is a plain function over `env`, callable in isolation, each with its `///` doctest. Simple
parts → complex whole.
