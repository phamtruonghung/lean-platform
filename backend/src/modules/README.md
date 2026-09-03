# Modules

A **Module** is a functional area of the Platform that records real work and
produces the measurements KPIs are calculated from: People, then Maintenance,
then the Tier Board.

Modules are **code seams, not data seams** (ADR-0006). They share one schema and
one process. A Module owns its routes and its services, and never reaches into
another Module's internals — it calls that Module's service through the entry
point at `<module>/index.js`. Cross-Module reads are ordinary joins, because the
schema is one connected graph and turning its foreign keys into function calls
would rebuild the boundary ADR-0001 removed.

`npm run lint` enforces this. Shared code that Modules stand on lives in
`src/platform` and is not a Module; the foundation must not depend on what is
built on it.

`people/` is the first Module. See ADR-0006's "What a Module's entry point may
expose" section (added for issue #59) for the rule governing what an entry
point may export once a second Module — Maintenance — exists to call it.
