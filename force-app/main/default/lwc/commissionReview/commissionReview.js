import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import LightningConfirm from 'lightning/confirm';
import { errorText, fill, formatDate, toIso } from 'c/commissionUtils';
import CommissionReviewDraftFrom from 'c/commissionReviewDraftFrom';
import { ADDED, CHANGED, REMOVED, SAME, compareConfigs, summarise } from './commissionReviewCompare';
import getConfig from '@salesforce/apex/CommissionSetupController.getConfig';
import getWorkspace from '@salesforce/apex/CommissionSetupController.getWorkspace';
import decide from '@salesforce/apex/CommissionSetupController.decide';
import withdraw from '@salesforce/apex/CommissionSetupController.withdraw';
const ERROR = 'Something went wrong. Please try again.';
const LOADING = 'Loading…';
const RETRY = 'Try again';
const BACK = 'Back';
const NONE = '—';
const NO_ACCESS = 'You do not have access to Commission Setup. Ask your Salesforce administrator.';
const VERSION = 'Version {0}';
const PERCENT_SUFFIX = '%';
const STAGE_INITIAL = 'Initial';
const STAGE_MID_NUMBERED = 'Mid {0}';
const STAGE_FINAL = 'Final';
const MODE_MARGINAL = 'Sales above target only';
const MODE_RETROSPECTIVE = 'All sales in the period';
const BASIS_UNITS = 'Units';
const BASIS_VALUE = 'Value';
const PERIOD_CONFIGURATION = 'Configuration period';
const PERIOD_MONTH = 'Month';
const PERIOD_QUARTER = 'Quarter';
const PERIOD_YEAR = 'Year';
const CHANGE_CORRECTION = 'Correct this version';
const CHANGE_FROM_DATE = 'Change terms from a date';
const CHANGE_NEXT_PERIOD = 'Next period';
const CHANGE_END_EARLY = 'End early';
const CHANGE_COPY = 'Copy to another project';
const TITLE_APPROVAL = 'Approval request';
const SUBLINE = '{0} · {1} · {2}';
const WAITING_FOR_YOU = 'Waiting for your decision';
const SUBMITTED = 'Submitted by {0} on {1}';
const APPROVED = 'Approved by {0} on {1}';
const RETURNED = 'Returned by {0} on {1}';
const RETURNED_LEAD = 'Returned by {0} on {1}:';
const RETURNED_LEAD_PLAIN = 'Returned with this comment:';
const WITHDRAWN = 'Withdrawn by {0} on {1}';
const LEAD_NEW = 'New configuration.';
const LEAD_CORRECTION = 'Correction of an approved version.';
const LEAD_FROM_DATE = 'Change terms from {0}.';
const LEAD_NEXT_PERIOD = 'Next period, from {0}.';
const LEAD_END_EARLY = 'End early, on {0}.';
const LEAD_COPY = 'New configuration, copied from another project.';
const REASON = 'Reason for change';
const WHAT_CHANGES = 'What changes';
const COUNT_NO_CHANGES = 'No changes';
const COUNT_CHANGE_ONE = '1 change';
const COUNT_CHANGES = '{0} changes';
const COUNT_UNCHANGED_ONE = '1 item unchanged';
const COUNT_UNCHANGED = '{0} items unchanged';
const TWO_PARTS = '{0} · {1}';
const HINT_NEW = 'New: nothing to compare';
const VIEW_LABEL = 'What to show';
const VIEW_CHANGES = 'Changes only';
const VIEW_FULL = 'Full configuration';
const TABLE_CAPTION = 'The items of this configuration, compared with the earlier version';
const COL_ITEM = 'Item';
const COL_CONFIGURATION = 'Configuration';
const COL_CHANGE = 'Change';
const COL_VERSION = '{0} ({1})';
const KIND_APPROVED = 'approved';
const KIND_PROPOSED = 'proposed';
const KIND_DRAFT = 'draft';
const KIND_REPLACED = 'replaced';
const KIND_PREVIOUS = 'previous period';
const TAG_CHANGED = 'Changed';
const TAG_ADDED = 'Added';
const TAG_REMOVED = 'Removed';
const NO_CHANGES = 'Nothing differs from the earlier version.';
const SHOW_FULL = 'Show the full configuration';
const ITEM_START = 'Start date';
const ITEM_END = 'End date';
const ITEM_PRICE = 'Commission calculated on';
const PRICE_EXCLUDING = 'Price excluding taxes';
const PRICE_INCLUDING = 'Price including taxes';
const ITEM_PAYOUT = '{0} payout';
const ITEM_RATE = '{0} rate';
const ITEM_RELEASE = '{0} release';
const ITEM_BASIS = 'Target counted in';
const ITEM_PERIOD = 'Target period';
const ITEM_EXCEED_MODE = 'Exceed rate applies to';
const NOT_PAID = 'Not paid';
const NOT_SET = 'Not set';
const PART_TARGET = 'Target {0}';
const PART_CURRENT = 'Current {0}';
const PART_EXCEED = 'Exceed {0}';
const PART_CONTRACT = 'Contract {0}';
const UNITS = '{0} units';
const AMOUNT = '{0} {1}';
const PAID_WHEN_DETAIL = '{0}: {1}';
const RELEASE_ALL = 'All at the Initial event';
const RELEASE_SPLIT = 'Split between Initial and Final';
const STAGE_PART = '{0}: {1}';
const YOUR_DECISION = 'Your decision';
const COMMENT = 'Comment';
const COMMENT_PLACEHOLDER = 'Required when you reject';
const COMMENT_REQUIRED = 'Enter a comment to reject.';
const REJECT = 'Reject';
const APPROVE = 'Approve';
const LOCK_NOTE = 'Figures cannot be edited here. To ask for a change, reject with a comment.';
const APPROVED_TOAST = '{0} is approved.';
const REJECTED_TOAST = '{0} is rejected and returned to Finance.';
const WITHDRAW = 'Withdraw';
const WITHDRAW_TITLE = 'Withdraw from approval';
const WITHDRAW_MESSAGE = 'Withdraw {0} from approval? It becomes a draft again, and you can change it and submit it again.';
const WITHDRAWN_TOAST = '{0} is withdrawn and is a draft again.';
const EDIT_DRAFT = 'Edit draft';
const NEW_DRAFT = 'New draft from this';
const OPEN_DRAFT = 'Open draft {0}';
const OPEN_IN_SETUP = 'Open in Commission Setup';
const NO_RECORD = 'No configuration was selected.';
const CHOICE_CORRECTION = 'A value was entered wrongly. On approval the new version replaces this one for its whole period.';
const CHOICE_FROM_DATE = 'The terms change during the period. This version ends the day before; sales whose Initial payout event falls before that date keep these terms.';
const CHOICE_NEXT_PERIOD = 'The period is coming to an end. The new configuration starts the day after this one ends; personal targets can be carried over.';
const CHOICE_END_EARLY = 'Commission stops before the planned end date. On approval the end date is brought forward.';
const CHOICE_COPY = 'Another project needs similar terms. Nothing changes on this configuration.';

