import { LightningElement, api } from 'lwc';
import { fill, formatDate, formatPeriod } from 'c/commissionUtils';
import NONE from '@salesforce/label/c.Commission_Common_None';
import VERSION_SHORT from '@salesforce/label/c.Commission_Common_Version_Short';
import WITH_APPROVER from '@salesforce/label/c.Commission_State_Pending_Short';
import FILTER_LABEL from '@salesforce/label/c.Commission_Setup_Filter_Label';
import FILTER_MINE from '@salesforce/label/c.Commission_Setup_Filter_Mine';
import FILTER_ENDING from '@salesforce/label/c.Commission_Setup_Filter_Ending';
import FILTER_NONE from '@salesforce/label/c.Commission_Setup_Filter_None';
import FILTER_DRAFTS from '@salesforce/label/c.Commission_Setup_Filter_Drafts';
import FILTER_ALL from '@salesforce/label/c.Commission_Setup_Filter_All';
import FILTER_EMPTY from '@salesforce/label/c.Commission_Setup_Filter_Empty';
import FILTER_SHOW_ALL from '@salesforce/label/c.Commission_Setup_Filter_Show_All';
import SHOWING from '@salesforce/label/c.Commission_Setup_Showing';
import TODAY from '@salesforce/label/c.Commission_Setup_Today';
import NO_PROJECTS from '@salesforce/label/c.Commission_Setup_No_Projects';
import TABLE_CAPTION from '@salesforce/label/c.Commission_Setup_Table_Caption';
import COL_PROJECT from '@salesforce/label/c.Commission_Setup_Col_Project';
import COL_CURRENT from '@salesforce/label/c.Commission_Setup_Col_Current';
import COL_PERIOD from '@salesforce/label/c.Commission_Setup_Col_Period';
import COL_DAYS_LEFT from '@salesforce/label/c.Commission_Setup_Col_Days_Left';
import COL_NEXT from '@salesforce/label/c.Commission_Setup_Col_Next';
import COL_STATUS from '@salesforce/label/c.Commission_Setup_Col_Status';
import COL_ACTION from '@salesforce/label/c.Commission_Setup_Col_Action';
import TWO_PARTS from '@salesforce/label/c.Commission_Setup_Two_Parts';
import OPEN_TITLE from '@salesforce/label/c.Commission_Setup_Open_Title';
import ACTION_OPEN from '@salesforce/label/c.Commission_Setup_Action_Open';
import ACTION_VIEW from '@salesforce/label/c.Commission_Setup_Action_View';
import ACTION_REVIEW from '@salesforce/label/c.Commission_Setup_Action_Review';
import ACTION_OPEN_DRAFT from '@salesforce/label/c.Commission_Setup_Action_Open_Draft';
import ACTION_NEXT_PERIOD from '@salesforce/label/c.Commission_Setup_Action_Next_Period';
import ACTION_CONFIGURE from '@salesforce/label/c.Commission_Setup_Action_Configure';
import OVERVIEW_NOTE from '@salesforce/label/c.Commission_Setup_Overview_Note';

const LABELS = {
    none: NONE,
    filterLabel: FILTER_LABEL,
    filterEmpty: FILTER_EMPTY,
    filterShowAll: FILTER_SHOW_ALL,
    noProjects: NO_PROJECTS,
    tableCaption: TABLE_CAPTION,
    colProject: COL_PROJECT,
    colCurrent: COL_CURRENT,
    colPeriod: COL_PERIOD,
    colDaysLeft: COL_DAYS_LEFT,
    colNext: COL_NEXT,
    colStatus: COL_STATUS,
    colAction: COL_ACTION,
    overviewNote: OVERVIEW_NOTE
};

