import { LightningElement } from 'lwc';
import getAccessStatus from '@salesforce/apex/partnerWebPortalAccessController.getAccessStatus';
import requestExtension from '@salesforce/apex/partnerWebPortalAccessController.requestExtension';

const REASON_MAX_LENGTH = 1000;
// From this many days left the notice turns amber
const SOON_DAYS = 7;
// How long the confirmation stays once a request is sent
const NOTICE_MS = 8000;
const TEMPORARY = 'Temporary';
const SAVE_ERROR = 'Your extension request could not be sent right now. Please try again.';
const SENT_NOTICE = 'Your extension request has been sent to the JKP CP team for approval.';
const FIELDS = ['days', 'reason'];
const MISSING = {
    days: 'Choose an extension period.',
    reason: 'Enter the reason for your request.'
};
const TOO_LONG = `Use ${REASON_MAX_LENGTH} characters or fewer.`;
// What Tab moves between inside the dialog
const DIALOG_FOCUSABLE = '.modal button:not([disabled]), .modal select:not([disabled]), .modal textarea:not([disabled])';
// Spaces of any kind at either end, including zero-width ones, which JavaScript's trim() keeps (Salesforce removes them too)
const EDGE_SPACES = /^[\s\u200B-\u200D\u2060]+|[\s\u200B-\u200D\u2060]+$/g;

// A value as Salesforce checks and saves it: without spaces of any kind at its ends
function cleanText(value) {
    return (value || '').replace(EDGE_SPACES, '');
}

function errorMessage(error, fallback) {
    return (error && error.body && error.body.message) || fallback;
}

function daysText(days) {
    return days === 1 ? '1 day' : `${days} days`;
}

// The notice above every portal page about the partner's access period (worded by Salesforce), with the extension
// request: the partner picks a period and gives a reason, and the CP Manager approves it. Once sent, the notice says the
// request is waiting. Nothing shows when Salesforce has nothing to say, or when the status cannot be read.
export default class PartnerWebPortalAccessBanner extends LightningElement {
    // The controller's AccessStatus, or undefined until it arrives (or when it could not be read)
    status;
    isModalOpen = false;
    form = { days: '', reason: '' };
    touched = {};
    submitAttempted = false;
    isSaving = false;
    modalError;
    // The confirmation shown for a while once a request is sent
    notice;
    noticeTimer;
    // Element to focus after the next render
    pendingFocus;

    connectedCallback() {
        this.onKeyDown = this.handleKeyDown.bind(this);
        this.loadStatus();
    }

    disconnectedCallback() {
        window.removeEventListener('keydown', this.onKeyDown);
        window.clearTimeout(this.noticeTimer);
    }

    renderedCallback() {
        // The select shows the chosen period: option selected= alone is not followed once the partner has picked by hand
        const select = this.isModalOpen ? this.template.querySelector('select[data-field="days"]') : null;
        if (select && select.value !== this.form.days) {
            select.value = this.form.days;
        }
        if (this.pendingFocus) {
            const target = this.template.querySelector(this.pendingFocus);
            this.pendingFocus = undefined;
            if (target) {
                target.focus();
            }
        }
    }

    // Read when the portal opens: the access period and any request change outside the portal. Only a notice: every page
    // works without it, so a status that cannot be read shows nothing.
    loadStatus() {
        return getAccessStatus()
            .then((status) => {
                this.status = status || undefined;
            })
            .catch(() => {
                this.status = undefined;
            });
    }

    // ================= NOTICE =================
    get showBanner() {
        return Boolean(this.status && this.status.message);
    }

    get message() {
        return this.status ? this.status.message : '';
    }

    get isPending() {
        return Boolean(this.status) && this.status.pending === true;
    }

    // The periods the partner may ask for, in days
    get extensionDays() {
        const options = (this.status && this.status.options) || [];
        return options.map(Number).filter((days) => Number.isInteger(days) && days > 0);
    }

    get canRequest() {
        return Boolean(this.status) && this.status.canRequest === true && !this.isPending && this.extensionDays.length > 0;
    }

    get daysLeft() {
        const days = this.status ? this.status.daysLeft : null;
        return days === null || days === undefined ? null : Number(days);
    }

    // Calm while there is time, amber in the last days, red once the access has ended; a waiting request is calm again
    get tone() {
        if (this.isPending) {
            return 'pending';
        }
        const days = this.daysLeft;
        if (days === null || Number.isNaN(days)) {
            return 'info';
        }
        if (days < 0) {
            return 'ended';
        }
        return days <= SOON_DAYS ? 'soon' : 'info';
    }

    get bannerClass() {
        return `access-banner access-banner_${this.tone}`;
    }

    get isInfoTone() {
        return this.tone === 'info';
    }

    get isSoonTone() {
        return this.tone === 'soon';
    }

    get isEndedTone() {
        return this.tone === 'ended';
    }

    get bannerLabel() {
        if (this.tone === 'pending') {
            return 'Extension requested';
        }
        if (this.tone === 'ended') {
            return 'Access ended';
        }
        return this.status && this.status.partnerType === TEMPORARY ? 'Temporary access' : 'Portal access';
    }

    get areaClass() {
        return this.showBanner || this.notice ? 'access-area access-area_shown' : 'access-area';
    }

    // ================= DIALOG =================
    get modalIntro() {
        const end = this.status && this.status.accessEnd;
        const when = end ? `Your portal access ${this.tone === 'ended' ? 'ended' : 'ends'} on ${end}. ` : '';
        return `${when}Choose how much more time you need and tell us why. The JKP CP team will review your request.`;
    }