const LABELS = {
    loading: LOADING,
    retry: RETRY,
    back: BACK,
    none: NONE,
    noAccess: NO_ACCESS,
    reason: REASON,
    whatChanges: WHAT_CHANGES,
    viewLabel: VIEW_LABEL,
    tableCaption: TABLE_CAPTION,
    colItem: COL_ITEM,
    colChange: COL_CHANGE,
    noChanges: NO_CHANGES,
    showFull: SHOW_FULL,
    yourDecision: YOUR_DECISION,
    comment: COMMENT,
    commentPlaceholder: COMMENT_PLACEHOLDER,
    reject: REJECT,
    approve: APPROVE,
    lockNote: LOCK_NOTE,
    withdraw: WITHDRAW,
    editDraft: EDIT_DRAFT,
    newDraft: NEW_DRAFT,
    openInSetup: OPEN_IN_SETUP
};

// The words of the comparison (commissionReviewCompare takes them from here)
const COMPARE_TEXTS = {
    startDate: ITEM_START,
    endDate: ITEM_END,
    priceBasis: ITEM_PRICE,
    priceExcludingTax: PRICE_EXCLUDING,
    priceIncludingTax: PRICE_INCLUDING,
    payoutItem: ITEM_PAYOUT,
    rateItem: ITEM_RATE,
    releaseItem: ITEM_RELEASE,
    targetBasis: ITEM_BASIS,
    targetPeriod: ITEM_PERIOD,
    exceedMode: ITEM_EXCEED_MODE,
    initial: STAGE_INITIAL,
    midNumbered: STAGE_MID_NUMBERED,
    final: STAGE_FINAL,
    notPaid: NOT_PAID,
    notSet: NOT_SET,
    partTarget: PART_TARGET,
    partCurrent: PART_CURRENT,
    partExceed: PART_EXCEED,
    partContract: PART_CONTRACT,
    units: UNITS,
    amount: AMOUNT,
    paidWhenDetail: PAID_WHEN_DETAIL,
    percentSuffix: PERCENT_SUFFIX,
    releaseAll: RELEASE_ALL,
    releaseSplit: RELEASE_SPLIT,
    stagePart: STAGE_PART
};