// The chips above the table: each counts the projects that carry its flag (CommissionDto.ProjectRow)
const FILTER_ALL_KEY = 'all';
const FILTER_MINE_KEY = 'mine';
const FILTERS = [
    { key: FILTER_MINE_KEY, flag: 'needsMyAction', label: FILTER_MINE },
    { key: 'ending', flag: 'endingSoon', label: FILTER_ENDING },
    { key: 'none', flag: 'noConfiguration', label: FILTER_NONE },
    { key: 'pending', flag: 'withApprover', label: WITH_APPROVER },
    { key: 'drafts', flag: 'hasDraft', label: FILTER_DRAFTS },
    { key: FILTER_ALL_KEY, flag: null, label: FILTER_ALL }
];

// The colours a status pill can take (CommissionDto.ProjectRow.tone)
const TONES = ['green', 'amber', 'red', 'blue', 'grey'];
const DEFAULT_TONE = 'grey';

// What the row button does (CommissionDto.ProjectRow.action), and its text when the server sent none
const ACTION_NONE = 'NONE';
const ACTION_LABELS = {
    OPEN: ACTION_OPEN,
    VIEW: ACTION_VIEW,
    REVIEW: ACTION_REVIEW,
    OPEN_DRAFT: ACTION_OPEN_DRAFT,
    NEXT_PERIOD: ACTION_NEXT_PERIOD,
    CONFIGURE: ACTION_CONFIGURE
};
const CHOICE_NEXT_PERIOD = 'NEXT_PERIOD';
const MODE_REVIEW = 'review';
const MODE_EDIT = 'edit';

const isBlank = (value) => value === null || value === undefined || value === '';
// A text that says something: the server sends a dash for "nothing", which gets the grey dash of the table instead
const hasWords = (text) => !isBlank(text) && String(text).replace(/[\s\-\u2013\u2014\u00b7.]/g, '') !== '';

// "CC-0003 · v1"
function configText(summary) {
    if (!summary) {
        return '';
    }
    return isBlank(summary.version) ? summary.name || '' : fill(TWO_PARTS, summary.name, fill(VERSION_SHORT, summary.version));
}

// A date inside a sentence stays on one line ("from 01 Nov 2026" must not break inside the date)
function keepDatesTogether(text) {
    return String(text).replace(/(\d{2}) (\S{3,9}) (\d{4})/g, '$1 $2 $3');
}

// The chip the user picked, kept while the page lives: the overview is built again after every visit to a configuration
let pickedFilter = null;

export default class CommissionOverview extends LightningElement {
    labels = LABELS;

    rows = [];
    today;
    filter = pickedFilter || FILTER_ALL_KEY;
    // Once the user picked a chip, a refresh of the data keeps it
    filterChosen = pickedFilter !== null;

    _workspace;

    @api
    get workspace() {
        return this._workspace;
    }
    set workspace(value) {
        this._workspace = value;
        this.today = value ? value.today : null;
        this.rows = ((value && value.projects) || []).map((project) => this.toRow(project));
        if (!this.filterChosen) {
            this.filter = this.rows.some((row) => row.needsMyAction) ? FILTER_MINE_KEY : FILTER_ALL_KEY;
        }
    }

