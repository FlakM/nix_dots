# Review Workflow - VALIDATE and PRESENT

## VALIDATE phase

Mandatory, runs after FIND and before PRESENT. It MUST emit the verdict table before any user-facing report. Re-reading each flagged file is the whole point of this phase - "don't re-read" token rules do not apply.

**Default bias: drop, not keep.** Reviews should only cost dev time on things that cost real time to ignore.

For EACH candidate:

1. **Project conventions** - does `CLAUDE.md`/`AGENTS.md`/clippy config make it acceptable?
2. **Double-check the code**
   - Read the file at the line; confirm the code says what the finding claims.
   - Trace one hop out for "missing / dropped / unused / duplicated / unguarded" claims: callers, trait impls, `From` impls, middleware/interceptors, the service layer above, DB constraints, the proto definition. If the neighbouring code handles it, DROP entirely - do not keep as a hedged LOW.
   - Grep siblings; if it's the established convention, drop silently.
   - Change claims (added/removed/renamed/downgraded) must appear in `git diff {baseSha}...HEAD -- <file>` (or the bundle). Not there → hallucination → DROP.
   - Cross-file premises: diff the other file too. If its diff doesn't show it → DROP.
   - Can't verify in 1-2 tool calls → DROP.
3. **Concreteness gate** - "What's the observable consequence today, given the current code?"
   - "Future maintainers might..." is not a consequence.
   - "If a caller passes a bad value..." needs a real caller in the codebase that does.
   - Drop: theoretical races with no interleaving in current code, micro-perf off the hot path, `clone()` on small/cold values, visibility/naming nits, "consider extracting", pre-existing patterns, test style nits.
   - Keep: bugs on a current code path, behavioral asymmetries with divergent runtime outcomes, authz/tenant leaks with a named path, locks across await with a real contention path, wire/schema incompatibility, missing tests for new public behavior, documented-convention violations.
   - Refactor/migration PRs: filter extra aggressively - only parity failures matter.
4. **Deduplicate** across specialists.
5. **Classify**: KEEP (concrete, verified) / NEEDS-INPUT (genuine contract ambiguity only the author can resolve - not "unsure if intentional") / DROP.

### Verdict table (mandatory)

```markdown
| # | Finding | file:line | Read | Hop-out | In diff | Verdict | Reason |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Missing team check | api.rs:42 | ✓ | interceptor enforces it | ✓ | DROP | discharged: auth.rs:88 checks team |
| 2 | Mutex guard across await | cache.rs:88 | ✓ | n/a | ✓ | KEEP | concurrent refresh deadlocks |
```

- **Read** - opened the file and confirmed (✓ or note mismatch)
- **Hop-out** - result of checking neighbouring code; `n/a` if purely local
- **In diff** - ✓ once confirmed in the diff; name the other file for cross-file premises (`✓ via auth.rs`); `n/a` if not a change claim
- **Verdict** - KEEP / DROP / NEEDS-INPUT
- **Reason** - one line

Then a line containing exactly `===VERDICT_TABLE_END===`, then surviving KEEP/NEEDS-INPUT findings as JSONL (no SUMMARY line).

## PRESENT phase (main Claude only)

Show only KEEP and NEEDS-INPUT. Investigate before writing - read the code and deepen the explanation; don't just reformat the JSONL.

### Writing style

- Senior colleague to teammate. Depth over brevity, but no filler.
- Lead with the defect, then mechanism, then fix. Active voice. Concrete (name the fn, type, value).
- No em-dashes to join thoughts. No templated phrases ("It's worth noting...").

### Shell format

~~~markdown
▶ 🔴 CRITICAL ISSUES (count)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

#1 Issue title - `path/to/file.rs:42`

**Why this matters:** mechanism, chain of events, evidence.

**Suggestion:**
```rust
// fix
```
Why the fix works; alternatives with tradeoffs.

─────────────────────────────────────────────────────────

▶ 🟡 MEDIUM ISSUES (count)
...
▶ 🟢 LOW ISSUES (count)
~~~

- Number sequentially across sections; omit empty sections.
- `"i":true` findings get `[OUTSIDE CHANGE]` after the number.
- NEEDS-INPUT: add `**Note:** depends on <specific uncertainty>. Flagging for your review.`

### Filtered out

Render the DROP rows compactly:

```markdown
## Filtered Out (X issues)

| # | Finding | Location | Reason Filtered |
| --- | --- | --- | --- |
```

## Preventing hallucinations

Every cited value, name, line, and "before" snippet must be copied from a file you read. If you can't verify a claim, leave it out.