// Texts of the option values, used when the catalog does not bring its own
const OPTION_TEXTS = {
    targetBasis: { Units: BASIS_UNITS, Value: BASIS_VALUE },
    targetPeriod: { 'Configuration Period': PERIOD_CONFIGURATION, Month: PERIOD_MONTH, Quarter: PERIOD_QUARTER, Year: PERIOD_YEAR },
    exceedMode: { Marginal: MODE_MARGINAL, Retrospective: MODE_RETROSPECTIVE }
};

// Commission_Config__c.Status__c
const STATUS_DRAFT = 'Draft';
const STATUS_PENDING = 'Pending Approval';
const STATUS_APPROVED = 'Approved';
const STATUS_SUPERSEDED = 'Superseded';
const DECISION_REJECTED = 'Rejected';
const DECISION_RECALLED = 'Recalled';
const STATE_RETURNED_KEY = 'RETURNED';
const BASELINE_PREVIOUS = 'PREVIOUS_PERIOD';

// Colour of the state pill by display state
const TONES = { DRAFT: 'grey', RETURNED: 'red', PENDING: 'blue', UPCOMING: 'blue', ACTIVE: 'green', EXPIRED: 'amber', REPLACED: 'grey' };
// "(approved)" behind a version in the column titles
const KINDS = { [STATUS_DRAFT]: KIND_DRAFT, [STATUS_PENDING]: KIND_PROPOSED, [STATUS_APPROVED]: KIND_APPROVED, [STATUS_SUPERSEDED]: KIND_REPLACED };
const TAGS = { [CHANGED]: TAG_CHANGED, [ADDED]: TAG_ADDED, [REMOVED]: TAG_REMOVED };
const TAG_CLASSES = { [CHANGED]: 'tag', [ADDED]: 'tag added', [REMOVED]: 'tag removed' };

// The five choices of "New draft from this" (CommissionConfigService.draftFrom), with their title and one sentence each
const DRAFT_CHOICES = [
    { value: 'CORRECTION', title: CHANGE_CORRECTION, text: CHOICE_CORRECTION },
    { value: 'CHANGE_FROM_DATE', title: CHANGE_FROM_DATE, text: CHOICE_FROM_DATE },
    { value: 'NEXT_PERIOD', title: CHANGE_NEXT_PERIOD, text: CHOICE_NEXT_PERIOD },
    { value: 'END_EARLY', title: CHANGE_END_EARLY, text: CHOICE_END_EARLY },
    { value: 'COPY', title: CHANGE_COPY, text: CHOICE_COPY, needsProject: true }
];

const DECISION_APPROVE = 'APPROVE';
const DECISION_REJECT = 'REJECT';
const VIEW_CHANGES_ONLY = 'changes';
const VIEW_EVERYTHING = 'full';
const MODE_EDIT = 'edit';
const MODE_REVIEW = 'review';
// The Commission Setup tab and its page state, for the buttons of the record page
const SETUP_TAB = 'Commission_Setup';
const STATE_VIEW = 'c__view';
const STATE_ID = 'c__id';
const SETUP_VIEW_EDITOR = 'editor';
const SETUP_VIEW_REVIEW = 'review';
// Watched on the record page, to notice a change made outside this component (named as text: no compile-time tie to the object)
const WATCHED_FIELDS = ['Commission_Config__c.Status__c', 'Commission_Config__c.LastModifiedDate'];

const isBlank = (value) => value === null || value === undefined || value === '';

// A date-time of the server as a date in the browser's time zone: '08 Oct 2026'
function localDate(value) {
    if (isBlank(value)) {
        return '';
    }
    const moment = new Date(value);
    return Number.isNaN(moment.getTime()) ? formatDate(value) : formatDate(toIso(moment));
}

