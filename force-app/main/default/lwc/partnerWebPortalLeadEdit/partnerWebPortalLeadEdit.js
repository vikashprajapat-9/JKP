import { LightningElement, api } from 'lwc';
import getEditOptions from '@salesforce/apex/partnerWebPortalLeadEditController.getEditOptions';
import saveStatus from '@salesforce/apex/partnerWebPortalLeadEditController.saveStatus';
import markNotVisited from '@salesforce/apex/partnerWebPortalLeadEditController.markNotVisited';
import requestGracePeriod from '@salesforce/apex/partnerWebPortalLeadEditController.requestGracePeriod';

const LABELS = {
    HANDOVER: 'After this update John Keells Properties takes this lead over, and you will see it read-only.',
    FIELD_REQUIRED: '{0} is required.',
    CALL_IN_FUTURE: 'The call date and time cannot be in the future.',
    FOLLOW_UP_PAST: 'The follow-up date and time must be in the future.',
    NUMBER_INVALID: '{0} must be a number greater than 0.',
    EDIT_FAILED: 'The lead could not be updated right now. Please try again or contact the JKP CP team.',
    VISIT_DATE_PAST: 'Choose today or a later date for the visit.',
    CHOOSE_VISIT: 'Choose the visit that took place.',
    GRACE_BUTTON: 'Request more time',
    GRACE_DAYS_LABEL: 'More days needed',
    GRACE_REASON_LABEL: 'Reason',
    GRACE_SEND: 'Send request',
    GRACE_DAYS_OPTION: '{0} days',
    GRACE_DAYS_MISSING: 'Choose how many more days you need.',
    GRACE_REASON_MISSING: 'Enter why you need more time.',
    NOT_VISITED_BUTTON: 'Customer did not visit',
    NOT_VISITED_CONFIRM: 'Mark this visit as Not Visited? You can then request a new site visit for this lead.',
    PROJECT_HINT: 'Site visits are for the project the lead was created for.',
    PROJECT_CHOOSE_HINT: 'This lead has no project, so choose the project for the visit.',
    OPTIONAL: 'Optional',
    OPTIONAL_NOTE: 'Fill in what you know: you can save without these details.',
    CALL_LOG_NOTE: 'Fill this in only to record the call: left empty, no call log is saved.',
    NOTHING_TO_LOG: 'Fill in the call details to log another call.',
    NO_ANSWER: 'We could not reach John Keells Properties. Please check your internet connection and try again.',
    NOT_SAVED: 'Your update was not saved: we got no answer from John Keells Properties. Please check your internet connection and try again.',
    SAVED_AFTER_DROP: 'The connection was interrupted for a moment, but your update was saved.',
    CHECKING: 'No answer from John Keells Properties yet. Checking whether your update was saved…',
    CHECKING_SHORT: 'Checking…'
};

const CALL_DATE_TIME = 'callDateTime';
const FOLLOW_UP_DATE_TIME = 'followUpDateTime';
const SUBJECT = 'subject';
const DESCRIPTION = 'description';
// A site visit stage's values (PartnerSiteVisitService)
const VISIT_REQUEST = 'Request';
const VISIT_COMPLETE = 'Complete';
const VISIT_PROJECT = 'visitProjectId';
const VISIT_REQUIREMENT_TYPE = 'visitRequirementType';
const VISIT_DATE = 'visitDate';
const VISIT_TIME = 'visitTime';
const VISIT_DESCRIPTION = 'visitDescription';
const VISIT_ID = 'visitId';

// The next full hour ("16:00" at 15:20), a time still ahead for a visit today; 10:00 late at night (the visit is then
// for another day)
function nextHour() {
    const hour = new Date().getHours() + 1;
    return hour > 23 ? '10:00' : String(hour).padStart(2, '0') + ':00';
}

