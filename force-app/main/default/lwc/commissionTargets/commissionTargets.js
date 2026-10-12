import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import { errorText, fill, formatDate, formatNumber, formatPercent, toNumber, todayIso } from 'c/commissionUtils';
import getTargets from '@salesforce/apex/CommissionTargetController.getTargets';
import saveTargets from '@salesforce/apex/CommissionTargetController.saveTargets';
import ERROR from '@salesforce/label/c.Commission_Common_Error';
import LOADING from '@salesforce/label/c.Commission_Common_Loading';
import RETRY from '@salesforce/label/c.Commission_Common_Retry';
import CANCEL from '@salesforce/label/c.Commission_Common_Cancel';
import SAVE from '@salesforce/label/c.Commission_Common_Save';
import NONE from '@salesforce/label/c.Commission_Common_None';
import NO_ACCESS from '@salesforce/label/c.Commission_Common_No_Access';
import PROJECT from '@salesforce/label/c.Commission_Targets_Project';
import CONFIGURATION from '@salesforce/label/c.Commission_Targets_Configuration';
import COUNTED_IN from '@salesforce/label/c.Commission_Targets_Counted_In';
import PERIOD from '@salesforce/label/c.Commission_Targets_Period';
import TWO_PARTS from '@salesforce/label/c.Commission_Targets_Two_Parts';
import CAPTION from '@salesforce/label/c.Commission_Targets_Caption';
import COL_PERSON from '@salesforce/label/c.Commission_Targets_Col_Person';
import COL_TARGET from '@salesforce/label/c.Commission_Targets_Col_Target';
import COL_ACTUAL from '@salesforce/label/c.Commission_Targets_Col_Actual';
import COL_RESULT from '@salesforce/label/c.Commission_Targets_Col_Result';
import COL_CURRENT from '@salesforce/label/c.Commission_Targets_Col_Current';
import COL_EXCEED from '@salesforce/label/c.Commission_Targets_Col_Exceed';
import COL_FROM from '@salesforce/label/c.Commission_Targets_Col_From';
import TEAM from '@salesforce/label/c.Commission_Targets_Team';
import TEAM_COUNTS from '@salesforce/label/c.Commission_Targets_Team_Counts';
import TEAM_HIDE from '@salesforce/label/c.Commission_Targets_Team_Hide';
import TEAM_SHOW from '@salesforce/label/c.Commission_Targets_Team_Show';
import DEFAULT from '@salesforce/label/c.Commission_Targets_Default';
import SET_ON from '@salesforce/label/c.Commission_Targets_Set_On';
import SET_BY from '@salesforce/label/c.Commission_Targets_Set_By';
import PERSONAL from '@salesforce/label/c.Commission_Targets_Personal';
import USE_DEFAULT from '@salesforce/label/c.Commission_Targets_Use_Default';
import WAS from '@salesforce/label/c.Commission_Targets_Was';
import INPUT_LABEL from '@salesforce/label/c.Commission_Targets_Input_Label';
import INVALID from '@salesforce/label/c.Commission_Targets_Invalid';
import LOCKED from '@salesforce/label/c.Commission_Targets_Locked';
import NOTE_RATES from '@salesforce/label/c.Commission_Targets_Note_Rates';
import NOTE_ACTUALS from '@salesforce/label/c.Commission_Targets_Note_Actuals';
import CHANGE_ONE from '@salesforce/label/c.Commission_Targets_Change_One';
import CHANGES from '@salesforce/label/c.Commission_Targets_Changes';
import CHANGE_LINE from '@salesforce/label/c.Commission_Targets_Change_Line';
import CHANGE_LINE_DEFAULT from '@salesforce/label/c.Commission_Targets_Change_Line_Default';
import MORE from '@salesforce/label/c.Commission_Targets_More';
import FROM from '@salesforce/label/c.Commission_Targets_From';
import REASON from '@salesforce/label/c.Commission_Targets_Reason';
import REASON_PLACEHOLDER from '@salesforce/label/c.Commission_Targets_Reason_Placeholder';
import REASON_REQUIRED from '@salesforce/label/c.Commission_Targets_Reason_Required';
import FROM_REQUIRED from '@salesforce/label/c.Commission_Targets_From_Required';
import FIX_FIRST from '@salesforce/label/c.Commission_Targets_Fix_First';
import SAVED from '@salesforce/label/c.Commission_Targets_Saved';
import EMPTY from '@salesforce/label/c.Commission_Targets_Empty';
import DISCARD_TITLE from '@salesforce/label/c.Commission_Targets_Discard_Title';
import DISCARD_MESSAGE from '@salesforce/label/c.Commission_Targets_Discard_Message';