    // One table row with its ready-made texts and class strings
    toRow(project) {
        const current = project.current && project.current.id ? project.current : null;
        const next = project.next && project.next.id ? project.next : null;
        const hasDays = !!current && !isBlank(project.daysLeft);
        const nextText = hasWords(project.nextText) ? keepDatesTogether(project.nextText) : '';
        const action = isBlank(project.action) ? ACTION_NONE : project.action;
        const actionLabel = project.actionLabel || ACTION_LABELS[action] || '';
        const tone = TONES.includes(project.tone) ? project.tone : DEFAULT_TONE;
        return {
            key: project.projectId,
            projectId: project.projectId,
            projectName: project.projectName,
            hasCurrent: !!current,
            currentId: current ? current.id : null,
            currentText: configText(current),
            currentTitle: current ? fill(OPEN_TITLE, configText(current)) : '',
            periodText: current ? formatPeriod(current.startDate, current.endDate) : '',
            hasDays,
            daysText: hasDays ? String(project.daysLeft) : '',
            daysClass: project.endingSoon ? 'warn' : '',
            hasNext: nextText !== '',
            nextText,
            nextId: next ? next.id : null,
            nextIsLink: nextText !== '' && !!next,
            nextTitle: next ? fill(OPEN_TITLE, configText(next)) : '',
            nextClass: project.nextIsWarning ? 'bad' : '',
            stateLabel: project.stateLabel,
            pillClass: `pill ${tone}`,
            hasAction: action !== ACTION_NONE && actionLabel !== '',
            action,
            actionLabel,
            actionClass: project.actionPrimary ? 'btn sm primary' : 'btn sm',
            actionConfigId: project.actionConfigId,
            needsMyAction: project.needsMyAction === true,
            endingSoon: project.endingSoon === true,
            noConfiguration: project.noConfiguration === true,
            withApprover: project.withApprover === true,
            hasDraft: project.hasDraft === true
        };
    }

    get chips() {
        return FILTERS.map((entry) => {
            const active = entry.key === this.filter;
            return {
                key: entry.key,
                label: entry.label,
                count: entry.flag ? this.rows.filter((row) => row[entry.flag]).length : this.rows.length,
                className: active ? 'chip active' : 'chip',
                pressed: active ? 'true' : 'false'
            };
        });
    }

    get visibleRows() {
        const chosen = FILTERS.find((entry) => entry.key === this.filter);
        return chosen && chosen.flag ? this.rows.filter((row) => row[chosen.flag]) : this.rows;
    }

    get hasProjects() {
        return this.rows.length > 0;
    }

    get hasVisibleRows() {
        return this.visibleRows.length > 0;
    }

    get todayText() {
        return this.today ? fill(TODAY, formatDate(this.today)) : '';
    }

    // Read out by a screen reader when the chip changes
    get showingText() {
        return fill(SHOWING, this.visibleRows.length, this.rows.length);
    }

    handleChip(event) {
        this.filter = event.currentTarget.dataset.key;
        this.filterChosen = true;
        pickedFilter = this.filter;
    }

    handleShowAll() {
        this.filter = FILTER_ALL_KEY;
        this.filterChosen = true;
        pickedFilter = this.filter;
    }

    rowOf(event) {
        const key = event.currentTarget.dataset.key;
        return this.rows.find((row) => row.key === key);
    }

    // The configuration name opens that configuration read-only
    handleOpenCurrent(event) {
        const row = this.rowOf(event);
        if (row && row.currentId) {
            this.openConfig(row.currentId, MODE_REVIEW);
        }
    }

    handleOpenNext(event) {
        const row = this.rowOf(event);
        if (row && row.nextId) {
            this.openConfig(row.nextId, MODE_REVIEW);
        }
    }

    handleAction(event) {
        const row = this.rowOf(event);
        if (!row) {
            return;
        }
        switch (row.action) {
            case 'OPEN':
            case 'VIEW':
            case 'REVIEW':
                this.openConfig(row.actionConfigId || row.currentId, MODE_REVIEW);
                break;
            case 'OPEN_DRAFT':
                this.openConfig(row.actionConfigId, MODE_EDIT);
                break;
            case 'NEXT_PERIOD':
                this.dispatchEvent(
                    new CustomEvent('draftfrom', {
                        detail: { sourceId: row.currentId || row.actionConfigId, choice: CHOICE_NEXT_PERIOD }
                    })
                );
                break;
            case 'CONFIGURE':
                this.dispatchEvent(new CustomEvent('newconfig', { detail: { projectId: row.projectId } }));
                break;
            default:
        }
    }

    openConfig(configId, mode) {
        if (configId) {
            this.dispatchEvent(new CustomEvent('openconfig', { detail: { configId, mode } }));
        }
    }
}