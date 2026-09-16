---
status: accepted
---

# Quality authority is held on a Grant, not on a role

Date: 2026-09-16

The Quality Module has decisions only some people may take: granting a
Concession, reopening a Non-conformance, opening a CAPA, and verifying one held.
Today a Grant carries one level flag, `can_write`, and `app_users.role` offers
`engineer` — but no check anywhere reads a role other than `admin`.

## The decision

A Grant carries a separate Quality authority flag alongside its level. The
decisions above require it on the Org Unit in question, reached downward like any
Grant (`canAct`). Quality authority does not imply write, and write does not imply
Quality authority; an administrator holds it everywhere, as with every other
check. Recording a Non-conformance, and scrap or rework Dispositions, need no
authority.

## Considered options

- **The `engineer` role plus a write Grant.** Rejected: a role is plant-wide, so
  an engineer on Line 2 could accept bad product on Line 5, and `engineer` would
  come to mean "quality engineer" for maintenance engineers too.
- **A new `quality_engineer` role.** Rejected for the same plant-wide reach, and
  because an Account holds one role, so a maintenance supervisor who also signs
  off Concessions for their own line could not be both.
- **Any write Grant.** Rejected: whoever may record work on a line would also
  accept its bad product, which is the separation ISO 9001 audits look for.
