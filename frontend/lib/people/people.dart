/// The People Module's client entry point (ADR-0012's client mirror of
/// ADR-0006), the counterpart of `backend/src/modules/people/index.js`.
///
/// A client Module exposes its Blocs and models here, never its widgets — so
/// Maintenance's Asset form drives `OrgUnitPickerBloc` and renders its own
/// single-select view of the tree, rather than importing `OrgUnitPicker`,
/// which is a Grant editor and belongs to People's Approval flow.
///
/// `lib/platform/` is not a cross-Module consumer and does not go through
/// here: it is the mounting layer, the same special case `src/index.js` is
/// for `router` on the server. `lib/people_api.dart` sits at `lib/` root and
/// is likewise outside this seam today.
library;

export 'assignee_candidate.dart' show AssigneeCandidate, HeldSkill;
export 'org_unit.dart' show OrgUnitNode, Site;
export 'org_unit_picker_bloc.dart'
    show
        OrgUnitPickerBloc,
        OrgUnitPickerState,
        OrgUnitPickerStarted,
        OrgUnitPickerSiteSelected,
        OrgUnitPickerExpanded,
        OrgUnitPickerCollapsed,
        OrgUnitRow,
        SitesStatus;
