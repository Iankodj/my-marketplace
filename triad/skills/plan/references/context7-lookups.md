# context7 — documentation lookups

Use this reference when the plan needs to read from a *known* library — exact API signatures, version differences for a migration, or architectural recipes. Three calling patterns share the same tool (`query-docs`); the right one depends on what the plan needs.

If you don't have a libraryId yet, see `context7-discovery.md` first.

## When to call

- You need a function signature, parameter, or return type the codebase doesn't already use.
- You need to compare versions for a migration or upgrade.
- You need a recommended approach (auth flow, schema design, error handling) the codebase has no precedent for.

## Pattern 1 — API reference

Single narrow `query-docs` call. One concept per query.

### Good vs. bad queries

| Bad | Good |
|---|---|
| `auth` | `JWT authentication with Express middleware` |
| `useEffect` | `useEffect cleanup function patterns for subscriptions` |
| `prisma client` | `Prisma findUnique with select clause for nested relations` |
| `routing` | `Next.js App Router catch-all dynamic segments and generateStaticParams` |

Narrow queries return tight snippets you can cite. Vague queries return overviews that don't help.

If the plan needs three different APIs from the same library, make three narrow `query-docs` calls. Three small > one giant.

## Pattern 2 — Version differences (migration)

Paired calls — one per version, same query both times.

```
query-docs(libraryId: "/org/project/<old-version>", query: "<X>")
query-docs(libraryId: "/org/project/<new-version>", query: "<X>")
```

Diff the snippets. Surface differences in the plan as **explicit breaking-change callouts**, not buried in step text:

```markdown
## Breaking changes between <oldVersion> and <newVersion>

- **<API or behavior>**: was <X>, now <Y>. Affects: <which files>.
```

### Common migration shapes

| Shape | Example |
|---|---|
| API rename | React class lifecycle → hooks; Vue 2 `data` → Vue 3 `setup()` |
| Default behavior change | Next.js Pages → App Router; React 18 strict-mode double-invocation |
| Deprecation with replacement | Express `body-parser` → built-in `express.json()` |
| Module restructure | Prisma client paths; Tailwind v4 `@layer` semantics |
| New required argument | OpenAI SDK v4 client constructor |

## Pattern 3 — Architectural patterns

Pattern-shaped query, not API-shaped.

### Less useful → more useful

| Less useful | More useful |
|---|---|
| `App Router` | `Recommended pattern for protected routes and server-side auth in Next.js App Router` |
| `Prisma relations` | `Schema design for many-to-many with metadata in Prisma` |
| `error handling` | `Error boundary placement strategies in React server components vs client components` |
| `state management` | `When to choose Zustand over Context for shared state in a Next.js App Router project` |

### When the docs return three approaches

Don't pretend they're decisive. Surface the options in the plan:

```markdown
## Approach
The docs describe three patterns:
- A: <one-line summary>
- B: <one-line summary>
- C: <one-line summary>

Going with **B** because: <reason from the codebase or constraints>.
```

That's a much better plan artefact than "we'll use B" with no provenance.

## Shared concerns

### Token budget

Default response is ~5000 tokens. Don't query for "everything about library X." Always narrow.

### Pinning versions

Pin via `/org/project/<version>` whenever the library moves fast (Next.js, React, Tailwind, Prisma). Floating IDs return latest; pinned IDs are stable.

### Citing results

When you cite a snippet in the plan, list the libraryId in `verified_against`. The build phase trusts those over its training data.

## Anti-patterns

- One giant query asking for "the API surface of library X." Always narrow.
- Querying without pinning the version on a fast-moving library.
- Treating major-version bumps as patch bumps — there's almost always a breaking change worth surfacing.
- Treating any single recipe as "the" answer — frameworks evolve; recipes are starting points, not commandments.
- Pattern-querying for things that depend on user-specific constraints (team size, infra, latency budget). Ask the user instead.
- Citing a `query-docs` result without recording the libraryId in `verified_against`.
