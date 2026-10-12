---
name: trail-review
description: Review a group hike proposal against safety and environment rules and return a structured verdict with evidence. Use when asked to review, assess, or approve a trail plan or hike proposal.
metadata:
  author: foundry-agents-options
  version: "0.1"
---

# Trail review

Review a group hike proposal and decide whether it can be approved.
The rules in this skill are illustrative demo rules for a fictional club.
They are not real safety guidance.

## Steps

1. Read the proposal in the user message.
2. Read `references/safety.md` and assess every rule in it.
3. Read `references/environment.md` and assess every rule in it.
4. Write the review result in the output format below.

## Assessment rules

- Assess each rule once. Copy the rule ID exactly from the reference file
  (S1-S3 for safety, E1-E3 for environment).
- Verdict per rule is one of `pass`, `concern`, or `fail`.
- Quote evidence verbatim from the proposal. If the proposal says nothing
  about a rule, write `No evidence in proposal` and use `concern`.
- Never invent facts that are not in the proposal.
- Overall verdict is `Reject` if any rule fails, `Approve with conditions`
  if any rule has a concern, and `Approve` otherwise.

## Output format

```markdown
## Review result

| Rule | Domain | Verdict | Finding | Evidence |
|---|---|---|---|---|
| S1 | Safety | fail | ... | "..." |

**Overall verdict:** Reject

**Conditions to fix:**
1. ...
```
