import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import qualifyLead from '@salesforce/apex/LeadLogicController.qualifyLead';
import LOGO_BLUE from '@salesforce/resourceUrl/Logo_Blue';
import LOGO_WHITE from '@salesforce/resourceUrl/Logo_White';
import LEAD_STATUS_FIELD from '@salesforce/schema/Lead.Status';
import LEAD_NAME_FIELD from '@salesforce/schema/Lead.Name';
import LEAD_COMPANY_FIELD from '@salesforce/schema/Lead.Company';

const FIELDS = [LEAD_STATUS_FIELD, LEAD_NAME_FIELD, LEAD_COMPANY_FIELD];

export default class LeadQualification extends LightningElement {
    @api recordId;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    lead;

    @track qualificationStatus = '';
    @track reason = '';
    @track isSaving = false;
    @track showStatusError = false;
    @track showReasonError = false;

    logoBlue = LOGO_BLUE;
    logoWhite = LOGO_WHITE;

    qualificationOptions = [
        {
            label: 'Qualified',
            value: 'Qualified',
            iconName: 'utility:check',
            badgeText: 'Verified Lead',
            badgeClass: 'decision-badge decision-badge--qualified',
            description: 'Lead meets investment criteria and is verified for sales follow-up.',
            labelClass: 'decision-card decision-card--qualified'
        },
        {
            label: 'Not Qualified',
            value: 'Not Qualified',
            iconName: 'utility:close',
            badgeText: 'Disqualified',
            badgeClass: 'decision-badge decision-badge--not-qualified',
            description: 'Lead does not meet requirements or has declined interest.',
            labelClass: 'decision-card decision-card--not-qualified'
        }
    ];

    qualifiedReasonTags = [
        'Budget Confirmed',
        'Site Visit Requested',
        'High Purchase Intent',
        'Decision Maker Engaged',
        'Immediate Requirement'
    ];

    notQualifiedReasonTags = [
        'Budget Mismatch',
        'Location Preference',
        'Invalid Contact Details',
        'Purchased Elsewhere',
        'No Longer Interested',
        'Looking for Rental'
    ];

    get currentStatus() {
        return getFieldValue(this.lead?.data, LEAD_STATUS_FIELD) || '';
    }

    get leadName() {
        return getFieldValue(this.lead?.data, LEAD_NAME_FIELD) || 'Lead Record';
    }

    get leadCompany() {
        return getFieldValue(this.lead?.data, LEAD_COMPANY_FIELD) || '';
    }

    get isNotContacted() {
        if (!this.lead?.data) {
            return false;
        }
        return this.currentStatus !== 'Contacted';
    }

    get isSaveDisabled() {
        return this.isSaving || this.isNotContacted;
    }

    get saveLabel() {
        return this.isSaving ? 'Submitting...' : 'Confirm Decision';
    }

    get isQualified() {
        return this.qualificationStatus === 'Qualified';
    }

    get isNotQualified() {
        return this.qualificationStatus === 'Not Qualified';
    }

    get activeReasonTags() {
        if (this.isQualified) {
            return this.qualifiedReasonTags;
        }
        if (this.isNotQualified) {
            return this.notQualifiedReasonTags;
        }
        return [];
    }

    get reasonLength() {
        return this.reason ? this.reason.length : 0;
    }

    get reasonClass() {
        const base = 'reason-textarea';
        return this.showReasonError ? `${base} textarea-error` : base;
    }

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    handleStatusChange(event) {
        this.qualificationStatus = event.target.value;
        this.showStatusError = false;
    }

    handleReasonChange(event) {
        this.reason = event.target.value;
        if (this.reason && this.reason.trim()) {
            this.showReasonError = false;
        }
    }

    handleTagClick(event) {
        if (this.isNotContacted) {
            return;
        }
        const tag = event.currentTarget.dataset.tag;
        if (!tag) {
            return;
        }

        const current = this.reason ? this.reason.trim() : '';
        if (!current) {
            this.reason = tag;
        } else if (!current.includes(tag)) {
            this.reason = `${current} | ${tag}`;
        }
        this.showReasonError = false;
    }

    async handleSave() {
        let isValid = true;

        if (!this.qualificationStatus) {
            this.showStatusError = true;
            isValid = false;
        }

        if (!this.reason || !this.reason.trim()) {
            this.showReasonError = true;
            isValid = false;
        }

        if (!isValid) {
            return;
        }

        this.isSaving = true;

        try {
            await qualifyLead({
                leadId: this.recordId,
                status: this.qualificationStatus,
                reason: this.reason.trim()
            });

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Decision Recorded',
                    message: `Lead has been marked as "${this.qualificationStatus}" successfully.`,
                    variant: 'success'
                })
            );

            // Close the quick action modal
            this.dispatchEvent(new CloseActionScreenEvent());

            // Refresh the record data across the page
            await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        } catch (error) {
            const msg =
                error?.body?.message ||
                error?.message ||
                'An unexpected error occurred while updating the lead.';

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: msg,
                    variant: 'error',
                    mode: 'sticky'
                })
            );
        } finally {
            this.isSaving = false;
        }
    }
}

