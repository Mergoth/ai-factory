# <Feature name>

Slug: `<slug>`
Written: <YYYY-MM-DD>
Brief: `factory/briefs/<slug>.md`   <!-- delete this line if there is no brief -->

## Problem

What is wrong or missing today. Two or three sentences. The full reasoning lives
in the brief - do not restate it here.

## Solution

What we build. Plain language, no code.

## Scope

In:
- thing we do

Out:
- thing we deliberately do not do

## Assumptions

- decision made where the request was ambiguous, and why

## Notes

Anything the build agent should know about this repo that is not obvious from
the files - conventions, gotchas, a pattern to follow.

Standing gotchas worth repeating when they apply:

- Python: `pytest` exits 5 on an empty collection. On a greenfield round 1 that
  is a normal empty suite, not a failed run.