    get dayOptions() {
        return this.extensionDays.map((days) => ({
            value: String(days),
            label: daysText(days),
            selected: String(days) === this.form.days
        }));
    }

    get noDaysChosen() {
        return !this.form.days;
    }

    // What is wrong with a field's value, if anything
    errorOf(field) {
        if (field === 'days') {
            return this.extensionDays.includes(Number(this.form.days)) ? '' : MISSING.days;
        }
        const reason = cleanText(this.form.reason);
        if (!reason) {
            return MISSING.reason;
        }
        return reason.length > REASON_MAX_LENGTH ? TOO_LONG : '';
    }

    // Shown once the field is left or Submit is pressed
    shownErrorOf(field) {
        return this.touched[field] || this.submitAttempted ? this.errorOf(field) : '';
    }

    get daysError() {
        return this.shownErrorOf('days');
    }

    get reasonError() {
        return this.shownErrorOf('reason');
    }

    // Muted while it still shows "Select a period", red when that is wrong
    get daysClass() {
        let css = 'field-input field-select';
        if (!this.form.days) {
            css += ' field-select_placeholder';
        }
        return this.daysError ? `${css} invalid` : css;
    }

    get reasonClass() {
        return this.reasonError ? 'field-input field-textarea invalid' : 'field-input field-textarea';
    }

    get daysInvalid() {
        return String(Boolean(this.daysError));
    }

    get reasonInvalid() {
        return String(Boolean(this.reasonError));
    }

    get reasonMaxLength() {
        return REASON_MAX_LENGTH;
    }

    get reasonCount() {
        return `${this.form.reason.length} / ${REASON_MAX_LENGTH}`;
    }

    get busyState() {
        return String(this.isSaving);
    }

    // ================= HANDLERS =================
    handleOpen() {
        const days = this.extensionDays;
        // A single period needs no choosing
        this.form = { days: days.length === 1 ? String(days[0]) : '', reason: '' };
        this.touched = {};
        this.submitAttempted = false;
        this.modalError = undefined;
        this.isModalOpen = true;
        this.pendingFocus = days.length === 1 ? '[data-field="reason"]' : '[data-field="days"]';
        window.removeEventListener('keydown', this.onKeyDown);
        window.addEventListener('keydown', this.onKeyDown);
    }

    closeModal() {
        this.isModalOpen = false;
        window.removeEventListener('keydown', this.onKeyDown);
    }

    handleCancel() {
        if (this.isSaving) {
            return;
        }
        this.closeModal();
        this.pendingFocus = '.request-btn';
    }

    handleDaysChange(event) {
        this.form = { ...this.form, days: event.target.value };
        this.modalError = undefined;
    }

    handleReasonInput(event) {
        this.form = { ...this.form, reason: event.target.value };
        this.modalError = undefined;
    }

    handleBlur(event) {
        this.touched = { ...this.touched, [event.target.dataset.field]: true };
    }

    // Keeps the cursor in the field while a footer button is pressed: leaving an empty field shows its message, which
    // would move the button away before the click lands
    keepFocus(event) {
        event.preventDefault();
    }

    handleKeyDown(event) {
        if (!this.isModalOpen) {
            return;
        }
        if (event.key === 'Escape') {
            this.handleCancel();
        } else if (event.key === 'Tab') {
            this.trapFocus(event);
        }
    }

    // Tab and Shift+Tab stay inside the dialog while it is open
    trapFocus(event) {
        const items = Array.from(this.template.querySelectorAll(DIALOG_FOCUSABLE));
        if (!items.length) {
            return;
        }
        const first = items[0];
        const last = items[items.length - 1];
        const active = this.template.activeElement;
        const inside = items.includes(active);
        if (event.shiftKey && (active === first || !inside)) {
            event.preventDefault();
            last.focus();
        } else if (!event.shiftKey && (active === last || !inside)) {
            event.preventDefault();
            first.focus();
        }
    }

    // Sends the request; Salesforce answers with the new status, which shows the request as waiting
    async handleSubmit() {
        if (this.isSaving) {
            return;
        }
        this.submitAttempted = true;
        this.modalError = undefined;
        const invalid = FIELDS.find((field) => this.errorOf(field));
        if (invalid) {
            const target = this.template.querySelector(`[data-field="${invalid}"]`);
            if (target) {
                target.focus();
            }
            return;
        }
        this.isSaving = true;
        try {
            const status = await requestExtension({
                days: Number(this.form.days),
                reason: cleanText(this.form.reason)
            });
            this.closeModal();
            if (status) {
                this.status = status;
            } else {
                this.loadStatus();
            }
            this.showNotice();
        } catch (error) {
            this.modalError = errorMessage(error, SAVE_ERROR);
        } finally {
            this.isSaving = false;
        }
    }

    showNotice() {
        window.clearTimeout(this.noticeTimer);
        this.notice = SENT_NOTICE;
        // The request button is gone: the notice (now saying the request waits) takes the focus
        this.pendingFocus = '.access-banner, .sent-notice';
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.noticeTimer = window.setTimeout(() => {
            this.notice = undefined;
        }, NOTICE_MS);
    }

    handleCloseNotice() {
        window.clearTimeout(this.noticeTimer);
        this.notice = undefined;
        this.pendingFocus = '.access-banner';
    }
}