function optionMap(options, fallback) {
    const map = Object.assign({}, fallback);
    (options || []).forEach((option) => {
        if (option && !isBlank(option.value) && !isBlank(option.label)) {
            map[option.value] = option.label;
        }
    });
    return map;
}

// The approval request of one configuration and its read-only view: what changes against the earlier version, the
// decision of the approver, and the actions that start from an approved configuration. Used inside the Commission Setup
// tab (config-id) and on the record page of Commission Configuration (recordId).
export default class CommissionReview extends NavigationMixin(LightningElement) {
    labels = LABELS;

    // From the Commission Setup tab. On the record page they are missing and loaded here.
    @api catalog;
    @api flags;
    @api projects;

    config;
    loading = true;
    loadError = '';
    // Catalog, flags and projects loaded by this component when the page did not pass them
    ownCatalog;
    ownFlags;
    ownProjects;

    rows = [];
    summary = { total: 0, unchanged: 0, changes: 0 };
    viewMode = VIEW_EVERYTHING;
    comments = '';
    commentError = '';
    // An approval, rejection or withdrawal is on its way
    working = false;
    actionError = '';

    connected = false;
    loadTicket = 0;
    _configId;
    _recordId;
    // When the record was last changed, as the record page last told us
    seenModified;

    @api
    get configId() {
        return this._configId;
    }
    set configId(value) {
        const changed = value !== this._configId;
        this._configId = value;
        if (changed && this.connected) {
            this.load();
        }
    }

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        const changed = value !== this._recordId;
        this._recordId = value;
        if (changed && this.connected && !this._configId) {
            this.load();
        }
    }

    connectedCallback() {
        this.connected = true;
        this.load();
    }

    // On the record page the record can change under us: approved or rejected from Approval History, or edited by an
    // administrator. The page then tells us, and the configuration is read again. Inside the tab there is no recordId.
    @wire(getRecord, { recordId: '$recordId', fields: WATCHED_FIELDS })
    wiredRecord({ data }) {
        const field = data && data.fields ? data.fields.LastModifiedDate : null;
        const modified = field ? field.value : null;
        if (!modified) {
            return;
        }
        const before = this.seenModified;
        this.seenModified = modified;
        if (before && before !== modified && this.standalone && this.config && !this.loading && !this.working) {
            this.load(true);
        }
    }

    disconnectedCallback() {
        this.connected = false;
    }

    // ------------------------------------------------------------ loading

    get targetId() {
        return this._configId || this._recordId;
    }

    // On the record page nobody listens to our events: the buttons open the Commission Setup tab instead
    get standalone() {
        return !this._configId && !!this._recordId;
    }

    get activeCatalog() {
        return this.catalog || this.ownCatalog;
    }

    get activeFlags() {
        return this.flags || this.ownFlags;
    }

    get activeProjects() {
        return this.projects || this.ownProjects || [];
    }

    // quiet: the configuration on screen is read again; what the user chose to see and typed stays
    async load(quiet) {
        this.loadTicket += 1;
        const ticket = this.loadTicket;
        const id = this.targetId;
        this.loadError = '';
        this.actionError = '';
        if (!id) {
            this.config = undefined;
            this.loading = false;
            this.loadError = NO_RECORD;
            return;
        }
        this.loading = true;
        try {
            // The catalog only adds the designation order, the currency and the option texts: the page works without it
            const needWorkspace = !this.catalog && !this.ownCatalog;
            const [config, workspace] = await Promise.all([
                getConfig({ configId: id }),
                needWorkspace ? getWorkspace().catch(() => null) : Promise.resolve(null)
            ]);
            if (ticket !== this.loadTicket) {
                return;
            }
            if (workspace) {
                this.ownCatalog = workspace.catalog;
                this.ownFlags = workspace.flags;
                this.ownProjects = workspace.projects;
            }
            if (!config) {
                throw new Error(ERROR);
            }
            this.applyConfig(config, quiet !== true);
        } catch (error) {
            if (ticket !== this.loadTicket) {
                return;
            }
            this.config = undefined;
            this.loadError = errorText(error, ERROR);
        } finally {
            if (ticket === this.loadTicket) {
                this.loading = false;
            }
        }
    }

    // Takes a configuration from the server and prepares the comparison
    applyConfig(config, fresh) {
        this.config = config;
        const catalog = this.activeCatalog || {};
        const context = {
            texts: COMPARE_TEXTS,
            currency: catalog.settings ? catalog.settings.currencyCode : undefined,
            options: {
                targetBasis: optionMap(catalog.targetBases, OPTION_TEXTS.targetBasis),
                targetPeriod: optionMap(catalog.targetPeriods, OPTION_TEXTS.targetPeriod),
                exceedMode: optionMap(catalog.exceedModes, OPTION_TEXTS.exceedMode)
            }
        };
        this.rows = compareConfigs(config.baseline || null, config, context);
        this.summary = summarise(this.rows);
        if (fresh) {
            // An approver first sees what differs; with nothing to compare or nothing changed, everything
            this.viewMode = config.baseline && this.summary.changes > 0 ? VIEW_CHANGES_ONLY : VIEW_EVERYTHING;
            this.comments = '';
            this.commentError = '';
        }
    }

    // ------------------------------------------------------------ states

    get noAccess() {
        const flags = this.activeFlags;
        return !!flags && !(flags.canView || flags.canConfigure || flags.canApprove || flags.canManageTargets);
    }

    get showLoading() {
        return this.loading && !this.config;
    }

    get showNoAccess() {
        return !this.showLoading && !this.config && this.noAccess;
    }

    get showLoadError() {
        return !this.showLoading && !this.config && !this.noAccess;
    }

    get isReady() {
        return !!this.config;
    }

    // ------------------------------------------------------------ header

    get canDecide() {
        return this.config.canDecide === true;
    }

    get headTitle() {
        return this.canDecide ? TITLE_APPROVAL : this.config.name || '';
    }

    get subline() {
        const version = isBlank(this.config.version) ? '' : fill(VERSION, this.config.version);
        return fill(SUBLINE, this.config.projectName, this.config.name, version);
    }

    get stateText() {
        return this.canDecide ? WAITING_FOR_YOU : this.config.stateLabel || this.config.status || '';
    }

    get stateClass() {
        const tone = this.canDecide ? 'blue' : TONES[this.config.state] || 'grey';
        return `pill ${tone}`;
    }

    // "Submitted by Finance on 08 Oct 2026", or who approved, returned or withdrew it
    get statusLine() {
        const config = this.config;
        if (config.status === STATUS_PENDING && !isBlank(config.submittedByName)) {
            return fill(SUBMITTED, config.submittedByName, localDate(config.submittedOn));
        }
        if ((config.status === STATUS_APPROVED || config.status === STATUS_SUPERSEDED) && !isBlank(config.approvedByName)) {
            return fill(APPROVED, config.approvedByName, localDate(config.approvedOn));
        }
        if (config.status === STATUS_DRAFT && !isBlank(config.decisionByName)) {
            if (config.decision === DECISION_REJECTED) {
                return fill(RETURNED, config.decisionByName, localDate(config.decisionOn));
            }
            if (config.decision === DECISION_RECALLED) {
                return fill(WITHDRAWN, config.decisionByName, localDate(config.decisionOn));
            }
        }
        return '';
    }

    get hasStatusLine() {
        return this.statusLine !== '';
    }

    // ------------------------------------------------------------ what this version does

    get changeLead() {
        const config = this.config;
        switch (config.changeType) {
            case 'Correction':
                return LEAD_CORRECTION;
            case 'Change From Date':
                return fill(LEAD_FROM_DATE, formatDate(config.startDate));
            case 'Next Period':
                return fill(LEAD_NEXT_PERIOD, formatDate(config.startDate));
            case 'End Early':
                return fill(LEAD_END_EARLY, formatDate(config.endDate));
            case 'Copy':
                return LEAD_COPY;
            default:
                return LEAD_NEW;
        }
    }

    get consequence() {
        return this.config.consequence || '';
    }

    get hasReason() {
        return !isBlank(this.config.changeReason);
    }

    // A rejected draft says why it came back
    get showReturned() {
        return this.config.state === STATE_RETURNED_KEY && !isBlank(this.config.decisionComments);
    }

    // "Returned by CCO on 09 Oct 2026:" in front of the comment
    get returnedLead() {
        const config = this.config;
        if (isBlank(config.decisionByName) || isBlank(config.decisionOn)) {
            return RETURNED_LEAD_PLAIN;
        }
        return fill(RETURNED_LEAD, config.decisionByName, localDate(config.decisionOn));
    }

    // ------------------------------------------------------------ what changes

    get hasBaseline() {
        return !!this.config.baseline;
    }

    get changesHint() {
        if (!this.hasBaseline) {
            return HINT_NEW;
        }
        const changes = this.summary.changes;
        const unchanged = this.summary.unchanged;
        const changeText = changes === 0 ? COUNT_NO_CHANGES : changes === 1 ? COUNT_CHANGE_ONE : fill(COUNT_CHANGES, changes);
        const unchangedText = unchanged === 1 ? COUNT_UNCHANGED_ONE : fill(COUNT_UNCHANGED, unchanged);
        return fill(TWO_PARTS, changeText, unchangedText);
    }

    get viewTabs() {
        return [
            { key: VIEW_CHANGES_ONLY, label: VIEW_CHANGES },
            { key: VIEW_EVERYTHING, label: VIEW_FULL }
        ].map((tab) => {
            const active = tab.key === this.viewMode;
            return Object.assign(tab, { className: active ? 'tab active' : 'tab', pressed: active ? 'true' : 'false' });
        });
    }

    get baselineTitle() {
        const baseline = this.config.baseline;
        if (!baseline) {
            return '';
        }
        if (this.config.baselineKind === BASELINE_PREVIOUS) {
            return fill(COL_VERSION, baseline.name, KIND_PREVIOUS);
        }
        return fill(COL_VERSION, fill(VERSION, baseline.version), KINDS[baseline.status] || KIND_APPROVED);
    }

    get versionTitle() {
        if (!this.hasBaseline) {
            return COL_CONFIGURATION;
        }
        return fill(COL_VERSION, fill(VERSION, this.config.version), KINDS[this.config.status] || KIND_PROPOSED);
    }

    // The rows on screen, each with its ready-made texts and classes
    get visibleRows() {
        const changesOnly = this.hasBaseline && this.viewMode === VIEW_CHANGES_ONLY;
        const piece = (rowKey, side) => (entry, index) => ({
            key: `${rowKey}-${side}-${index}`,
            prefix: entry.prefix,
            text: entry.text,
            suffix: entry.suffix,
            valueClass: entry.changed ? 'new' : ''
        });
        return this.rows
            .filter((row) => !changesOnly || row.status !== SAME)
            .map((row) => ({
                key: row.key,
                label: row.label,
                rowClass: row.status === SAME ? 'same' : row.status,
                hasBefore: !!row.before,
                before: (row.before || []).map(piece(row.key, 'before')),
                hasAfter: !!row.after,
                after: (row.after || []).map(piece(row.key, 'after')),
                hasTag: row.status !== SAME,
                tag: TAGS[row.status] || '',
                tagClass: TAG_CLASSES[row.status] || 'tag'
            }));
    }

    get hasVisibleRows() {
        return this.visibleRows.length > 0;
    }

    handleViewMode(event) {
        this.viewMode = event.currentTarget.dataset.view === VIEW_CHANGES_ONLY ? VIEW_CHANGES_ONLY : VIEW_EVERYTHING;
    }

    handleShowFull() {
        this.viewMode = VIEW_EVERYTHING;
    }

    // ------------------------------------------------------------ decision

    get isBlocked() {
        return !this.canDecide && !isBlank(this.config.decideBlockedReason);
    }

    get showDecision() {
        return this.canDecide || this.isBlocked;
    }

    get hasCommentError() {
        return this.commentError !== '';
    }

    handleComment(event) {
        this.comments = event.detail && event.detail.value !== undefined ? event.detail.value : event.target.value;
        if (!isBlank(this.comments) && String(this.comments).trim() !== '') {
            this.commentError = '';
        }
    }

    // What is in the comment box right now (the last keystroke may not have reached handleComment yet)
    readComments() {
        const box = this.template.querySelector('lightning-textarea');
        const typed = box && !isBlank(box.value) ? box.value : this.comments;
        return isBlank(typed) ? '' : String(typed).trim();
    }

    handleApprove() {
        this.sendDecision(DECISION_APPROVE, this.readComments());
    }

    handleReject() {
        const comments = this.readComments();
        if (comments === '') {
            this.commentError = COMMENT_REQUIRED;
            const box = this.template.querySelector('lightning-textarea');
            if (box && typeof box.focus === 'function') {
                box.focus();
            }
            return;
        }
        this.sendDecision(DECISION_REJECT, comments);
    }

    async sendDecision(decision, comments) {
        if (this.working) {
            return;
        }
        this.working = true;
        this.actionError = '';
        this.commentError = '';
        const name = this.config.name;
        try {
            const config = await decide({ configId: this.config.id, decision, comments: comments === '' ? null : comments });
            this.afterAction(config);
            this.toast(fill(decision === DECISION_APPROVE ? APPROVED_TOAST : REJECTED_TOAST, name));
            this.dispatchEvent(new CustomEvent('decided', { detail: { config: this.config } }));
        } catch (error) {
            this.actionError = errorText(error, ERROR);
        } finally {
            this.working = false;
        }
    }

    // ------------------------------------------------------------ footer actions

    get showBack() {
        return !this.standalone;
    }

    get showWithdraw() {
        return this.config.canWithdraw === true;
    }

    get showEdit() {
        return this.config.canEdit === true;
    }

    get showNewDraft() {
        return this.config.canCreateFrom === true && !this.standalone;
    }

    get showOpenDraft() {
        return !isBlank(this.config.openDraftId);
    }

    get openDraftLabel() {
        return fill(OPEN_DRAFT, this.config.openDraftName || '');
    }

    get hasActionError() {
        return this.actionError !== '';
    }

    handleBack() {
        this.dispatchEvent(new CustomEvent('back'));
    }

    async handleWithdraw() {
        if (this.working) {
            return;
        }
        const name = this.config.name;
        const confirmed = await LightningConfirm.open({
            label: WITHDRAW_TITLE,
            message: fill(WITHDRAW_MESSAGE, name),
            variant: 'header',
            theme: 'warning'
        });
        if (!confirmed || this.working) {
            return;
        }
        this.working = true;
        this.actionError = '';
        try {
            const config = await withdraw({ configId: this.config.id });
            this.afterAction(config);
            this.toast(fill(WITHDRAWN_TOAST, name));
            this.dispatchEvent(new CustomEvent('refresh'));
        } catch (error) {
            this.actionError = errorText(error, ERROR);
        } finally {
            this.working = false;
        }
    }

    handleEdit() {
        this.openConfig(this.config.id, MODE_EDIT);
    }

    handleOpenDraft() {
        this.openConfig(this.config.openDraftId, MODE_REVIEW);
    }

    handleOpenInSetup() {
        this.navigateToSetup(this.config.id, SETUP_VIEW_REVIEW);
    }

    // Inside the tab the shell switches the view; on the record page the tab is opened at that configuration
    openConfig(configId, mode) {
        if (!configId) {
            return;
        }
        if (this.standalone) {
            this.navigateToSetup(configId, mode === MODE_EDIT ? SETUP_VIEW_EDITOR : SETUP_VIEW_REVIEW);
            return;
        }
        this.dispatchEvent(new CustomEvent('openconfig', { detail: { configId, mode } }));
    }

    navigateToSetup(configId, view) {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: SETUP_TAB },
            state: { [STATE_VIEW]: view, [STATE_ID]: configId }
        });
    }

    // "New draft from this": the dialog returns the choice, the shell asks the server for the draft and opens the editor
    async handleNewDraft() {
        const config = this.config;
        const projects = this.activeProjects
            .filter((project) => project && project.projectId && project.projectId !== config.projectId)
            .map((project) => ({ value: project.projectId, label: project.projectName }));
        const heading = fill(TWO_PARTS, NEW_DRAFT, config.name);
        const result = await CommissionReviewDraftFrom.open({ size: 'small', label: heading, heading, choices: DRAFT_CHOICES, projects });
        if (!result || !result.choice) {
            return;
        }
        this.dispatchEvent(
            new CustomEvent('draftfrom', {
                detail: { sourceId: config.id, choice: result.choice, targetProjectId: result.targetProjectId || null }
            })
        );
    }

    // ------------------------------------------------------------ helpers

    handleRetry() {
        this.load();
    }

    // After an approval, rejection or withdrawal: the server sends the configuration as it is now
    afterAction(config) {
        if (config) {
            this.applyConfig(config, true);
        } else {
            this.load();
        }
        // The record page around us shows the same record
        try {
            const refreshed = notifyRecordUpdateAvailable([{ recordId: this.targetId }]);
            if (refreshed && typeof refreshed.catch === 'function') {
                refreshed.catch(() => {});
            }
        } catch (error) {
            // Nothing to refresh outside a record page
        }
    }

    toast(message) {
        this.dispatchEvent(new ShowToastEvent({ title: message, variant: 'success' }));
    }
}