import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { RefreshEvent } from 'lightning/refresh';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getTerminationInfo from '@salesforce/apex/PartnerAccessRequestService.getTerminationInfo';
import requestTermination from '@salesforce/apex/PartnerAccessRequestService.requestTermination';
import FOLLOWS_HEAD from '@salesforce/label/c.Partner_Access_Termination_Follows_Head';

const REASON_MAX_LENGTH = 1000;
const LOAD_ERROR = "The partner's details could not be loaded. Close this window and try again.";
const SUBMIT_ERROR = 'The termination request could not be submitted. Please try again.';
const SUBMITTED = 'The termination request was submitted for approval.';

// Salesforce's message: an AuraHandledException's text, or the page and field errors of a failed save
function messageOf(error, fallback) {
    const body = error && error.body;
    if (body) {
        if (typeof body.message === 'string' && body.message) {
            return body.message;
        }
        const errors = Array.isArray(body) ? body : body.pageErrors;
        if (Array.isArray(errors) && errors.length) {
            return errors.map((item) => item.message).filter(Boolean).join(' ') || fallback;
        }
    }
    return (error && error.message) || fallback;
}

// Request Termination on a Channel Partner account: the CP Manager gives a reason and the request goes to the CP Head
// for approval (PartnerAccessRequestService). Salesforce says whether a request can be made, and what it does; a channel
// head's executives lose their access with them.
export default class PartnerAccessTermination extends LightningElement {
    // The service's TerminationInfo, once loaded
    info;
    reason = '';
    isLoading = true;
    isSaving = false;
    error;
    _recordId;
    loadedFor;

    // A quick action gets its record Id after it is created, not always before connectedCallback: the details load once
    // it arrives
    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        this._recordId = value;
        if (value && value !== this.loadedFor) {
            this.loadedFor = value;
            this.loadInfo();
        }
    }

    async loadInfo() {
        this.isLoading = true;
        this.error = undefined;
        try {
            const info = await getTerminationInfo({ accountId: this._recordId });
            if (!info) {
                throw new Error(LOAD_ERROR);
            }
            this.info = info;
        } catch (error) {
            this.info = undefined;
            this.error = messageOf(error, LOAD_ERROR);
        } finally {
            this.isLoading = false;
        }
    }

    get hasInfo() {
        return !this.isLoading && Boolean(this.info);
    }

    get accountName() {
        return this.info ? this.info.accountName : '';
    }

    // An executive (an account with a channel head) has no Partner Type of its own: its access follows the head's.
    // Without an account name the account was not found, and nothing is known about it.
    get isExecutive() {
        return Boolean(this.info) && Boolean(this.info.accountName) && this.info.isChannelHead === false;
    }

    get partnerTypeLabel() {
        if (this.info && this.info.partnerType) {
            return this.info.partnerType;
        }
        return this.isExecutive ? FOLLOWS_HEAD : 'Not set';
    }

    get roleLabel() {
        if (this.isExecutive) {
            return 'Executive';
        }
        return this.info && this.info.isChannelHead === true ? 'Channel Head' : null;
    }

    get message() {
        return this.info ? this.info.message : '';
    }

    get canRequest() {
        return Boolean(this.info) && this.info.canRequest === true;
    }

    // Information when the request can be made; a warning when it cannot (the message says why)
    get messageIcon() {
        return this.canRequest ? 'utility:info' : 'utility:warning';
    }

    get messageIconVariant() {
        return this.canRequest ? undefined : 'warning';
    }

    get messageIconText() {
        return this.canRequest ? 'Information' : 'Warning';
    }

    get executiveCount() {
        return (this.info && Number(this.info.executiveCount)) || 0;
    }

    get showExecutives() {
        return Boolean(this.info) && this.info.isChannelHead === true && this.executiveCount > 0;
    }

    get executivesText() {
        const count = this.executiveCount;
        return `${count} ${count === 1 ? 'executive' : 'executives'} under this channel head will also lose portal access.`;
    }

    get reasonMaxLength() {
        return REASON_MAX_LENGTH;
    }

    get submitDisabled() {
        return !this.canRequest || !this.reason.trim() || this.isSaving || this.isLoading;
    }

    handleReasonChange(event) {
        this.reason = (event.detail && event.detail.value) || '';
        this.error = undefined;
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    async handleSubmit() {
        if (this.submitDisabled) {
            return;
        }
        const field = this.template.querySelector('lightning-textarea');
        if (field && field.reportValidity() === false) {
            return;
        }
        this.isSaving = true;
        this.error = undefined;
        try {
            const confirmation = await requestTermination({ accountId: this._recordId, reason: this.reason.trim() });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Termination requested',
                    message: confirmation || SUBMITTED,
                    variant: 'success'
                })
            );
            this.refreshRecord();
            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (error) {
            this.error = messageOf(error, SUBMIT_ERROR);
        } finally {
            this.isSaving = false;
        }
    }

    // The record page shows the request (its fields and approval history) without a reload
    refreshRecord() {
        Promise.resolve()
            .then(() => notifyRecordUpdateAvailable([{ recordId: this._recordId }]))
            .catch(() => {
                // The page refresh below covers it
            });
        this.dispatchEvent(new RefreshEvent());
    }
}