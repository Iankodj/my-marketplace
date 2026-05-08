# context7 — library discovery

Use this reference when the plan needs to identify *which* library to depend on, disambiguate a casual name, or pin a specific version.

## When to call

- Multiple candidate libraries solve the same problem (e.g., "an HTTP client for Node" → axios, undici, got, node-fetch).
- The user names a library casually ("React Query", "Next") and you need the canonical `/org/project` ID before any docs lookup will work.
- The codebase already pins a version that may differ from the agent's training-data assumptions, and you need to confirm what's actually installed.

## How to call

Call `resolve-library-id` with:

- `libraryName`: the user's name, properly capitalized — `Next.js` not `nextjs`, `Customer.io` not `customerio`, `Three.js` not `threejs`.
- `query`: a short description of what the plan needs from this library (used for ranking).

The response is a list of candidates with metadata. Pick by ranking on:

1. **Name match** — exact > partial.
2. **Source Reputation** — High > Medium > Low > Unknown.
3. **Benchmark Score** — closer to 100 is better-curated docs.
4. **Code Snippet count** — more snippets = better doc coverage for follow-up `query-docs` calls.

Cite the chosen libraryId in the plan's `verified_against` frontmatter.

## Version pinning

If the codebase pins a major version (or the library moves fast — Next.js, React, Tailwind, Prisma), use the pinned form: `/org/project/<version>`, e.g. `/vercel/next.js/v15.0.0`. Floating IDs (`/org/project`) get whatever the latest docs say; pinned IDs are stable.

When the codebase doesn't pin and the library is stable enough (lodash, express), the unpinned ID is fine.

## Examples

| User said | Call | Likely chosen ID |
|---|---|---|
| "use Prisma" | `resolve-library-id("Prisma", "ORM for PostgreSQL")` | `/prisma/prisma` |
| "Next 15 app router" | `resolve-library-id("Next.js", "App Router server components")` | `/vercel/next.js/v15.0.0` |
| "I'm using React Query" | `resolve-library-id("TanStack Query", "data fetching React")` | `/tanstack/query` |

## Anti-patterns

- Calling `resolve-library-id` when the plan already has a verified libraryId from earlier in the conversation. Reuse it.
- Picking the candidate with the highest snippet count without checking reputation. A high-snippet, Low-reputation source is often a fork or scraper.
- Skipping the version pin for a fast-moving library "to keep things simple." That's how the build phase ends up calling `useEffect` with React 19 semantics on a React 18 codebase.
