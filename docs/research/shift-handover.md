# What a shift handover has to be, for the Self-Closing section

Research behind ADR-0054 and issue #332. The feature: the Self-Closing section
(SC) hands a shift from one Team Leader to the next, across Cutting, Shaping,
Raschel and Warping. Today that happens on paper and by voice; the Platform
records nothing about it, though it already holds the shift calendar, the assets,
the downtime events, the quality issues and the actions the handover is about.

This is a design input, not a literature review. It answers three questions:
what the evidence says a handover must contain and be, which of that belongs in
this Platform and which belongs in the plant's habits, and what the Platform
must refuse to do.

## 1. Three elements, and only one of them is a form

HSE's human-factors guidance on shift handover is short and has not been
improved on: effective handover is **preparation by the outgoing crew**, a
**two-way exchange**, and **cross-checking by the incoming crew as they assume
responsibility** ([HSE, Shift handover](https://www.hse.gov.uk/humanfactors/topics/shift-handover.htm)).
It should be face-to-face, two-way with joint responsibility, **using both
verbal and written communication**, based on an analysis of the incoming
staff's information needs, and given as much time as necessary.

Three consequences the design takes literally:

1. A written record is not optional, and it is not the handover either. The
   record is the object of the conversation, not a parallel artifact.
2. The incoming Team Leader's check is an **event with a time and a name** —
   that is what "Handover acknowledgement" is in `CONTEXT.md`, and why an
   acknowledgement can never be inferred from a submission.
3. The form cannot be a single narrative box. The evidence is unusually clear
   that structure, not effort, is what survives: across five handovers in a
   weekend, 2.5% of the information from the first survived to the last without
   a written record, 85.5% with notes, and **99% with a standardised proforma**
   ([RCP, Acute care toolkit 1](https://www.rcp.ac.uk/media/5q5hqwbx/acute-care-toolkit-1-handover.pdf),
   citing Bhabra et al.).

The strongest experiment we have on the *shape* of the written part was run at
an ENGEN refinery by the ASM Consortium: a checklist-integrated logbook was
compared with the site's general-heading logbook over two trials. Completeness
rose from **57.5% to 76.1%** of expected information items, which was
statistically significant (F(1,9)=6.80, p<0.02); incoming-operator recall and
mid-shift probe accuracy also improved but did not reach significance, and the
handover took slightly longer (324 s vs 280 s)
([ASM Consortium, *Effective Shift Handover*](https://process.honeywell.com/content/dam/process/en/documents/document-lists/doc_asm-consortium/white-papers/July%2031%202011%20-%20Effective%20Shift%20Handover.pdf)).
Read that honestly: structure reliably improves **what gets written**. The
effect on the incoming person's understanding is positive but not firmly
established, so the acknowledgement step stays — it is cheap and it is the only
part that tests understanding rather than recording.

Failure modes the same literature names, all of which the design has to answer:
verbal-by-default under time pressure; no agreed minimum content; a log that
records the state at the end of the shift and not the events during it
(Buncefield); handover attempted without the person who did the work
(Texas City); cause missing from the record; temporary fixes invisible; no
cross-check; and a signal buried in prose
([IChemE, *Pass it on! Revisiting shift handover after Buncefield*](https://www.icheme.org/media/9026/xxiii-paper-16.pdf)).

## 2. TPM: what the operator owns, and the two records tea leaves it

TPM contributes the content that a generic handover form misses, because it
assigns the operator a specific relationship to the machine.

**Autonomous Maintenance (Jishu Hozen)** moves routine care — cleaning,
inspection, lubrication — to the operator, in steps: initial cleaning,
eliminating sources of contamination, provisional CIL standards, general
inspection, autonomous inspection, area standardisation, and autonomous
management. The relevant consequence at a shift boundary is that the operator
owns the **basic condition** of their machine, the **detection and tagging** of
abnormalities (not universal repair), the **escalation decision**, and the
state of the area around the machine. So a handover that does not say whether
the routine care was done — and why not, when it was skipped — hides the one
thing the next shift cannot otherwise discover.

A skipped CIL is not a neutral omission: TPM classifies it as an *unfulfilled
basic condition*, one of seven abnormality types (minor flaws, unfulfilled basic
conditions, inaccessible places, sources of contamination, sources of quality
defects, unnecessary items, unsafe places). That list is the right value set for
the form's abnormality field, and note that two of the seven are already quality
and safety records elsewhere in this Platform.

**Change point (henkaten)** is the other half, and it is the one a free-text box
loses first. Toyota's change-point management monitors the four Ms — man,
machine, material, method — because after a change in any of them, safety,
quality, speed or cost can worsen. AllAboutLean's treatment is explicit that the
**shift change is itself a man change point**, which is the whole justification
for a change-point block on a handover
([AllAboutLean, Henkaten](https://www.allaboutlean.com/henkaten/)). Art of Lean
adds the design constraint: change-point management does not track every change,
only conditions altered by a countermeasure or kaizen and changes discovered at
the boundary — a board that records everything records nothing
([Art of Lean, Change Point Management](https://artoflean.com/reference/change-point-management)).

Change point and abnormality are not synonyms, and the form should not merge
them. A change point is an *expected* difference that triggers a watch; an
abnormality is an *observed* defect that triggers a fix. Miss the first and the
change silently becomes the new normal; miss the second and the defect grows
into a breakdown.

## 3. Lean: the handover is not the huddle, and the numbers are not the story

The daily-management literature is clear that three things happen at a shift
boundary and they are different artifacts:

| Artifact | When | Who | Purpose |
|---|---|---|---|
| Shift handover | last minutes of the shift, acknowledged at the start of the next | outgoing Team Leader → incoming Team Leader | transfer state, meaning and commitments |
| Tier-1 huddle | first 10–15 minutes, standing at the board | Team Leader leads, supervisor owns escalation | align the team on today's target and owners |
| Shift close | at the boundary | system | stop the numbers moving under the conversation |

The handover is the input; the huddle produces actions. The Platform already has
a home for the meeting (`tier_meetings`, tier 1) and for the shift calendar
(`shift_instances`), so the handover must not become a second meeting record.

OEE enters because the shift's numbers are what both people are talking about,
and because the platform already computes them per shift and asset
(`v_shift_oee`): availability as run minutes over planned production minutes,
performance as theoretical over run minutes, quality as first-pass yield. The
six big losses map onto the three components — breakdown and setup are
availability, minor stops and reduced speed are performance, defects and startup
yield are quality ([Vorne, OEE six big losses](https://www.oee.com/oee-six-big-losses/)).

What the handover must carry forward is narrower than "the OEE": the **top loss
of the shift** with its reason, the **open losses** (a machine still stopped at
the boundary), the **classification backlog** (how much of the OEE is built on
unclassified stops), and the **countermeasure status** of the actions the loss
produced. The commercial tools converge on the same three blocks — Status,
Events, Actions, plus an acknowledgement — from `MachineMetrics`' shift handover
in its MES, through `Shoplogix`' digital shift log and `Symestic`'s shift log,
to `Poka`'s changeover checklist and `Tulip`'s shift summary. `AVEVA`'s OSM adds
one block worth stealing: *experience transfers*, lessons that must outlive the
shift. `Oxmaint` is the clearest on maintenance content: temporary repairs,
bypassed interlocks and open work orders with ownership transferred **by name**.

None of them owns the loss tree the way this Platform's `downtime_events` does,
which is the argument for the handover being a *reader* of the plant's records
with a small amount of human text, not a re-entry surface.

## 4. What the Platform should therefore record

The record is six blocks, in the order the incoming Team Leader needs them.

**A. Identity, derived.** Section, shift instance, production day, window,
outgoing Team Leader, incoming Team Leader, and the time each acted. Nothing
typed.

**B. The frozen status snapshot.** The numbers as the form showed them: OEE and
A/P/Q, planned production minutes, run and unplanned-downtime minutes, the top
loss (reason and minutes), unclassified downtime (minutes and count), good /
reject / rework and the planned-versus-good gap, open quality issues with their
containment, and the shift's safety events. Machine-derived, Team Leader
confirmed, stored once (ADR-0054).

**C. Machine status lines.** One per active Asset in the Section: state, the
reason when the state is not normal running, the record that explains it (open
downtime event, quality issue, work order), and what the incoming shift must
watch. The completeness rule is the point: a machine nobody mentioned cannot
exist.

**D. Change points.** One row per 4M dimension that changed: man (who is
different, and whether they are qualified on that machine), machine (changeover,
tool or needle set, repair, modification), material (lot, supplier, beam, shade,
remaining WIP), method (speed, setting, specification). Each carries what to
watch and whether the watch ran.

**E. Actions carried.** The Section's open `action_items`, each dispositioned —
carried, reassigned, or closed with the evidence that closed it — with its
owner, due date, PDCA phase and age in shifts. Linked, never copied.

**F. Handover evidence.** Whether the joint walk happened and which assets it
covered, which items were discussed face-to-face as critical, and any deviation
(late, partial, no incoming Team Leader) with its reason. This is how the
process is audited later without asking anybody to remember.

Three things are deliberately **not** in the record: a second downtime log (a
loss is explained in the record but recorded as a `downtime_events` row), a
second action list (Actions owns actions), and free narrative outside the fields
where the human *why* belongs.

## 5. Rules the record enforces

Drawn from the handover literature and the platform's own house rules, in the
order the server enforces them:

1. One handover per Section per shift instance; the pair is unique.
2. Nobody acknowledges their own handover.
3. Submit requires every active Asset in the Section to have a status line.
4. A line not in normal running carries a reason and a reference to the record
   that explains it.
5. A change point carries what to watch, and the watch's result is recorded at
   acknowledgement.
6. Every carried action is dispositioned by the new handover.
7. A submitted handover is immutable; a correction is an amendment that names
   the version it replaces.
8. An unacknowledged handover never resolves itself: it stays visible as an
   exception.
9. Timing is the plant's calendar (`shift_instances`), never the server clock;
   "late" is a derived flag with a stated threshold.

Rules 1–4 and 7 are enforced in the database and the route; 5–6 and 8–9 are
enforced in the route and shown on the board.

## 6. What the plant still has to tell us

- **Shift overlap.** Are handover minutes paid time on both sides, or does the
  incoming Team Leader arrive as the outgoing one leaves? It decides whether
  "late" starts at the boundary or 30 minutes after it.
- **Who acknowledges when the incoming Team Leader is absent** — the acting Team
  Leader, the supervisor, or nobody, in which case the record stays
  unacknowledged.
- **The section's equipment list**, so the tree and its assets can be seeded
  (Cutting, Shaping, Raschel, Warping each carry which machines?).
- **Whether a supervisor co-signature exists** on the current paper form; the
  schema carries the columns, the act can wait for its own ticket.
- **The plant's abnormality vocabulary** — whether the TPM seven types are used
  as they are, or the plant has its own list.

## 7. Sources

Primary guidance:

- HSE, *Shift handover* — https://www.hse.gov.uk/humanfactors/topics/shift-handover.htm
- HSE / The Keil Centre, *Improving communication at shift handover* (2006) —
  https://www.hse.gov.uk/humanfactors/assets/docs/shifthandover.pdf
- Lardner, *Safe communication at shift handover: setting and implementing
  standards* — https://www.hse.gov.uk/humanfactors/assets/docs/standards.pdf
- HSE HSG250, *Guidance on permit-to-work systems* —
  https://www.hse.gov.uk/pubns/priced/hsg250.pdf (permits crossing a shift need
  a handover and the incoming signature)
- IChemE, *Pass it on! Revisiting shift handover after Buncefield* —
  https://www.icheme.org/media/9026/xxiii-paper-16.pdf
- ASM Consortium, *Effective Shift Handover* (ENGEN trials) —
  https://process.honeywell.com/content/dam/process/en/documents/document-lists/doc_asm-consortium/white-papers/July%2031%202011%20-%20Effective%20Shift%20Handover.pdf
- Royal College of Physicians, *Acute care toolkit 1: Handover* —
  https://www.rcp.ac.uk/media/5q5hqwbx/acute-care-toolkit-1-handover.pdf
- CCPS, *Guidelines for Risk Based Process Safety*, ch. 17 Conduct of
  Operations — https://www.aiche.org/ccps/introduction-conduct-operations

TPM and Lean:

- AllAboutLean, *Henkaten* — https://www.allaboutlean.com/henkaten/
- Art of Lean, *Change Point Management* —
  https://artoflean.com/reference/change-point-management
- Seven abnormality types —
  https://www.nikunjbhoraniya.com/2021/04/7-types-of-abnormalities.html
- Jishu Hozen steps —
  https://www.nikunjbhoraniya.com/2021/09/7-steps-of-jishu-hozen.html
- Vorne, *OEE and the six big losses* — https://www.oee.com/oee-six-big-losses/
- LEI, *How we improved our tiered daily huddles* —
  https://lean.org/the-lean-post/articles/how-we-improved-our-tiered-daily-huddles/
- Kaufman Global, *Shift start-up meeting* —
  https://kaufmanglobal.com/glossary/shift-start-up-meeting

Commercial tools, for the field checklist:

- MachineMetrics, shift handover — https://docs.machinemetrics.com/docs/product-guides/mes/shift-handover
- Shoplogix, digital shift handover logs —
  https://shoplogix.com/blog/digital-shift-handover-logs/
- Symestic, digital shift log — https://www.symestic.com/en-us/what-is/digital-shift-log
- Oxmaint, maintenance shift handover —
  https://oxmaint.com/industries/manufacturing-plant/maintenance-shift-handover-best-practices-prevent-information-loss
- Tulip, shift starter meeting — https://support.tulip.co/docs/shift-starter-meeting
- AVEVA OSM, shift handover module — https://docs.aveva.com/bundle/osm-web/page/631096.html
- Poka, shift handovers — https://www.poka.io/en/blog/making-the-most-of-shift-handovers-in-manufacturing/
