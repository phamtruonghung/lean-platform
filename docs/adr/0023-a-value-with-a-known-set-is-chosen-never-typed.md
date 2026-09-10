---
status: accepted
---

# A value with a known set is chosen, never typed

Date: 2026-09-11

Three input controls in this client ask a person to type a value that the
system already knows the full set of, and then tell them afterwards whether
they guessed right.

**Dates.** Four fields — the Assignment effective date
(`employee_assignment_dialog.dart`), the departure date
(`employee_departure_dialog.dart`), and a skill's assessed-on and expires-on
dates (`employee_skill_form_dialog.dart`) — are raw `TextField`s. Each
independently hand-rolls the same `"YYYY-MM-DD"` helper string; there is no
`showDatePicker` call anywhere under `frontend/lib/`, and no shared date
widget. Nothing validates the format in the client, so `DATE_RE` in
`modules/people/directory.js` catches a typo only after a round trip, as a
refusal.

**The timezone.** `site_form_dialog.dart` takes a Site's timezone as free
text with the helper `"An IANA zone, e.g. Europe/London"`. Its only
validation is the `sites_validate_timezone()` trigger, which checks the value
against `pg_timezone_names`. A typo therefore surfaces as a trigger error at
submit — and a value that is *valid but wrong* is accepted in silence, which
moves that Site's production-day boundary (ADR-0017, `plant_date`,
`fill_shift_instance`). Nobody notices until a stoppage is counted against
the wrong day.

**Search.** All three search boxes — the Directory, the Org Units admin
screen, the Employee link picker — are submit-triggered: type a term, press
Enter or a Search button, and only then learn whether anything matches. A
person who half-remembers a name has to guess, submit, read an empty result,
and guess again.

The common shape is that the client holds the user to a format or a spelling
that the system could simply have offered them.

## The decision

A value whose acceptable set is known is chosen from that set, never typed.

**1. A field backed by a Postgres `DATE` renders a date picker.** The text
field is read-only; tapping it anywhere opens the picker. Granularity follows
the column: every temporal input in the product today maps to a `DATE`, so
every one of them is date-only. If a genuine `TIMESTAMPTZ` ever becomes
user-entered, it gets a date *and* time flow — the rule is "the picker
matches the field's granularity", not "every date carries a clock". Forcing a
time onto a calendar fact invents precision that is not there.

**2. Optional date fields keep an explicit clear affordance** — a trailing ✕,
shown once a value is set. Blank carries meaning in three of the four call
sites: the server records today, or re-derives the value from the skill's
revalidation period. A picker-only field must therefore be able to get back
to genuine empty, not to a defaulted date.

**3. Dates display as `YYYY-MM-DD`** — the same format the wire uses, so a
single label costs no `intl` dependency.

**4. A timezone is chosen from the list Postgres itself validates against.**
A backend endpoint reads `pg_timezone_names`, excluding the `posix/` and
`right/` prefixes, and the client filters it in memory. Any other source —
a bundled IANA table, a curated shortlist — is a second source of truth that
can offer a value the trigger will refuse. A stored value absent from that
list is still displayed rather than blanked: a Site created earlier may hold
a legacy alias, and showing an empty control invites a careless save that
changes the plant's production day.

**5. Search boxes suggest records, as the user types** — debounced ~300ms,
minimum two characters, at most ten results. They suggest *records*, not
query completions: on a directory screen a person is looking for a person,
not for a better search string. Picking a suggestion completes that box's own
job, and the three boxes do different jobs — the Directory navigates to the
Employee, the Employee link picker selects them into the form it sits inside,
the Org Units search reveals and selects the unit in its tree. The shared
widget therefore reports a selection to its caller and holds no routing
knowledge at all.

**6. When the list behind a control cannot be fetched**, the control shows
`FailureState` with a retry and blocks submission. It never falls back to
free text. The fallback would reinstate exactly the input being removed, and
would do so at the moment the system is least healthy — accepting an
unvalidated value that the backend is about to reject anyway.

## Why not the alternatives

**Letting the date fields also accept typed input.** A keyboard user entering
`1974-03-02` is faster than any calendar, and a birth year reached by tapping
back through months is genuinely tedious. This was rejected because a field
that parses text has to defend every malformed string — which is the class of
bug being deleted — and because "must show a picker" is only enforceable as a
test when the field is read-only. If far-past dates become a real complaint,
the answer is a picker that accepts a year directly, not a text field.

**Bundling the IANA zone list in the client.** Cheaper, works offline, no new
endpoint. Rejected because `sites_validate_timezone()` is the authority and a
bundled list drifts from it silently: the client offers `America/Godthab`,
Postgres has renamed it, and the user gets a trigger error for picking
something the app suggested.

**Query completions instead of record hits.** Typing `wel` offering the term
"welder" keeps the box a filter and is simpler to build. Rejected because it
adds a step in the middle of what the person is actually doing, which is
finding a record.

## What this costs

**Suggestions run against an unindexed scan.** `listEmployees` matches with
`display_name ILIKE '%…%'` — a leading wildcard no B-tree can serve — and
`pg_trgm` is not installed. Moving from one query per search to one per
debounced keystroke multiplies that load. It is accepted at plant scale: a
bounded result over a few thousand rows is comfortably fast, and installing a
GIN index for a table that size is ceremony. **Revisit — install `pg_trgm`
and index `display_name` — when the Employee table passes ~100k rows, or when
suggestion latency exceeds ~200ms at p95.** The bound itself is not optional:
`listEmployees` gains a `limit`, because bounding in the client would still
transfer the whole match set.

**Two shared widgets to keep honest.** `frontend/lib/widgets/`
`app_date_field.dart` and `app_search_field.dart`, joining the existing
shared presentational widgets. They live there rather than in
`frontend/lib/platform/` because they are things Screens *use*, not things
the app is *built on*. The timezone control is the search widget's third
consumer, which is what stops it from acquiring Employee-shaped assumptions.

**Enforcement is per-screen widget tests, not a source scan.** The one
automatically enforced UI convention in this repo today is
`theme_skeleton_test.dart`'s walk of every file under `lib/` failing on a
`Color` literal. That pattern was deliberately not reused here: a grep for
date-shaped `TextField`s is easy to fool and annoying to maintain, whereas a
test that taps the field and asserts a picker appears tests the behaviour
that actually matters. The cost is that the rule is only as complete as the
tests written for it, so a new date field added without a test can violate it
silently. The `AGENTS.md` pointer exists to make that a review question.

## Out of scope, deliberately

**Adding search to Assets and Work Orders.** Neither has a search box, and
neither backend endpoint accepts a search term. Whether a technician should
be able to search Work Orders is a product decision, and it does not belong
inside a UI-consistency change.

**An account-level timezone preference.** `app_users` has no timezone column
and needs none. Every timezone-aware interpretation in this Platform happens
inside Postgres — `plant_date`, `shift_instance_at`, `fill_shift_instance` —
against the *Site's* zone, because a production day belongs to the plant, not
to the person reading the screen (ADR-0017, CONTEXT.md's **Production day**).
