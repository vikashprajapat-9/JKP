import { LightningElement, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import LightningConfirm from 'lightning/confirm';
import { errorText, fill, formatDateTime, formatPeriod } from 'c/commissionUtils';
import getWorkspace from '@salesforce/apex/CommissionSetupController.getWorkspace';
import newDraft from '@salesforce/apex/CommissionSetupController.newDraft';
import draftFrom from '@salesforce/apex/CommissionSetupController.draftFrom';
import CommissionSetupProjectPicker from 'c/commissionSetupProjectPicker';
const ERROR = 'Something went wrong. Please try again.';
const LOADING = 'Loading…';
const RETRY = 'Try again';
const CLOSE = 'Close';
const NONE = '—';
const NO_ACCESS = 'You do not have access to Commission Setup. Ask your Salesforce administrator.';
const VERSION_SHORT = 'v{0}';
const CHANGE_NEW = 'New configuration';
const CHANGE_CORRECTION = 'Correct this version';
const CHANGE_FROM_DATE = 'Change terms from a date';
const CHANGE_NEXT_PERIOD = 'Next period';
const CHANGE_END_EARLY = 'End early';
const CHANGE_COPY = 'Copy to another project';
const TARGETS_DISCARD_TITLE = 'Unsaved changes';
const TARGETS_DISCARD_MESSAGE = 'You have target changes that are not saved. Discard them?';
const TITLE = 'Commission Setup';
const SUBTITLE = 'Commission configuration by project';
const VIEWS_LABEL = 'Commission Setup views';
const TAB_OVERVIEW = 'Overview';
const TAB_APPROVALS = 'Approvals';
const TAB_TARGETS = 'Targets';
const TAB_MY_TERMS = 'My terms';
const APPROVALS_WAITING = '{0} waiting for a decision';
const NEW_CONFIGURATION = '+ New configuration';
const APPROVALS_TITLE = 'Waiting for approval';
const APPROVALS_EMPTY = 'Nothing is waiting for approval.';
const APPROVALS_TO_OVERVIEW = 'Go to Overview';
const APPROVALS_CAPTION = 'Commission configurations waiting for approval';
const COL_PROJECT = 'Project';
const COL_CONFIGURATION = 'Configuration';
const COL_PERIOD = 'Period';
const COL_CHANGE = 'Change';
const COL_SUBMITTED_BY = 'Submitted by';
const COL_SUBMITTED_ON = 'Submitted on';
const COL_ACTION = 'Action';
const ACTION_REVIEW = 'Review';
const ACTION_VIEW = 'View';
const TWO_PARTS = '{0} · {1}';

const LABELS = {
    loading: LOADING,
    retry: RETRY,
    close: CLOSE,
    none: NONE,
    noAccess: NO_ACCESS,
    title: TITLE,
    subtitle: SUBTITLE,
    viewsLabel: VIEWS_LABEL,
    newConfiguration: NEW_CONFIGURATION,
    approvalsTitle: APPROVALS_TITLE,
    approvalsEmpty: APPROVALS_EMPTY,
    approvalsToOverview: APPROVALS_TO_OVERVIEW,
    approvalsCaption: APPROVALS_CAPTION,
    colProject: COL_PROJECT,
    colConfiguration: COL_CONFIGURATION,
    colPeriod: COL_PERIOD,
    colChange: COL_CHANGE,
    colSubmittedBy: COL_SUBMITTED_BY,
    colSubmittedOn: COL_SUBMITTED_ON,
    colAction: COL_ACTION
};

// The views of the tab. The first four are lists and have a button in the view switch; editor and review show one configuration.
const VIEW_OVERVIEW = 'overview';
const VIEW_APPROVALS = 'approvals';
const VIEW_TARGETS = 'targets';
const VIEW_TERMS = 'terms';
const VIEW_EDITOR = 'editor';
const VIEW_REVIEW = 'review';
const LIST_VIEWS = [VIEW_OVERVIEW, VIEW_APPROVALS, VIEW_TARGETS, VIEW_TERMS];
const TAB_LABELS = {
    [VIEW_OVERVIEW]: TAB_OVERVIEW,
    [VIEW_APPROVALS]: TAB_APPROVALS,
    [VIEW_TARGETS]: TAB_TARGETS,
    [VIEW_TERMS]: TAB_MY_TERMS
};

// The page state that mirrors the view, so that a notification link or a browser reload returns to the same place
const STATE_VIEW = 'c__view';
const STATE_ID = 'c__id';

// What a child asks for when it opens a configuration (event openconfig)
const MODE_EDIT = 'edit';
// The action of an overview row that says this user can look at a pending configuration but not decide it
const ACTION_VIEW_ONLY = 'VIEW';

// Commission_Config__c.Change_Type__c -> its label
const CHANGE_LABELS = {
    New: CHANGE_NEW,
    Correction: CHANGE_CORRECTION,
    'Change From Date': CHANGE_FROM_DATE,
    'Next Period': CHANGE_NEXT_PERIOD,
    'End Early': CHANGE_END_EARLY,
    Copy: CHANGE_COPY
};

const isBlank = (value) => value === null || value === undefined || value === '';
const routeKey = (view, id) => `${view || ''}|${id || ''}`;

// { c__view: 'Review', c__id: 'a0X…' } -> { view: 'review', id: 'a0X…' }
function routeOf(state) {
    const source = state || {};
    return {
        view: isBlank(source[STATE_VIEW]) ? '' : String(source[STATE_VIEW]).trim().toLowerCase(),
        id: isBlank(source[STATE_ID]) ? '' : String(source[STATE_ID]).trim()
    };
}

// "CC-0003 · v1"
function configText(summary) {
    return isBlank(summary.version) ? summary.name || '' : fill(TWO_PARTS, summary.name, fill(VERSION_SHORT, summary.version));
}

// The Commission Setup tab: header with the view switch, the list views, and the editor and review of one configuration
export default class CommissionSetup extends NavigationMixin(LightningElement) {
    labels = LABELS;

    workspace;
    loading = true;
    loadError = '';
    // A new draft is being prepared by the server
    busy = false;
    // A failed action or refresh, shown above the view that stays on screen
    actionError = '';

    view = '';
    // The list view the editor or review was opened from: Back returns to it
    returnView = '';

    // What the editor or review on screen was opened with. Kept unchanged while it is open, so that the child is not reloaded under the user.
    childKey = 0;
    childConfigId;
    childDraft;
    childCatalog;
    childFlags;
    childProjects;
    // The configuration id for the page state (an unsaved draft gets one with its first save)
    routeId = '';

    approvalRows = [];
    approvalCount = 0;

    // Page-state bookkeeping: the page this component lives on, and the view | id the address shows as far as we know
    pageRef;
    homePage;
    urlKey;
    pendingRoute;
    // The user went to another page while this tab stayed in memory
    away = false;
    loadTicket = 0;

    connectedCallback() {
        this.loadWorkspace();
    }

    // ------------------------------------------------------------ page state (deep links)

    @wire(CurrentPageReference)
    wiredPageReference(pageRef) {
        if (!pageRef) {
            return;
        }
        // A cached tab also hears about the pages the user goes to next: only our own page counts
        const page = `${pageRef.type}|${JSON.stringify(pageRef.attributes || {})}`;
        if (this.homePage === undefined) {
            this.homePage = page;
        } else if (page !== this.homePage) {
            // The user is on another page: the lists are read again when they come back
            this.away = true;
            return;
        }
        this.pageRef = pageRef;
        if (this.away) {
            this.away = false;
            if (this.workspace) {
                this.loadWorkspace();
            }
        }
        const route = routeOf(pageRef.state);
        const key = routeKey(route.view, route.id);
        if (key === this.urlKey) {
            // Our own update coming back
            return;
        }
        this.urlKey = key;
        if (this.workspace) {
            this.applyRoute(route);
        } else {
            this.pendingRoute = route;
        }
    }

    // Shows what a link asks for; anything unknown or not allowed falls back to the user's first view
    applyRoute(route) {
        const view = route.view;
        if (!view && !route.id && (this.view === VIEW_EDITOR || this.targetsHaveEdits())) {
            // The tab itself was clicked while something is being edited: it stays, and its own Back or the view switch asks about unsaved changes
            this.syncPageState();
            return;
        }
        if (route.id && this.canView && !LIST_VIEWS.includes(view)) {
            // A link to one configuration: the editor when it says so, otherwise the review
            this.openChild(view === VIEW_EDITOR ? VIEW_EDITOR : VIEW_REVIEW, route.id, undefined);
            return;
        }
        this.closeChild();
        this.view = this.isAllowed(view) ? view : this.defaultView;
        this.syncPageState();
    }

    // Writes the view to the page state (replacing the history entry) when it differs from what the address shows
    syncPageState() {
        if (!this.pageRef) {
            return;
        }
        let view = this.view;
        let id = '';
        if (this.isChildView) {
            id = this.routeId || '';
            if (!id) {
                // An unsaved draft has no address: the link stays on the list it was opened from
                view = this.returnView;
            }
        }
        if (!id && view === this.defaultView) {
            view = '';
        }
        const key = routeKey(view, id);
        if (key === this.urlKey) {
            return;
        }
        this.urlKey = key;
        const state = Object.assign({}, this.pageRef.state);
        delete state[STATE_VIEW];
        delete state[STATE_ID];
        if (view) {
            state[STATE_VIEW] = view;
        }
        if (id) {
            state[STATE_ID] = id;
        }
        try {
            this[NavigationMixin.Navigate]({ type: this.pageRef.type, attributes: this.pageRef.attributes, state }, true);
        } catch (error) {
            // The screen works without the address; nothing to tell the user
        }
    }

    // ------------------------------------------------------------ workspace

    async loadWorkspace() {
        this.loadTicket += 1;
        const ticket = this.loadTicket;
        const first = !this.workspace;
        if (first) {
            this.loading = true;
            this.loadError = '';
        }
        try {
            const workspace = await getWorkspace();
            if (ticket !== this.loadTicket) {
                return;
            }
            this.workspace = workspace || {};
            this.digestApprovals();
            if (first) {
                const route = this.pendingRoute || routeOf(this.pageRef && this.pageRef.state);
                this.pendingRoute = undefined;
                this.applyRoute(route);
            } else if (!this.isChildView && !this.isAllowed(this.view)) {
                this.view = this.defaultView;
                this.syncPageState();
            }
        } catch (error) {
            if (ticket !== this.loadTicket) {
                return;
            }
            const message = errorText(error, ERROR);
            if (first) {
                this.loadError = message;
            } else {
                this.actionError = message;
            }
        } finally {
            if (ticket === this.loadTicket) {
                this.loading = false;
            }
        }
    }

    // The rows of the Approvals view and the number in the view switch
    digestApprovals() {
        const projects = this.workspace.projects || [];
        const approvals = this.workspace.approvals || [];
        const viewOnly = new Set(
            projects.filter((project) => project.action === ACTION_VIEW_ONLY && project.actionConfigId).map((project) => project.actionConfigId)
        );
        const canApprove = this.flags.canApprove === true;
        this.approvalRows = approvals.map((summary) => {
            const mine = canApprove && !viewOnly.has(summary.id);
            return {
                key: summary.id,
                projectName: summary.projectName,
                configText: configText(summary),
                periodText: formatPeriod(summary.startDate, summary.endDate) || NONE,
                changeText: CHANGE_LABELS[summary.changeType] || summary.changeType || NONE,
                submittedBy: summary.submittedByName || NONE,
                submittedOn: formatDateTime(summary.submittedOn) || NONE,
                mine,
                buttonLabel: mine ? ACTION_REVIEW : ACTION_VIEW,
                buttonClass: mine ? 'btn sm primary' : 'btn sm'
            };
        });
        // An approver sees how many wait for them; everybody else how many wait at all
        this.approvalCount = canApprove ? this.approvalRows.filter((row) => row.mine).length : this.approvalRows.length;
    }

    // ------------------------------------------------------------ what the user may see

    get flags() {
        return (this.workspace && this.workspace.flags) || {};
    }

    get canView() {
        const flags = this.flags;
        return !!(flags.canView || flags.canConfigure || flags.canApprove || flags.canManageTargets);
    }

    get allowedViews() {
        const views = [];
        if (this.canView) {
            views.push(VIEW_OVERVIEW, VIEW_APPROVALS, VIEW_TARGETS);
        }
        if (this.flags.isPayee) {
            views.push(VIEW_TERMS);
        }
        return views;
    }

    get defaultView() {
        return this.allowedViews[0] || '';
    }

    isAllowed(view) {
        return this.allowedViews.includes(view);
    }

    get currencyCode() {
        const catalog = this.workspace && this.workspace.catalog;
        return catalog && catalog.settings ? catalog.settings.currencyCode : undefined;
    }

    // ------------------------------------------------------------ what is on screen

    get isChildView() {
        return this.view === VIEW_EDITOR || this.view === VIEW_REVIEW;
    }

    // The review draws its own grey panel (it also lives on the record page): a second one around it would only add an inset
    get shellClass() {
        return this.view === VIEW_REVIEW ? 'shell' : 'shell screen';
    }

    get showLoading() {
        return this.loading && !this.workspace;
    }

    get showLoadError() {
        return !this.showLoading && !this.workspace && this.loadError !== '';
    }

    get isReady() {
        return !!this.workspace;
    }

    get showNoAccess() {
        return this.isReady && this.allowedViews.length === 0;
    }

    get isOverview() {
        return this.isReady && this.view === VIEW_OVERVIEW;
    }

    get isApprovals() {
        return this.isReady && this.view === VIEW_APPROVALS;
    }

    get isTargets() {
        return this.isReady && this.view === VIEW_TARGETS;
    }

    get isTerms() {
        return this.isReady && this.view === VIEW_TERMS;
    }

    get tabs() {
        return this.allowedViews.map((view) => {
            const active = view === this.view;
            const hasCount = view === VIEW_APPROVALS && this.approvalCount > 0;
            return {
                key: view,
                label: TAB_LABELS[view],
                className: active ? 'tab active' : 'tab',
                current: active ? 'page' : null,
                hasCount,
                count: this.approvalCount,
                countTitle: hasCount ? fill(APPROVALS_WAITING, this.approvalCount) : ''
            };
        });
    }

    get hasTabs() {
        return this.isReady && this.allowedViews.length > 0;
    }

    // As in the mock-ups: on Overview (and Approvals), not on Targets
    get showNewButton() {
        return this.isReady && this.flags.canConfigure === true && (this.view === VIEW_OVERVIEW || this.view === VIEW_APPROVALS);
    }

    get hasApprovals() {
        return this.approvalRows.length > 0;
    }

    get approvalsHint() {
        return this.hasApprovals ? fill(APPROVALS_WAITING, this.approvalRows.length) : '';
    }

    // The editor and the review are rendered through a list of one entry: a new key gives a fresh component for each configuration opened
    get editorSlots() {
        return this.view === VIEW_EDITOR ? [{ key: `editor-${this.childKey}` }] : [];
    }

    get reviewSlots() {
        return this.view === VIEW_REVIEW ? [{ key: `review-${this.childKey}` }] : [];
    }

    // ------------------------------------------------------------ moving between views

    openChild(view, configId, draft) {
        if (LIST_VIEWS.includes(this.view)) {
            this.returnView = this.view;
        } else if (!this.isAllowed(this.returnView)) {
            this.returnView = this.defaultView;
        }
        this.childKey += 1;
        this.childConfigId = configId || undefined;
        this.childDraft = draft || undefined;
        this.childCatalog = this.workspace.catalog;
        this.childFlags = this.workspace.flags;
        this.childProjects = this.workspace.projects;
        this.routeId = configId || (draft && draft.id) || '';
        this.view = view;
        this.actionError = '';
        this.syncPageState();
    }

    closeChild() {
        this.childConfigId = undefined;
        this.childDraft = undefined;
        this.routeId = '';
    }

    // Back to the list the editor or review was opened from, with fresh figures
    leaveChild() {
        if (!this.isChildView) {
            return;
        }
        this.closeChild();
        this.view = this.isAllowed(this.returnView) ? this.returnView : this.defaultView;
        this.actionError = '';
        this.syncPageState();
        this.loadWorkspace();
    }

    // The Targets view is on screen with something typed that is not saved
    targetsHaveEdits() {
        const targets = this.view === VIEW_TARGETS ? this.template.querySelector('c-commission-targets') : null;
        return !!targets && !!targets.hasUnsavedChanges;
    }

    async handleTab(event) {
        const view = event.currentTarget.dataset.view;
        if (!this.isAllowed(view) || view === this.view) {
            return;
        }
        if (this.targetsHaveEdits()) {
            const confirmed = await LightningConfirm.open({
                label: TARGETS_DISCARD_TITLE,
                message: TARGETS_DISCARD_MESSAGE,
                variant: 'header',
                theme: 'warning'
            });
            if (!confirmed || this.view !== VIEW_TARGETS) {
                return;
            }
        }
        this.view = view;
        this.actionError = '';
        this.syncPageState();
    }

    handleShowOverview() {
        this.view = this.defaultView;
        this.syncPageState();
    }

    handleRetry() {
        this.loadWorkspace();
    }

    handleDismissError() {
        this.actionError = '';
    }

    // ------------------------------------------------------------ events of the children

    // { configId, mode }: mode edit opens the editor, review or view the read-only review
    handleOpenConfig(event) {
        const detail = event.detail || {};
        if (!detail.configId) {
            return;
        }
        this.openChild(detail.mode === MODE_EDIT ? VIEW_EDITOR : VIEW_REVIEW, detail.configId, undefined);
    }

    handleApprovalOpen(event) {
        this.openChild(VIEW_REVIEW, event.currentTarget.dataset.id, undefined);
    }

    // { projectId }: a blank draft for that project; without a project the dialog asks for one
    handleNewConfig(event) {
        const projectId = event.detail && event.detail.projectId;
        if (projectId) {
            this.startDraft(() => newDraft({ projectId }));
        } else {
            this.handleNewConfiguration();
        }
    }

    async handleNewConfiguration() {
        const projects = ((this.workspace && this.workspace.projects) || []).map((project) => ({
            value: project.projectId,
            label: project.projectName
        }));
        const projectId = await CommissionSetupProjectPicker.open({ size: 'small', label: CHANGE_NEW, projects });
        if (projectId) {
            this.startDraft(() => newDraft({ projectId }));
        }
    }

    // { sourceId, choice, targetProjectId }: a draft made from an approved configuration
    handleDraftFrom(event) {
        const detail = event.detail || {};
        if (!detail.sourceId || !detail.choice) {
            return;
        }
        this.startDraft(() =>
            draftFrom({ sourceId: detail.sourceId, choice: detail.choice, targetProjectId: detail.targetProjectId || null })
        );
    }

    // Asks the server for an unsaved draft and opens the editor with it
    async startDraft(request) {
        if (this.busy) {
            return;
        }
        this.busy = true;
        this.actionError = '';
        try {
            const draft = await request();
            if (!draft) {
                throw new Error(ERROR);
            }
            this.openChild(VIEW_EDITOR, undefined, draft);
        } catch (error) {
            this.actionError = errorText(error, ERROR);
        } finally {
            this.busy = false;
        }
    }

    handleBack() {
        this.leaveChild();
    }

    // The first save gives a draft its id: from now on a reload returns to it
    handleSaved(event) {
        const config = event.detail && event.detail.config;
        if (config && config.id && this.view === VIEW_EDITOR) {
            this.routeId = config.id;
            this.syncPageState();
        }
    }

    // Submitted or discarded: the editor has nothing more to do, the list shows the new state
    handleSubmitted() {
        this.leaveChild();
    }

    handleDiscarded() {
        this.leaveChild();
    }

    // Approved or rejected: the review stays, the lists behind it are refreshed
    handleDecided() {
        this.loadWorkspace();
    }

    handleRefresh() {
        this.loadWorkspace();
    }
}