const LABELS = {
    loading: LOADING,
    retry: RETRY,
    cancel: CANCEL,
    save: SAVE,
    none: NONE,
    noAccess: NO_ACCESS,
    project: PROJECT,
    configuration: CONFIGURATION,
    caption: CAPTION,
    colPerson: COL_PERSON,
    colTarget: COL_TARGET,
    colActual: COL_ACTUAL,
    colResult: COL_RESULT,
    colCurrent: COL_CURRENT,
    colExceed: COL_EXCEED,
    colFrom: COL_FROM,
    useDefault: USE_DEFAULT,
    locked: LOCKED,
    noteRates: NOTE_RATES,
    noteActuals: NOTE_ACTUALS,
    from: FROM,
    reason: REASON,
    reasonPlaceholder: REASON_PLACEHOLDER
};

// Row shapes of the table
const KIND_MANAGER = 'group';
const KIND_MEMBER = 'sub';
const KIND_OTHER = 'solo';

const isBlank = (value) => value === null || value === undefined || value === '';
// A person can hold a target under one designation only once: that pair names the row
const editKeyOf = (person) => `${person.userId || ''}|${person.designation || ''}`;
const sameNumber = (first, second) => !isBlank(first) && !isBlank(second) && Number(first) === Number(second);
const inputText = (value) => (isBlank(value) ? '' : String(value));
// Targets are stored with two decimals
const rounded = (amount) => Math.round(amount * 100) / 100;
// From this many digits on (a target counted in value) the target box is the wide one
const WIDE_DIGITS = 6;

// The target table of the Head of Sales: everybody starts on the default target of the configuration, a personal
// target replaces it from a date and with a reason. Rates are shown read-only.
export default class CommissionTargets extends LightningElement {
    labels = LABELS;

    // What the running user may do (CommissionDto.Flags); the server decides per row what can be edited
    @api flags;

    table;
    loading = true;
    loadError = '';
    // Another project or configuration is being loaded: the table stays until it arrives
    reloading = false;
    actionError = '';

    // Changes not saved yet, by row: { target: number, or null for "back to the default" } or { invalid: true }
    edits = {};
    // What stands in a target box the user typed in, by row, exactly as typed: the box is never rewritten while typing
    typed = {};
    // Managers whose team is folded away, by row
    collapsed = {};
    people = {};
    wideTargets = false;
    effectiveFrom = '';
    reason = '';
    formError = '';
    saving = false;
    loadTicket = 0;

    connectedCallback() {
        if (this.noAccess) {
            this.loading = false;
            return;
        }
        this.fetch(null, null);
    }

    // ------------------------------------------------------------ loading

    get noAccess() {
        const flags = this.flags;
        return !!flags && !(flags.canView || flags.canManageTargets || flags.canConfigure || flags.canApprove);
    }

