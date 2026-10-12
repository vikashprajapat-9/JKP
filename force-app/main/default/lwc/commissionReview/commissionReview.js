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
import ERROR from '@salesforce/label/c.Commission_Common_Error';
import LOADING from '@salesforce/label/c.Commission_Common_Loading';
import RETRY from '@salesforce/label/c.Commission_Common_Retry';
import BACK from '@salesforce/label/c.Commission_Common_Back';
import NONE from '@salesforce/label/c.Commission_Common_None';
import NO_ACCESS from '@salesforce/label/c.Commission_Common_No_Access';
import VERSION from '@salesforce/label/c.Commission_Common_Version';
import PERCENT_SUFFIX from '@salesforce/label/c.Commission_Common_Percent_Suffix';
import STAGE_INITIAL from '@salesforce/label/c.Commission_Stage_Initial';
import STAGE_MID_NUMBERED from '@salesforce/label/c.Commission_Stage_Mid_Numbered';
import STAGE_FINAL from '@salesforce/label/c.Commission_Stage_Final';
import MODE_MARGINAL from '@salesforce/label/c.Commission_Exceed_Mode_Marginal';
import MODE_RETROSPECTIVE from '@salesforce/label/c.Commission_Exceed_Mode_Retrospective';
import BASIS_UNITS from '@salesforce/label/c.Commission_Target_Basis_Units';
import BASIS_VALUE from '@salesforce/label/c.Commission_Target_Basis_Value';
import PERIOD_CONFIGURATION from '@salesforce/label/c.Commission_Target_Period_Configuration';
import PERIOD_MONTH from '@salesforce/label/c.Commission_Target_Period_Month';
import PERIOD_QUARTER from '@salesforce/label/c.Commission_Target_Period_Quarter';
import PERIOD_YEAR from '@salesforce/label/c.Commission_Target_Period_Year';
import CHANGE_CORRECTION from '@salesforce/label/c.Commission_Change_Correction';
import CHANGE_FROM_DATE from '@salesforce/label/c.Commission_Change_From_Date';
import CHANGE_NEXT_PERIOD from '@salesforce/label/c.Commission_Change_Next_Period';
import CHANGE_END_EARLY from '@salesforce/label/c.Commission_Change_End_Early';
import CHANGE_COPY from '@salesforce/label/c.Commission_Change_Copy';
import TITLE_APPROVAL from '@salesforce/label/c.Commission_Review_Title_Approval';
import SUBLINE from '@salesforce/label/c.Commission_Review_Subline';
import WAITING_FOR_YOU from '@salesforce/label/c.Commission_Review_Waiting_For_You';
import SUBMITTED from '@salesforce/label/c.Commission_Review_Submitted';
import APPROVED from '@salesforce/label/c.Commission_Review_Approved';
import RETURNED from '@salesforce/label/c.Commission_Review_Returned';
import RETURNED_LEAD from '@salesforce/label/c.Commission_Review_Returned_Lead';
import RETURNED_LEAD_PLAIN from '@salesforce/label/c.Commission_Review_Returned_Lead_Plain';
import WITHDRAWN from '@salesforce/label/c.Commission_Review_Withdrawn';
import LEAD_NEW from '@salesforce/label/c.Commission_Review_Lead_New';
import LEAD_CORRECTION from '@salesforce/label/c.Commission_Review_Lead_Correction';
import LEAD_FROM_DATE from '@salesforce/label/c.Commission_Review_Lead_From_Date';
import LEAD_NEXT_PERIOD from '@salesforce/label/c.Commission_Review_Lead_Next_Period';
import LEAD_END_EARLY from '@salesforce/label/c.Commission_Review_Lead_End_Early';
import LEAD_COPY from '@salesforce/label/c.Commission_Review_Lead_Copy';
import REASON from '@salesforce/label/c.Commission_Review_Reason';
import WHAT_CHANGES from '@salesforce/label/c.Commission_Review_What_Changes';
import COUNT_NO_CHANGES from '@salesforce/label/c.Commission_Review_Count_No_Changes';
import COUNT_CHANGE_ONE from '@salesforce/label/c.Commission_Review_Count_Change_One';
import COUNT_CHANGES from '@salesforce/label/c.Commission_Review_Count_Changes';
import COUNT_UNCHANGED_ONE from '@salesforce/label/c.Commission_Review_Count_Unchanged_One';
import COUNT_UNCHANGED from '@salesforce/label/c.Commission_Review_Count_Unchanged';
import TWO_PARTS from '@salesforce/label/c.Commission_Review_Two_Parts';
import HINT_NEW from '@salesforce/label/c.Commission_Review_Hint_New';
import VIEW_LABEL from '@salesforce/label/c.Commission_Review_View_Label';
import VIEW_CHANGES from '@salesforce/label/c.Commission_Review_View_Changes';
import VIEW_FULL from '@salesforce/label/c.Commission_Review_View_Full';
import TABLE_CAPTION from '@salesforce/label/c.Commission_Review_Table_Caption';
import COL_ITEM from '@salesforce/label/c.Commission_Review_Col_Item';
import COL_CONFIGURATION from '@salesforce/label/c.Commission_Review_Col_Configuration';
import COL_CHANGE from '@salesforce/label/c.Commission_Review_Col_Change';
import COL_VERSION from '@salesforce/label/c.Commission_Review_Col_Version';
import KIND_APPROVED from '@salesforce/label/c.Commission_Review_Kind_Approved';
import KIND_PROPOSED from '@salesforce/label/c.Commission_Review_Kind_Proposed';
import KIND_DRAFT from '@salesforce/label/c.Commission_Review_Kind_Draft';
import KIND_REPLACED from '@salesforce/label/c.Commission_Review_Kind_Replaced';
import KIND_PREVIOUS from '@salesforce/label/c.Commission_Review_Kind_Previous';
import TAG_CHANGED from '@salesforce/label/c.Commission_Review_Tag_Changed';
import TAG_ADDED from '@salesforce/label/c.Commission_Review_Tag_Added';
import TAG_REMOVED from '@salesforce/label/c.Commission_Review_Tag_Removed';
import NO_CHANGES from '@salesforce/label/c.Commission_Review_No_Changes';
import SHOW_FULL from '@salesforce/label/c.Commission_Review_Show_Full';
import ITEM_START from '@salesforce/label/c.Commission_Review_Item_Start';
import ITEM_END from '@salesforce/label/c.Commission_Review_Item_End';
import ITEM_PRICE from '@salesforce/label/c.Commission_Review_Item_Price';
import PRICE_EXCLUDING from '@salesforce/label/c.Commission_Review_Price_Excluding';
import PRICE_INCLUDING from '@salesforce/label/c.Commission_Review_Price_Including';
import ITEM_PAYOUT from '@salesforce/label/c.Commission_Review_Item_Payout';
import ITEM_RATE from '@salesforce/label/c.Commission_Review_Item_Rate';
import ITEM_RELEASE from '@salesforce/label/c.Commission_Review_Item_Release';
import ITEM_BASIS from '@salesforce/label/c.Commission_Review_Item_Basis';
import ITEM_PERIOD from '@salesforce/label/c.Commission_Review_Item_Period';
import ITEM_EXCEED_MODE from '@salesforce/label/c.Commission_Review_Item_Exceed_Mode';
import NOT_PAID from '@salesforce/label/c.Commission_Review_Not_Paid';
import NOT_SET from '@salesforce/label/c.Commission_Review_Not_Set';
import PART_TARGET from '@salesforce/label/c.Commission_Review_Part_Target';
import PART_CURRENT from '@salesforce/label/c.Commission_Review_Part_Current';
import PART_EXCEED from '@salesforce/label/c.Commission_Review_Part_Exceed';
import PART_CONTRACT from '@salesforce/label/c.Commission_Review_Part_Contract';
import UNITS from '@salesforce/label/c.Commission_Review_Units';
import AMOUNT from '@salesforce/label/c.Commission_Review_Amount';
import PAID_WHEN_DETAIL from '@salesforce/label/c.Commission_Review_Paid_When_Detail';
import RELEASE_ALL from '@salesforce/label/c.Commission_Review_Release_All';
import RELEASE_SPLIT from '@salesforce/label/c.Commission_Review_Release_Split';
import STAGE_PART from '@salesforce/label/c.Commission_Review_Stage_Part';
import YOUR_DECISION from '@salesforce/label/c.Commission_Review_Your_Decision';
import COMMENT from '@salesforce/label/c.Commission_Review_Comment';
import COMMENT_PLACEHOLDER from '@salesforce/label/c.Commission_Review_Comment_Placeholder';
import COMMENT_REQUIRED from '@salesforce/label/c.Commission_Review_Comment_Required';
import REJECT from '@salesforce/label/c.Commission_Review_Reject';
import APPROVE from '@salesforce/label/c.Commission_Review_Approve';
import LOCK_NOTE from '@salesforce/label/c.Commission_Review_Lock_Note';
import APPROVED_TOAST from '@salesforce/label/c.Commission_Review_Approved_Toast';
import REJECTED_TOAST from '@salesforce/label/c.Commission_Review_Rejected_Toast';
import WITHDRAW from '@salesforce/label/c.Commission_Review_Withdraw';
import WITHDRAW_TITLE from '@salesforce/label/c.Commission_Review_Withdraw_Title';
import WITHDRAW_MESSAGE from '@salesforce/label/c.Commission_Review_Withdraw_Message';
import WITHDRAWN_TOAST from '@salesforce/label/c.Commission_Review_Withdrawn_Toast';
import EDIT_DRAFT from '@salesforce/label/c.Commission_Review_Edit_Draft';
import NEW_DRAFT from '@salesforce/label/c.Commission_Review_New_Draft';
import OPEN_DRAFT from '@salesforce/label/c.Commission_Review_Open_Draft';
import OPEN_IN_SETUP from '@salesforce/label/c.Commission_Review_Open_In_Setup';
import NO_RECORD from '@salesforce/label/c.Commission_Review_No_Record';
import CHOICE_CORRECTION from '@salesforce/label/c.Commission_Review_Choice_Correction';
import CHOICE_FROM_DATE from '@salesforce/label/c.Commission_Review_Choice_From_Date';
import CHOICE_NEXT_PERIOD from '@salesforce/label/c.Commission_Review_Choice_Next_Period';
import CHOICE_END_EARLY from '@salesforce/label/c.Commission_Review_Choice_End_Early';
import CHOICE_COPY from '@salesforce/label/c.Commission_Review_Choice_Copy';

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