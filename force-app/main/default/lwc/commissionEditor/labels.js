// The custom labels of this bundle, in one object. Generated from the label list of the editor: add a label there, not here.
const BACK = 'Back';
const LOADING = 'Loading…';
const RETRY = 'Try again';
const ERROR = 'Something went wrong. Please try again.';
const NO_ACCESS = 'You do not have access to Commission Setup. Ask your Salesforce administrator.';
const NONE = '—';
const VERSION = 'Version {0}';
const PERCENT_SUFFIX = '%';
const NEW_CONFIGURATION = 'New configuration';
const STATE_DRAFT = 'Draft';
const STATE_RETURNED = 'Returned by CCO';
const STATE_PENDING = 'With CCO';
const STATE_UPCOMING = 'Upcoming';
const STATE_ACTIVE = 'Active';
const STATE_EXPIRED = 'Expired';
const STATE_REPLACED = 'Replaced';
const CHANGE_CORRECTION = 'Correct this version';
const CHANGE_FROM_DATE = 'Change terms from a date';
const CHANGE_NEXT_PERIOD = 'Next period';
const CHANGE_END_EARLY = 'End early';
const CHANGE_COPY = 'Copy to another project';
const INITIAL = 'Initial';
const MID_NUMBERED = 'Mid {0}';
const FINAL = 'Final';
const BACK_OVERVIEW = '‹ Overview';
const JOINED = '{0} · {1}';
const NOT_SAVED_YET = 'Not saved yet';
const UNSAVED_CHANGES = 'Unsaved changes';
const SAVED_AT = 'Saved {0}';
const SAVING = 'Saving…';
const RETURNED_BANNER = 'Returned by CCO on {0}: {1}';
const RETURNED_BANNER_NO_COMMENT = 'Returned by CCO on {0}.';
const READ_ONLY_PENDING = 'This configuration is waiting for approval. Withdraw it to make changes.';
const READ_ONLY_APPROVED = 'An approved configuration cannot be changed. Use New draft from this.';
const READ_ONLY_OTHER = 'You can view this configuration but you cannot change it.';
const END_EARLY_NOTE = 'Ending a period early changes only the end date. The other sections are shown for reference.';
const LOAD_ERROR = 'The configuration could not be loaded.';
const NOTHING_TO_SHOW = 'There is no configuration to show.';
const CHECKLIST = 'Checklist';
const CHECKLIST_OPEN = '{0} open';
const CHECKLIST_DONE = 'done';
const CHECKLIST_NOT_PAID = 'not paid';
const CHECKLIST_ITEMS_LEFT = '{0} items left before you can submit.';
const CHECKLIST_ITEM_LEFT = '1 item left before you can submit.';
const CHECKLIST_READY = 'Everything is filled in. You can submit.';
const CHECKLIST_GO_TO = 'Go to {0}';
const SECTION_PERIOD = 'Project and period';
const SECTION_STAGES = 'Payout stages';
const SECTION_RATES = 'Rates and targets';
const SECTION_OWN = '{0} payout';
const SECTION_OPTIONS = 'Options';
const STAGES_HINT = 'Internal team · {0}% allocated · {1}% left';
const STAGES_HINT_OVER = 'Internal team · {0}% allocated · {1}% over';
const STAGE_LEFT = '{0}% left';
const PROJECT = 'Project';
const CHOOSE_PROJECT = 'Choose a project';
const START_DATE = 'Start date';
const END_DATE = 'End date';
const NO_OVERLAP = 'No overlap with another configuration of this project';
const OVERLAP = 'The period overlaps {0} version {1} ({2}).';
const OVERLAP_ON_SAVE = 'The overlap with other configurations of the project is checked when you save.';
const NEED_PROJECT = 'Choose the project.';
const NEED_START = 'Enter the start date.';
const NEED_END = 'Enter the end date.';
const END_BEFORE_START = 'The end date must be on or after the start date.';
const START_INSIDE_SOURCE = 'The start date must be after {0} and not after {1}, the period of the version being changed.';
const START_AFTER_SOURCE = 'The start date must be after {0}, the end of the previous period.';
const END_NOT_AFTER_SOURCE = 'The end date cannot be after {0}, the end of the period today.';
const NEED_INITIAL = 'Add the Initial payout.';
const NEED_FINAL = 'Add the Final payout.';
const NEED_EVENT = 'Choose when the {0} payout is paid.';
const NEED_PARAMETER_PERCENT = 'Enter the % of the price that must be paid for the {0} payout.';
const NEED_PARAMETER_TRANCHE = 'Enter the tranche number for the {0} payout.';
const NEED_PARAMETER_INSTALLMENT = 'Choose the instalment for the {0} payout.';
const NEED_PERCENT = 'Enter a percentage';
const NEED_PERCENT_LEFT = 'Enter a percentage: {0}% is left';
const PERCENT_RANGE = 'A percentage must be above 0 and at most 100.';
const TRANCHE_RANGE = 'A tranche number must be 1 or more.';
const EVENT_NOT_ALLOWED = 'This payout event cannot be used for the {0} payout.';
const TOTAL_LEFT = '{0}% is still to be allocated: the payouts must total 100%.';
const TOTAL_OVER = 'The payouts total {0}%: {1}% more than 100%.';
const MID_ORDER = '{0} must come later than {1}: enter a higher value.';
const DUPLICATE_STAGE = 'Only one {0} payout is allowed.';
const MID_NOT_ALLOWED = 'A mid payout is not possible here: only Initial and Final.';
const SHORT_STAGE_PERCENT = '{0} payout %';
const SHORT_STAGE_EVENT = '{0} paid when';
const TARGET_BASIS = 'Target counted in';
const TARGET_PERIOD = 'Target period';
const EXCEED_MODE = 'Exceed rate applies to';
const CHOOSE = 'Choose…';
const COL_PAY = 'Pay';
const COL_DESIGNATION = 'Designation';
const COL_TARGET = 'Target';
const COL_CURRENT = 'Current %';
const COL_EXCEED = 'Exceed %';
const COL_CLAIM = 'Claim opens';
const TEAM_TOTAL = 'team total';
const NOT_PAID = 'Not paid on this project';
const PAY_DESIGNATION = 'Pay {0}';
const FIELD_OF = '{0}: {1}';
const NO_DESIGNATIONS = 'No designation is set up for the internal team.';
const NEED_ANY_RATE = 'Switch on at least one designation to pay.';
const NEED_RATE = 'Enter the current rate for {0}.';
const NEED_EXCEED = 'Enter the exceed rate for {0}.';
const NEED_TARGET = 'Enter a target above 0 for {0}.';
const RATE_RANGE = 'A rate must be between 0 and 100.';
const TARGET_RANGE = 'A target cannot be below 0.';
const EXCEED_LOWER = 'The exceed rate of {0} cannot be below its current rate.';
const NEED_BASIS = 'Choose what the target is counted in.';
const NEED_TARGET_PERIOD = 'Choose the target period.';
const NEED_EXCEED_MODE = 'Choose which sales the exceed rate applies to.';
const RATE = 'Rate';
const CONTRACT_REFERENCE = 'Contract reference';
const WHEN_TO_RELEASE = 'When to release';
const RELEASE_ALL_INITIAL = 'All at the Initial event';
const RELEASE_SPLIT = 'Split between Initial and Final';
const CONTRACT_HAS_TARGET = 'Contract has a target';
const EXCEED_RATE = 'Exceed rate';
const NEED_RELEASE_MODE = 'Choose when {0} is released.';
const FEE_AMOUNT = '{0} ({1})';
const NEED_AMOUNT = 'Enter an amount above 0 for {0}.';
const AMOUNT_RANGE = 'An amount cannot be below 0.';
const PRICE_EXCLUDES_TAX = 'Commission on price excluding taxes';
const CHANGE_REASON = 'Reason for change';
const CHANGE_REASON_PLACEHOLDER = 'Needed when an approved configuration is changed';
const NEED_REASON = 'Enter the reason for this change.';
const CARRY_OVER = 'Carry over personal targets';
const DISCARD = 'Discard draft';
const SAVE_DRAFT = 'Save draft';
const SUBMIT = 'Submit for approval';
const ITEMS_LEFT_FIRST = '{0} items left: {1}';
const ITEM_LEFT_FIRST = '1 item left: {0}';
const READY = 'Ready to submit';
const DISCARD_TITLE = 'Discard this draft?';
const DISCARD_MESSAGE = 'The draft {0} is deleted. This cannot be undone.';
const LEAVE_TITLE = 'Leave without saving?';
const LEAVE_MESSAGE = 'Your changes to this configuration have not been saved and will be lost.';
const SUBMIT_TITLE = 'Submit for approval';
const SUBMIT_MESSAGE_TO = '{0} will be asked to approve this configuration. You cannot change it while it is waiting for approval; you can withdraw it.';
const SUBMIT_MESSAGE = 'The configuration is sent for approval. You cannot change it while it is waiting for approval; you can withdraw it.';
const TOAST_SAVED = 'Draft saved';
const TOAST_SUBMITTED = 'Sent for approval';
const TOAST_DISCARDED = 'Draft discarded';
const NOT_SAVED_ONE = 'Not saved. Fix this first: {0}';
const NOT_SAVED_MANY = 'Not saved. Fix these {0} items first, starting with: {1}';
const NOT_SUBMITTED = 'Saved as a draft, but not sent for approval: {0}';
const RELOAD = 'Reload the latest version';
const RELOAD_TITLE = 'Reload this configuration?';
const RELOAD_MESSAGE = 'Your unsaved changes will be lost.';