    async fetch(projectId, reference) {
        this.loadTicket += 1;
        const ticket = this.loadTicket;
        const first = !this.table;
        this.actionError = '';
        if (first) {
            this.loading = true;
            this.loadError = '';
        } else {
            this.reloading = true;
        }
        try {
            const table = await getTargets({ projectId: projectId || null, reference: reference || null });
            if (ticket !== this.loadTicket) {
                return;
            }
            this.applyTable(table || {});
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
                this.reloading = false;
            }
        }
    }

    // Takes a table from the server; whatever was typed belongs to the table before it
    applyTable(table) {
        this.table = table;
        const people = {};
        const everybody = [];
        (table.groups || []).forEach((group) => {
            if (group && group.manager) {
                everybody.push(group.manager);
            }
            ((group && group.members) || []).forEach((member) => everybody.push(member));
        });
        (table.others || []).forEach((person) => everybody.push(person));
        everybody.forEach((person) => {
            people[editKeyOf(person)] = person;
        });
        this.people = people;
        this.edits = {};
        this.typed = {};
        // Large targets (counted in value) need a wider box than a number of units
        this.wideTargets = everybody.some((person) => {
            const largest = Math.max(Math.abs(Number(person.target) || 0), Math.abs(Number(person.defaultTarget) || 0));
            return String(Math.trunc(largest)).length >= WIDE_DIGITS;
        });
        this.reason = '';
        this.formError = '';
        // A change applies from today, or from the start of a configuration that has not begun yet
        // (people on the default target carry that start date)
        const today = todayIso();
        const starts = everybody
            .filter((person) => person.isDefault === true && !isBlank(person.fromDate))
            .map((person) => String(person.fromDate).slice(0, 10))
            .sort();
        this.effectiveFrom = starts.length > 0 && starts[0] > today ? starts[0] : today;
    }

    // ------------------------------------------------------------ states

    get showLoading() {
        return this.loading && !this.table;
    }

    get showLoadError() {
        return !this.showLoading && !this.table && !this.noAccess;
    }

    get isReady() {
        return !!this.table;
    }

    get hasActionError() {
        return this.actionError !== '';
    }

    // ------------------------------------------------------------ project and configuration

    get projectOptions() {
        return this.table.projects || [];
    }

    get configOptions() {
        return this.table.configs || [];
    }

    get showPickers() {
        return this.projectOptions.length > 0;
    }

    get hasConfigs() {
        return this.configOptions.length > 0;
    }

    // "Target counted in units · Target period: configuration period"
    get basisText() {
        const basis = isBlank(this.table.basisLabel) ? '' : fill(COUNTED_IN, String(this.table.basisLabel).toLowerCase());
        const period = isBlank(this.table.periodLabel) ? '' : fill(PERIOD, String(this.table.periodLabel).toLowerCase());
        return basis !== '' && period !== '' ? fill(TWO_PARTS, basis, period) : basis || period;
    }

    handleProject(event) {
        this.switchTable(event, this.table.projectId, (value) => this.fetch(value, null));
    }

    handleConfig(event) {
        this.switchTable(event, this.table.reference, (value) => this.fetch(this.table.projectId, value));
    }

    // Another project or configuration: unsaved changes are given up only when the user says so
    async switchTable(event, current, load) {
        const box = event.target;
        const value = event.detail ? event.detail.value : box.value;
        if (isBlank(value) || value === current) {
            return;
        }
        if (this.hasEdits) {
            const confirmed = await LightningConfirm.open({
                label: DISCARD_TITLE,
                message: DISCARD_MESSAGE,
                variant: 'header',
                theme: 'warning'
            });
            if (!confirmed) {
                box.value = current;
                return;
            }
        }
        load(value);
    }

    // ------------------------------------------------------------ rows

    // The rows on screen, each with its ready-made texts and classes: a manager, the team under it, then everybody else
    get rows() {
        const table = this.table || {};
        const rows = [];
        const groups = table.groups || [];
        groups.forEach((group, groupIndex) => {
            const members = (group && group.members) || [];
            if (!group || !group.manager) {
                members.forEach((member, index) => rows.push(this.rowOf(member, `g${groupIndex}m${index}`, KIND_OTHER, {})));
                return;
            }
            const folded = this.collapsed[editKeyOf(group.manager)] === true;
            rows.push(this.rowOf(group.manager, `g${groupIndex}`, KIND_MANAGER, { teamSize: group.manager.teamSize || members.length, folded }));
            if (!folded) {
                members.forEach((member, index) => rows.push(this.rowOf(member, `g${groupIndex}m${index}`, KIND_MEMBER, {})));
            }
        });
        (table.others || []).forEach((person, index) => rows.push(this.rowOf(person, `o${index}`, KIND_OTHER, {})));
        return rows;
    }

    rowOf(person, key, kind, shape) {
        const editKey = editKeyOf(person);
        const edit = this.edits[editKey];
        const editable = person.canEdit === true;
        const personal = person.isDefault === false;
        const invalid = !!edit && edit.invalid === true;
        const changed = !!edit && !invalid;
        const toDefault = changed && edit.target === null;
        const value = !changed ? person.target : toDefault ? person.defaultTarget : edit.target;
        const isManager = kind === KIND_MANAGER;
        const name = person.name || '';

        // Beside the target: "default", when a personal target was set, or what it was before this change
        let hint = '';
        let hintTitle = '';
        if (toDefault || (!changed && !invalid && !personal)) {
            hint = DEFAULT;
        } else if (!changed && !invalid) {
            const since = formatDate(person.setOn || person.fromDate);
            hint = since === '' ? PERSONAL : fill(SET_ON, since);
            hintTitle = isBlank(person.setByName) ? '' : fill(SET_BY, person.setByName, person.reason || NONE);
        }
        const fromDate = changed ? this.effectiveFrom : person.fromDate;
        const hasResult = !isBlank(person.result);

        return {
            key,
            editKey,
            rowClass: kind === KIND_OTHER ? '' : kind,
            whoClass: `who ${kind}`,
            isManager,
            name,
            expanded: shape.folded ? 'false' : 'true',
            isFolded: shape.folded === true,
            toggleTitle: isManager ? fill(shape.folded ? TEAM_SHOW : TEAM_HIDE, name) : '',
            teamText: isManager ? fill(shape.folded ? TEAM : TEAM_COUNTS, shape.teamSize) : '',
            editable,
            inputLabel: fill(INPUT_LABEL, name),
            inputValue: editKey in this.typed ? this.typed[editKey] : inputText(value),
            targetClass: `tgt${this.wideTargets ? ' wide' : ''}${changed ? ' editing' : ''}${invalid ? ' invalid' : ''}`,
            targetText: isBlank(value) ? NONE : formatNumber(value),
            hint,
            hasHint: hint !== '',
            hintTitle,
            wasText: changed ? fill(WAS, isBlank(person.target) ? NONE : formatNumber(person.target)) : '',
            showWas: changed,
            showUseDefault: editable && personal && !toDefault,
            invalid,
            invalidText: INVALID,
            actualText: isBlank(person.actual) ? NONE : formatNumber(person.actual),
            hasResult,
            resultText: hasResult ? person.result : NONE,
            resultClass: `pill ${person.resultTone || 'grey'}`,
            currentText: isBlank(person.currentRate) ? NONE : formatPercent(person.currentRate),
            exceedText: isBlank(person.exceedRate) ? NONE : formatPercent(person.exceedRate),
            fromText: formatDate(fromDate) || NONE
        };
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get emptyText() {
        return this.table.message || EMPTY;
    }

    handleToggleTeam(event) {
        const key = event.currentTarget.dataset.key;
        this.collapsed = Object.assign({}, this.collapsed, { [key]: this.collapsed[key] !== true });
    }

    // ------------------------------------------------------------ editing

    handleTarget(event) {
        const key = event.currentTarget.dataset.key;
        const person = this.people[key];
        if (!person || person.canEdit !== true) {
            return;
        }
        const raw = event.detail && event.detail.value !== undefined ? event.detail.value : event.target.value;
        const text = isBlank(raw) ? '' : String(raw);
        const typedAmount = toNumber(text);
        const amount = typedAmount === null ? null : rounded(typedAmount);
        const edits = Object.assign({}, this.edits);
        if (amount === null || amount < 0) {
            edits[key] = { invalid: true };
        } else if (sameNumber(amount, person.target)) {
            // Back at what is in force: no change
            delete edits[key];
        } else {
            edits[key] = { target: amount };
        }
        this.edits = edits;
        this.typed = Object.assign({}, this.typed, { [key]: text });
        this.formError = '';
    }

    // A personal target goes back to the default of the configuration
    handleUseDefault(event) {
        const key = event.currentTarget.dataset.key;
        const person = this.people[key];
        if (!person || person.canEdit !== true || person.isDefault !== false) {
            return;
        }
        this.edits = Object.assign({}, this.edits, { [key]: { target: null } });
        // The box shows the default again, not what was typed before
        const typed = Object.assign({}, this.typed);
        delete typed[key];
        this.typed = typed;
        this.formError = '';
    }

    get hasEdits() {
        return Object.keys(this.edits).length > 0;
    }

    // For the tab: whether leaving this view would drop something typed
    @api
    get hasUnsavedChanges() {
        return this.hasEdits;
    }

    get hasInvalid() {
        return Object.keys(this.edits).some((key) => this.edits[key].invalid === true);
    }

    // The changes to save, in the order of the table
    get changes() {
        return Object.keys(this.people)
            .filter((key) => this.edits[key] && this.edits[key].invalid !== true)
            .map((key) => {
                const person = this.people[key];
                const toDefault = this.edits[key].target === null;
                return {
                    userId: person.userId,
                    designation: person.designation,
                    target: this.edits[key].target,
                    name: person.name || '',
                    before: person.target,
                    after: toDefault ? person.defaultTarget : this.edits[key].target,
                    toDefault
                };
            });
    }

    get changeCountText() {
        const count = this.changes.length;
        return count === 1 ? CHANGE_ONE : fill(CHANGES, count);
    }

    // "Advisor 2: 10 → 12", and how many more
    get changeDetailText() {
        const changes = this.changes;
        if (changes.length === 0) {
            return '';
        }
        const first = changes[0];
        const show = (value) => (isBlank(value) ? NONE : formatNumber(value));
        const line = fill(first.toDefault ? CHANGE_LINE_DEFAULT : CHANGE_LINE, first.name, show(first.before), show(first.after));
        return changes.length === 1 ? line : fill(TWO_PARTS, line, fill(MORE, changes.length - 1));
    }

    get saveDisabled() {
        return this.saving || this.changes.length === 0 || this.hasInvalid;
    }

    get hasFormError() {
        return this.formError !== '';
    }

    handleFrom(event) {
        this.effectiveFrom = event.detail && event.detail.value !== undefined ? event.detail.value : event.target.value;
        this.formError = '';
    }

    handleReason(event) {
        this.reason = event.detail && event.detail.value !== undefined ? event.detail.value : event.target.value;
        this.formError = '';
    }

    handleCancel() {
        this.edits = {};
        this.typed = {};
        this.reason = '';
        this.formError = '';
        this.actionError = '';
    }

    async handleSave() {
        if (this.saving) {
            return;
        }
        const changes = this.changes;
        const reason = isBlank(this.reason) ? '' : String(this.reason).trim();
        if (this.hasInvalid) {
            this.formError = FIX_FIRST;
            return;
        }
        if (changes.length === 0) {
            return;
        }
        if (isBlank(this.effectiveFrom)) {
            this.formError = FROM_REQUIRED;
            return;
        }
        if (reason === '') {
            this.formError = REASON_REQUIRED;
            const box = this.template.querySelector('[data-id="reason"]');
            if (box && typeof box.focus === 'function') {
                box.focus();
            }
            return;
        }
        this.saving = true;
        this.formError = '';
        this.actionError = '';
        try {
            const table = await saveTargets({
                payload: JSON.stringify({
                    projectId: this.table.projectId,
                    reference: this.table.reference,
                    effectiveFrom: this.effectiveFrom,
                    reason,
                    changes: changes.map((change) => ({ userId: change.userId, designation: change.designation, target: change.target }))
                })
            });
            if (table) {
                this.applyTable(table);
            } else {
                this.edits = {};
                this.typed = {};
                this.fetch(this.table.projectId, this.table.reference);
            }
            this.dispatchEvent(new ShowToastEvent({ title: SAVED, variant: 'success' }));
        } catch (error) {
            this.actionError = errorText(error, ERROR);
        } finally {
            this.saving = false;
        }
    }

    handleRetry() {
        this.fetch(null, null);
    }
}