// "2026-10-06T14:05" for a datetime-local input, in the browser's time zone
function localDateTime(date) {
    const pad = (n) => String(n).padStart(2, '0');
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

function format(template, value) {
    return template.replace('{0}', value);
}

// How the platform words a request that got no readable answer: the partner's connection dropped, or the server sent
// an error page instead of data. A refusal by the portal's own Apex always comes with its own message.
const NO_ANSWER_TEXTS = ['failed to get error from response', 'failed to fetch', 'networkerror', 'load failed', 'error fetching component'];
// After a change without an answer the lead is read again: first after a short wait (the server may still be saving
// it), then as often as RECHECK_TRIES while the server does not answer
const RECHECK_FIRST_WAIT = 1500;
const RECHECK_WAIT = 3000;
const RECHECK_TRIES = 6;
// A dropping connection can also leave a request hanging instead of failing: after this long it counts as unanswered
const SEND_TIMEOUT = 30000;
const LOOK_TIMEOUT = 8000;

function isNoAnswer(error) {
    const text = String((error && error.body && error.body.message) || (error && error.message) || '').toLowerCase();
    return Boolean(error && error.unanswered) || NO_ANSWER_TEXTS.some((known) => text.includes(known));
}

// The request's own answer or refusal when it comes in time; otherwise a refusal that reads as "no answer"
function inTime(request, milliseconds) {
    let timer;
    const late = new Promise((resolve, reject) => {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        timer = setTimeout(() => reject(Object.assign(new Error('No answer in time'), { unanswered: true })), milliseconds);
    });
    return Promise.race([request, late]).finally(() => clearTimeout(timer));
}

function errorMessage(error) {
    if (isNoAnswer(error)) {
        return LABELS.NO_ANSWER;
    }
    if (error && error.body && error.body.message) {
        return error.body.message;
    }
    if (error && error.message) {
        return error.message;
    }
    return LABELS.EDIT_FAILED;
}

function wait(milliseconds) {
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

// What the lead shows once a change has arrived, for the look at the lead after a change that got no answer (send).
// Each reads the popup's own data, loaded again.
const stageIs = (stage) => (fresh) => fresh.currentStatus === stage;
// A site visit request now waits on the lead: its stage can no longer be chosen
const stageBlocked = (stage) => (fresh) => (fresh.statuses || []).some((status) => status.value === stage && Boolean(status.unavailableReason));
// The visit was marked (completed or not visited): it is no longer among the scheduled ones
const visitGone = (visitId) => (fresh) => Boolean(fresh.visit && fresh.visit.scheduled) && !fresh.visit.scheduled.some((visit) => visit.id === visitId);
const gracePending = (fresh) => Boolean(fresh.freeze && fresh.freeze.pending);
// Another call logged at the lead's own stage leaves nothing the popup can see
const neverSeen = () => false;

// The Edit popup of the Leads page: the partner chooses the lead's new stage, then fills what that stage needs (a call
// log, lead details, a site visit request, the visit that took place) and saves. Fires "saved" (detail: { message,
// status, handedToJkp, visitRequested }) or "close".
export default class PartnerWebPortalLeadEdit extends LightningElement {
    @api leadId;

    loading = true;
    saving = false;
    // Changes that got no answer from the server (the connection dropped), each as what the lead shows once it has
    // arrived: see send()
    unconfirmed = [];
    checking = false;
    // The popup was closed
    gone = false;
    options;
    selectedValue;
    values = {};
    errorMessage;
    scrollToError = false;
    // The Lead Freezing Window's grace period request, and Visited? No
    graceOpen = false;
    graceDays;
    graceReason = '';
    confirmNotVisited = false;
    labels = {
        handover: LABELS.HANDOVER,
        graceButton: LABELS.GRACE_BUTTON,
        graceDays: LABELS.GRACE_DAYS_LABEL,
        graceReason: LABELS.GRACE_REASON_LABEL,
        notVisitedButton: LABELS.NOT_VISITED_BUTTON,
        notVisitedConfirm: LABELS.NOT_VISITED_CONFIRM,
        projectHint: LABELS.PROJECT_HINT,
        projectChooseHint: LABELS.PROJECT_CHOOSE_HINT,
        optional: LABELS.OPTIONAL,
        optionalNote: LABELS.OPTIONAL_NOTE,
        callLogNote: LABELS.CALL_LOG_NOTE,
        checking: LABELS.CHECKING
    };

    connectedCallback() {
        this.load();
        this.keyHandler = (event) => {
            if (event.key === 'Escape' && !this.locked) {
                this.handleCancel();
            }
        };
        window.addEventListener('keydown', this.keyHandler);
    }

    disconnectedCallback() {
        this.gone = true;
        window.removeEventListener('keydown', this.keyHandler);
    }

    renderedCallback() {
        if (this.scrollToError) {
            const banner = this.template.querySelector('.error-banner');
            if (banner) {
                this.scrollToError = false;
                if (typeof banner.scrollIntoView === 'function') {
                    banner.scrollIntoView({ behavior: 'smooth', block: 'center' });
                }
                banner.focus();
            }
        }
    }

    async load() {
        this.loading = true;
        try {
            this.options = await getEditOptions({ leadId: this.leadId });
        } catch (error) {
            this.showError(errorMessage(error));
        } finally {
            this.loading = false;
        }
    }

    // ---------- what the popup shows ----------

    get leadName() {
        return this.options ? this.options.leadName : '';
    }

    get currentStatus() {
        return this.options ? this.options.currentStatus : '';
    }

    get projectName() {
        return this.options ? this.options.projectName : null;
    }

    get readOnly() {
        return Boolean(this.options) && !this.options.canEdit;
    }

    get readOnlyReason() {
        return this.options ? this.options.readOnlyReason : null;
    }

    get canEdit() {
        return Boolean(this.options) && this.options.canEdit;
    }

    get statusCards() {
        if (!this.options || !this.options.statuses) {
            return [];
        }
        return this.options.statuses.map((status) => {
            const selected = status.value === this.selectedValue;
            // The current stage can be chosen again only to log another call or visit
            const selectable = !status.current || status.repeatable;
            const unavailable = selectable && Boolean(status.unavailableReason);
            let className = 'status-card';
            if (selected) {
                className += ' status-card_selected';
            }
            if (!selectable) {
                className += ' status-card_current';
            }
            if (unavailable) {
                className += ' status-card_unavailable';
            }
            return {
                ...status,
                selected,
                unavailable,
                disabled: !selectable || unavailable,
                // An unavailable stage says why instead of what it is
                cardText: unavailable ? status.unavailableReason : status.description,
                ariaChecked: selected ? 'true' : 'false',
                className
            };
        });
    }

    get selected() {
        if (!this.options || !this.selectedValue) {
            return null;
        }
        return this.options.statuses.find((status) => status.value === this.selectedValue) || null;
    }

    get hasSelection() {
        return Boolean(this.selected);
    }

    get hasCallLog() {
        return Boolean(this.selected && this.selected.callDisposition);
    }

    get followUpRequired() {
        return Boolean(this.selected && this.selected.followUpRequired);
    }

    get handsOver() {
        return Boolean(this.selected && this.selected.ownerQueue);
    }

    // ---------- the lead freezing window ----------

    get freeze() {
        return this.options && this.options.freeze ? this.options.freeze : {};
    }

    get showFreeze() {
        return Boolean(this.freeze.inWindow);
    }

    get showGraceButton() {
        return Boolean(this.freeze.canRequest) && !this.graceOpen;
    }

    get graceDayOptions() {
        return (this.freeze.graceOptions || []).map((days) => {
            const selected = days === this.graceDays;
            return {
                value: String(days),
                label: format(LABELS.GRACE_DAYS_OPTION, days),
                ariaChecked: selected ? 'true' : 'false',
                className: selected ? 'day-chip day-chip_selected' : 'day-chip'
            };
        });
    }

    get graceSendLabel() {
        if (this.checking) {
            return LABELS.CHECKING_SHORT;
        }
        return this.saving ? 'Sending…' : LABELS.GRACE_SEND;
    }

    // ---------- site visits ----------

    get visitForm() {
        return this.options && this.options.visit ? this.options.visit : {};
    }

    get isVisitRequest() {
        return Boolean(this.selected) && this.selected.visitAction === VISIT_REQUEST;
    }

    get isVisitComplete() {
        return Boolean(this.selected) && this.selected.visitAction === VISIT_COMPLETE;
    }

    // A request is for the lead's project, shown read-only; only an old lead without a project chooses one of the
    // partner's projects (visitProjects), as before
    get visitProjectFromLead() {
        return Boolean(this.visitForm.projectFromLead);
    }

    get visitProjects() {
        return (this.visitForm.projects || []).map((option) => ({ ...option, selected: option.value === this.values[VISIT_PROJECT] }));
    }

    get visitRequirementTypes() {
        return (this.visitForm.requirementTypes || []).map((option) => ({
            ...option,
            selected: option.value === this.values[VISIT_REQUIREMENT_TYPE]
        }));
    }

    get visitDate() {
        return this.values[VISIT_DATE] || '';
    }

    get visitTime() {
        return this.values[VISIT_TIME] || '';
    }

    get visitDescription() {
        return this.values[VISIT_DESCRIPTION] || '';
    }

    get scheduledVisits() {
        return (this.visitForm.scheduled || []).map((visit) => {
            const selected = visit.id === this.values[VISIT_ID];
            let className = 'visit-option';
            if (selected) {
                className += ' visit-option_selected';
            }
            if (!visit.canComplete) {
                className += ' visit-option_later';
            }
            return { ...visit, selected, disabled: !visit.canComplete, ariaChecked: selected ? 'true' : 'false', className };
        });
    }

    // Visited? No: the chosen visit's day and time have come
    get canMarkNotVisited() {
        const visitId = this.values[VISIT_ID];
        return Boolean(visitId) && (this.visitForm.scheduled || []).some((visit) => visit.id === visitId && visit.canComplete);
    }

    get notVisitedLabel() {
        if (this.checking) {
            return LABELS.CHECKING_SHORT;
        }
        return this.saving ? 'Saving…' : 'Yes, not visited';
    }

    get leadFields() {
        if (!this.selected) {
            return [];
        }
        return this.selected.fields.map((field) => {
            const value = this.values[field.apiName];
            return {
                ...field,
                value,
                // Ties the field's label to its input
                inputId: 'leadField-' + field.apiName,
                isPicklist: field.type === 'picklist',
                isNumber: field.type === 'number',
                isTextarea: field.type === 'textarea',
                isText: field.type !== 'picklist' && field.type !== 'number' && field.type !== 'textarea',
                wrapClass: field.type === 'textarea' ? 'field field_wide' : 'field',
                choices: (field.options || []).map((option) => ({ ...option, selected: option.value === value }))
            };
        });
    }

    get hasLeadFields() {
        return this.leadFields.length > 0;
    }

    get showOtherLossReason() {
        return Boolean(this.selected) && this.selected.fields.some((field) => field.apiName === 'Loss_Reason__c')
            && this.values.Loss_Reason__c === this.options.otherLossReasonTrigger;
    }

    get otherLossReasonLabel() {
        return this.options && this.options.otherLossReason ? this.options.otherLossReason.label : '';
    }

    get otherLossReasonValue() {
        return this.values.Other_Loss_Reason__c || '';
    }

    get callDateTime() {
        return this.values[CALL_DATE_TIME] || '';
    }

    get followUpDateTime() {
        return this.values[FOLLOW_UP_DATE_TIME] || '';
    }

    get subject() {
        return this.values[SUBJECT] || '';
    }

    get description() {
        return this.values[DESCRIPTION] || '';
    }

    get nowLocal() {
        return localDateTime(new Date());
    }

    get subjectMaxLength() {
        return this.options && this.options.subjectMaxLength ? this.options.subjectMaxLength : 255;
    }

    get saveDisabled() {
        return !this.canEdit || !this.selected || this.saving;
    }

    // While a change is sent the popup stays; while it only looks whether the change arrived, the partner may leave
    get locked() {
        return this.saving && !this.checking;
    }

    get saveLabel() {
        if (this.checking) {
            return LABELS.CHECKING_SHORT;
        }
        if (this.saving) {
            return this.isVisitRequest ? 'Sending…' : 'Saving…';
        }
        if (this.isVisitRequest) {
            return 'Send request';
        }
        // The lead stays at its stage: another call is logged
        return this.selected && this.selected.current && this.selected.callDisposition ? 'Log call' : 'Update stage';
    }

    // ---------- events ----------

    handleSelect(event) {
        const value = event.currentTarget.dataset.value;
        const status = this.options.statuses.find((option) => option.value === value);
        if (!status || (status.current && !status.repeatable) || status.unavailableReason) {
            return;
        }
        this.selectedValue = value;
        this.errorMessage = undefined;
        this.confirmNotVisited = false;
        // The lead's current details, ready to change
        // The call log starts empty: it is saved only when the partner fills any of it
        const values = { [CALL_DATE_TIME]: '', [SUBJECT]: '' };
        status.fields.forEach((field) => {
            values[field.apiName] = field.value === null || field.value === undefined ? '' : field.value;
        });
        if (this.options.otherLossReason) {
            values.Other_Loss_Reason__c = this.options.otherLossReason.value || '';
        }
        // A request is for the lead's project, starting from its unit type; a completed visit from the first that can be
        const form = this.visitForm;
        values[VISIT_PROJECT] = form.projectId || '';
        values[VISIT_REQUIREMENT_TYPE] = form.requirementType || '';
        values[VISIT_DATE] = '';
        values[VISIT_TIME] = nextHour();
        values[VISIT_DESCRIPTION] = '';
        const first = (form.scheduled || []).find((visit) => visit.canComplete);
        values[VISIT_ID] = first ? first.id : '';
        this.values = values;
    }

    handleVisitChoice(event) {
        const visitId = event.currentTarget.dataset.id;
        const visit = (this.visitForm.scheduled || []).find((option) => option.id === visitId);
        if (visit && visit.canComplete) {
            this.values = { ...this.values, [VISIT_ID]: visitId };
            this.errorMessage = undefined;
            this.confirmNotVisited = false;
        }
    }

    handleNotVisited() {
        this.confirmNotVisited = true;
        this.errorMessage = undefined;
    }

    handleNotVisitedBack() {
        this.confirmNotVisited = false;
    }

    async handleNotVisitedConfirm() {
        if (!this.values[VISIT_ID]) {
            this.showError(LABELS.CHOOSE_VISIT);
            return;
        }
        const visitId = this.values[VISIT_ID];
        await this.send(() => markNotVisited({ leadId: this.leadId, visitId }), visitGone(visitId));
        this.confirmNotVisited = false;
    }

    handleGraceOpen() {
        this.graceOpen = true;
        this.errorMessage = undefined;
        const options = this.freeze.graceOptions || [];
        this.graceDays = options.length === 1 ? options[0] : undefined;
    }

    handleGraceCancel() {
        this.graceOpen = false;
        this.graceReason = '';
        this.graceDays = undefined;
    }

    handleGraceDays(event) {
        this.graceDays = Number(event.currentTarget.dataset.value);
    }

    handleGraceReason(event) {
        this.graceReason = event.target.value;
    }

    async handleGraceSend() {
        if (!this.graceDays) {
            this.showError(LABELS.GRACE_DAYS_MISSING);
            return;
        }
        if (!String(this.graceReason || '').trim()) {
            this.showError(LABELS.GRACE_REASON_MISSING);
            return;
        }
        const days = this.graceDays;
        const reason = this.graceReason.trim();
        await this.send(() => requestGracePeriod({ leadId: this.leadId, days, reason }), gracePending);
    }

    handleInput(event) {
        const field = event.target.dataset.field;
        this.values = { ...this.values, [field]: event.target.value };
    }

    // Not while a change is sent: it would finish unseen
    handleCancel() {
        if (this.locked) {
            return;
        }
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleBackdrop() {
        if (!this.locked) {
            this.handleCancel();
        }
    }

    handleCloseError() {
        this.errorMessage = undefined;
    }

    async handleSave() {
        const problem = this.validate();
        if (problem) {
            this.showError(problem);
            return;
        }
        const status = this.selectedValue;
        const values = this.payload();
        await this.send(() => saveStatus({ leadId: this.leadId, status, values }), this.arrivedIf(status, values));
    }

    // What the lead shows once this change of stage has arrived
    arrivedIf(status, values) {
        if (this.isVisitRequest) {
            return stageBlocked(status);
        }
        const moved = this.selected.current ? neverSeen : stageIs(status);
        if (this.isVisitComplete) {
            const marked = visitGone(values[VISIT_ID]);
            return (fresh) => moved(fresh) || marked(fresh);
        }
        return moved;
    }

    // ---------- a change that gets no answer ----------

    // Sends a change of the lead to the server. With no answer (the partner's connection dropped, or the server sent an
    // error page) the change may or may not have arrived, so the lead is read again once the server answers, and tells
    // which (arrivedIf: what the lead shows once the change has arrived). Arrived, the popup closes as saved; not
    // arrived, the partner is told to try again. Until a change is answered or seen on the lead, every try starts with
    // that look: a change is never sent twice blindly.
    async send(request, arrivedIf) {
        this.saving = true;
        this.errorMessage = undefined;
        try {
            // An earlier try that never got its answer may have arrived meanwhile
            if (this.unconfirmed.length && (await this.arrived(1, 0))) {
                return;
            }
            const result = await inTime(request(), SEND_TIMEOUT);
            this.unconfirmed = [];
            this.dispatchEvent(new CustomEvent('saved', { detail: { ...result } }));
        } catch (error) {
            if (this.gone) {
                return;
            }
            if (isNoAnswer(error)) {
                if (!this.unconfirmed.includes(arrivedIf)) {
                    this.unconfirmed = [...this.unconfirmed, arrivedIf];
                }
                await this.afterNoAnswer();
            } else {
                this.showError(errorMessage(error));
            }
        } finally {
            this.saving = false;
            this.checking = false;
        }
    }

    async afterNoAnswer() {
        this.checking = true;
        try {
            if (!(await this.arrived(RECHECK_TRIES, RECHECK_FIRST_WAIT)) && !this.gone) {
                this.showError(LABELS.NOT_SAVED);
            }
        } catch (error) {
            // Still no answer (or the lead cannot be read): the next try starts with the same look at the lead
            if (!this.gone) {
                this.showError(errorMessage(error));
            }
        } finally {
            this.checking = false;
        }
    }

    // Whether a change without an answer arrived after all: reads the lead (again while the server does not answer, up
    // to the number of tries) and looks for what each such change leaves on it. Arrived: the popup closes as saved.
    async arrived(tries, firstWait) {
        let fresh;
        for (let attempt = 1; fresh === undefined; attempt++) {
            const pause = attempt === 1 ? firstWait : RECHECK_WAIT;
            if (pause) {
                // eslint-disable-next-line no-await-in-loop
                await wait(pause);
            }
            if (this.gone) {
                return false;
            }
            try {
                // eslint-disable-next-line no-await-in-loop
                fresh = await inTime(getEditOptions({ leadId: this.leadId }), LOOK_TIMEOUT);
            } catch (error) {
                if (!isNoAnswer(error) || attempt >= tries) {
                    throw error;
                }
            }
        }
        if (this.gone || !this.unconfirmed.some((arrivedIf) => arrivedIf(fresh))) {
            return false;
        }
        this.unconfirmed = [];
        this.dispatchEvent(new CustomEvent('saved', {
            detail: { status: fresh.currentStatus, message: LABELS.SAVED_AFTER_DROP, handedToJkp: !fresh.canEdit, visitRequested: false }
        }));
        return true;
    }

    // ---------- checks and what is sent ----------

    // The first value that is wrong, in the popup's order (the call log or the site visit, then the lead details below
    // them); null when the form can be saved. The call log and the lead details are optional (a channel partner may
    // change the stage without them); a site visit request needs its details, and Visited the visit.
    validate() {
        const status = this.selected;
        if (!status) {
            return null;
        }
        const problem = this.validateStage(status);
        if (problem) {
            return problem;
        }
        for (const field of status.fields) {
            const value = String(this.values[field.apiName] || '').trim();
            if (value && field.type === 'number' && !(Number(value) > 0)) {
                return format(LABELS.NUMBER_INVALID, field.label);
            }
        }
        return null;
    }

    // What the stage itself takes: a site visit request its details, Visited the visit, a call log's times when given
    validateStage(status) {
        if (this.isVisitRequest) {
            return this.validateVisitRequest();
        }
        if (this.isVisitComplete) {
            return this.values[VISIT_ID] ? null : LABELS.CHOOSE_VISIT;
        }
        if (status.callDisposition) {
            if (this.values[CALL_DATE_TIME] && new Date(this.values[CALL_DATE_TIME]).getTime() > Date.now() + 5 * 60 * 1000) {
                return LABELS.CALL_IN_FUTURE;
            }
            if (status.followUpRequired && this.values[FOLLOW_UP_DATE_TIME]
                    && new Date(this.values[FOLLOW_UP_DATE_TIME]).getTime() <= Date.now()) {
                return LABELS.FOLLOW_UP_PAST;
            }
            // Choosing the current stage again only logs another call: with nothing filled in there is nothing to save
            if (status.current && !this.callLogFilled() && !this.leadDetailsChanged()) {
                return LABELS.NOTHING_TO_LOG;
            }
        }
        return null;
    }

    // Whether the partner filled in any of the call log (only then is one saved)
    callLogFilled() {
        return [CALL_DATE_TIME, SUBJECT, DESCRIPTION, FOLLOW_UP_DATE_TIME].some((key) => String(this.values[key] || '').trim() !== '');
    }

    // Whether the partner changed any of the lead details shown
    leadDetailsChanged() {
        const status = this.selected;
        const changed = (status ? status.fields : []).some((field) =>
            String(this.values[field.apiName] || '').trim() !== String(field.value === null || field.value === undefined ? '' : field.value).trim());
        const other = this.options && this.options.otherLossReason ? this.options.otherLossReason.value || '' : '';
        return changed || (this.showOtherLossReason && String(this.values.Other_Loss_Reason__c || '').trim() !== String(other).trim());
    }

    validateVisitRequest() {
        const form = this.visitForm;
        if (!this.values[VISIT_PROJECT]) {
            return format(LABELS.FIELD_REQUIRED, form.projectLabel);
        }
        if (!this.values[VISIT_REQUIREMENT_TYPE]) {
            return format(LABELS.FIELD_REQUIRED, form.requirementTypeLabel);
        }
        if (!this.values[VISIT_DATE]) {
            return format(LABELS.FIELD_REQUIRED, form.dateLabel);
        }
        // yyyy-mm-dd strings compare as dates
        if (form.today && this.values[VISIT_DATE] < form.today) {
            return LABELS.VISIT_DATE_PAST;
        }
        if (!this.values[VISIT_TIME]) {
            return format(LABELS.FIELD_REQUIRED, form.timeLabel);
        }
        return null;
    }

    // The values sent: the lead details (empty ones change nothing on the lead) with the stage's own values
    payload() {
        const status = this.selected;
        const payload = {};
        status.fields.forEach((field) => {
            payload[field.apiName] = String(this.values[field.apiName] || '').trim();
        });
        if (this.showOtherLossReason) {
            payload.Other_Loss_Reason__c = String(this.values.Other_Loss_Reason__c || '').trim();
        }
        if (this.isVisitRequest) {
            return {
                ...payload,
                [VISIT_PROJECT]: this.values[VISIT_PROJECT],
                [VISIT_REQUIREMENT_TYPE]: this.values[VISIT_REQUIREMENT_TYPE],
                [VISIT_DATE]: this.values[VISIT_DATE],
                [VISIT_TIME]: this.values[VISIT_TIME],
                [VISIT_DESCRIPTION]: String(this.values[VISIT_DESCRIPTION] || '').trim()
            };
        }
        if (this.isVisitComplete) {
            return { ...payload, [VISIT_ID]: this.values[VISIT_ID] };
        }
        if (status.callDisposition) {
            // Left empty, no call log is saved
            if (this.values[CALL_DATE_TIME]) {
                payload[CALL_DATE_TIME] = new Date(this.values[CALL_DATE_TIME]).toISOString();
            }
            payload[SUBJECT] = String(this.values[SUBJECT] || '').trim();
            payload[DESCRIPTION] = String(this.values[DESCRIPTION] || '').trim();
            if (status.followUpRequired && this.values[FOLLOW_UP_DATE_TIME]) {
                payload[FOLLOW_UP_DATE_TIME] = new Date(this.values[FOLLOW_UP_DATE_TIME]).toISOString();
            }
        }
        return payload;
    }

    showError(message) {
        this.errorMessage = message;
        this.scrollToError = true;
    }
}