export const labels = {
    back: BACK,
    loading: LOADING,
    retry: RETRY,
    error: ERROR,
    noAccess: NO_ACCESS,
    none: NONE,
    version: VERSION,
    percentSuffix: PERCENT_SUFFIX,
    newConfiguration: NEW_CONFIGURATION,
    stateDraft: STATE_DRAFT,
    stateReturned: STATE_RETURNED,
    statePending: STATE_PENDING,
    stateUpcoming: STATE_UPCOMING,
    stateActive: STATE_ACTIVE,
    stateExpired: STATE_EXPIRED,
    stateReplaced: STATE_REPLACED,
    changeCorrection: CHANGE_CORRECTION,
    changeFromDate: CHANGE_FROM_DATE,
    changeNextPeriod: CHANGE_NEXT_PERIOD,
    changeEndEarly: CHANGE_END_EARLY,
    changeCopy: CHANGE_COPY,
    initial: INITIAL,
    midNumbered: MID_NUMBERED,
    final: FINAL,
    backOverview: BACK_OVERVIEW,
    joined: JOINED,
    notSavedYet: NOT_SAVED_YET,
    unsavedChanges: UNSAVED_CHANGES,
    savedAt: SAVED_AT,
    saving: SAVING,
    returnedBanner: RETURNED_BANNER,
    returnedBannerNoComment: RETURNED_BANNER_NO_COMMENT,
    readOnlyPending: READ_ONLY_PENDING,
    readOnlyApproved: READ_ONLY_APPROVED,
    readOnlyOther: READ_ONLY_OTHER,
    endEarlyNote: END_EARLY_NOTE,
    loadError: LOAD_ERROR,
    nothingToShow: NOTHING_TO_SHOW,
    checklist: CHECKLIST,
    checklistOpen: CHECKLIST_OPEN,
    checklistDone: CHECKLIST_DONE,
    checklistNotPaid: CHECKLIST_NOT_PAID,
    checklistItemsLeft: CHECKLIST_ITEMS_LEFT,
    checklistItemLeft: CHECKLIST_ITEM_LEFT,
    checklistReady: CHECKLIST_READY,
    checklistGoTo: CHECKLIST_GO_TO,
    sectionPeriod: SECTION_PERIOD,
    sectionStages: SECTION_STAGES,
    sectionRates: SECTION_RATES,
    sectionOwn: SECTION_OWN,
    sectionOptions: SECTION_OPTIONS,
    stagesHint: STAGES_HINT,
    stagesHintOver: STAGES_HINT_OVER,
    stageLeft: STAGE_LEFT,
    project: PROJECT,
    chooseProject: CHOOSE_PROJECT,
    startDate: START_DATE,
    endDate: END_DATE,
    noOverlap: NO_OVERLAP,
    overlap: OVERLAP,
    overlapOnSave: OVERLAP_ON_SAVE,
    needProject: NEED_PROJECT,
    needStart: NEED_START,
    needEnd: NEED_END,
    endBeforeStart: END_BEFORE_START,
    startInsideSource: START_INSIDE_SOURCE,
    startAfterSource: START_AFTER_SOURCE,
    endNotAfterSource: END_NOT_AFTER_SOURCE,
    needInitial: NEED_INITIAL,
    needFinal: NEED_FINAL,
    needEvent: NEED_EVENT,
    needParameterPercent: NEED_PARAMETER_PERCENT,
    needParameterTranche: NEED_PARAMETER_TRANCHE,
    needParameterInstallment: NEED_PARAMETER_INSTALLMENT,
    needPercent: NEED_PERCENT,
    needPercentLeft: NEED_PERCENT_LEFT,
    percentRange: PERCENT_RANGE,
    trancheRange: TRANCHE_RANGE,
    eventNotAllowed: EVENT_NOT_ALLOWED,
    totalLeft: TOTAL_LEFT,
    totalOver: TOTAL_OVER,
    midOrder: MID_ORDER,
    duplicateStage: DUPLICATE_STAGE,
    midNotAllowed: MID_NOT_ALLOWED,
    shortStagePercent: SHORT_STAGE_PERCENT,
    shortStageEvent: SHORT_STAGE_EVENT,
    targetBasis: TARGET_BASIS,
    targetPeriod: TARGET_PERIOD,
    exceedMode: EXCEED_MODE,
    choose: CHOOSE,
    colPay: COL_PAY,
    colDesignation: COL_DESIGNATION,
    colTarget: COL_TARGET,
    colCurrent: COL_CURRENT,
    colExceed: COL_EXCEED,
    colClaim: COL_CLAIM,
    teamTotal: TEAM_TOTAL,
    notPaid: NOT_PAID,
    payDesignation: PAY_DESIGNATION,
    fieldOf: FIELD_OF,
    noDesignations: NO_DESIGNATIONS,
    needAnyRate: NEED_ANY_RATE,
    needRate: NEED_RATE,
    needExceed: NEED_EXCEED,
    needTarget: NEED_TARGET,
    rateRange: RATE_RANGE,
    targetRange: TARGET_RANGE,
    exceedLower: EXCEED_LOWER,
    needBasis: NEED_BASIS,
    needTargetPeriod: NEED_TARGET_PERIOD,
    needExceedMode: NEED_EXCEED_MODE,
    rate: RATE,
    contractReference: CONTRACT_REFERENCE,
    whenToRelease: WHEN_TO_RELEASE,
    releaseAllInitial: RELEASE_ALL_INITIAL,
    releaseSplit: RELEASE_SPLIT,
    contractHasTarget: CONTRACT_HAS_TARGET,
    exceedRate: EXCEED_RATE,
    needReleaseMode: NEED_RELEASE_MODE,
    feeAmount: FEE_AMOUNT,
    needAmount: NEED_AMOUNT,
    amountRange: AMOUNT_RANGE,
    priceExcludesTax: PRICE_EXCLUDES_TAX,
    changeReason: CHANGE_REASON,
    changeReasonPlaceholder: CHANGE_REASON_PLACEHOLDER,
    needReason: NEED_REASON,
    carryOver: CARRY_OVER,
    discard: DISCARD,
    saveDraft: SAVE_DRAFT,
    submit: SUBMIT,
    itemsLeftFirst: ITEMS_LEFT_FIRST,
    itemLeftFirst: ITEM_LEFT_FIRST,
    ready: READY,
    discardTitle: DISCARD_TITLE,
    discardMessage: DISCARD_MESSAGE,
    leaveTitle: LEAVE_TITLE,
    leaveMessage: LEAVE_MESSAGE,
    submitTitle: SUBMIT_TITLE,
    submitMessageTo: SUBMIT_MESSAGE_TO,
    submitMessage: SUBMIT_MESSAGE,
    toastSaved: TOAST_SAVED,
    toastSubmitted: TOAST_SUBMITTED,
    toastDiscarded: TOAST_DISCARDED,
    notSavedOne: NOT_SAVED_ONE,
    notSavedMany: NOT_SAVED_MANY,
    notSubmitted: NOT_SUBMITTED,
    reload: RELOAD,
    reloadTitle: RELOAD_TITLE,
    reloadMessage: RELOAD_MESSAGE
};