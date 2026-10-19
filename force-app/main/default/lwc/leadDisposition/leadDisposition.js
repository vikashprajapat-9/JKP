import { LightningElement, api, wire, track } from 'lwc';

import getDispositions from '@salesforce/apex/LeadDispositionController.getDispositions';
import saveDisposition from '@salesforce/apex/LeadDispositionController.saveDisposition';
import getPicklistValues from '@salesforce/apex/Utility.getPicklistValues';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

export default class LeadDisposition extends LightningElement {

    @api recordId;
    @track dispositions = [];
    wiredResult;
    showLossReasonModal = false;
    showContactedModal = false;
    showForm = false;

    subject = '';
    description = '';
    disposition = '';
    callDateTime ='' ;
    followUpDateTime = null;
    lossReason;
    otherLossReason;

    dispositionOptions = [];
    lossReasonOptions = [];
    purchasePurposeOptions = [];
    unitTypeOptions = [];
    purchaseTimelineOptions = [];
    assessBudgetOptions = [];
    assessFinanceReadinessOptions = [];

    connectedCallback() {
        this.loadPicklists();
    }

    loadPicklists() {

        this.loadPicklist('Call_Disposition__c', 'Call_Disposition__c', 'dispositionOptions');
        this.loadPicklist('Lead', 'Loss_Reason__c', 'lossReasonOptions');
        this.loadPicklist('Lead', 'Purchase_Purpose__c', 'purchasePurposeOptions');
        this.loadPicklist('Lead', 'Unit_Type__c', 'unitTypeOptions');
        this.loadPicklist('Lead', 'Purchase_Timeline__c', 'purchaseTimelineOptions');
        this.loadPicklist('Lead', 'Assess_Budget__c', 'assessBudgetOptions');
        this.loadPicklist('Lead', 'Assess_Finance_Readiness__c', 'assessFinanceReadinessOptions');
    }

    loadPicklist(objectApiName, fieldApiName, propertyName) {

        getPicklistValues({
            objectApiName: objectApiName,
            fieldApiName: fieldApiName
        })
        .then(result => {
            this[propertyName] = result;
        })
        .catch(error => {
            console.error(
                'Error loading ' + fieldApiName,
                error
            );
        });
    }

    @wire(getDispositions, { leadId: '$recordId' })
        wiredDispositions(result) {
            this.wiredResult = result;

            if (result.data) {
                this.dispositions = result.data;
            } else if (result.error) {
                console.error(result.error);
                this.dispositions = [];
            }
        }

    /* PAGINATION */

    pageSize = 5;
    currentPage = 1;


    /* GETTERS */
    get minDateTime() {
        const now = new Date();
        now.setHours(0, 0, 0, 0);
        const offset = now.getTimezoneOffset() * 60000;
        return new Date(now.getTime() - offset).toISOString().slice(0, 16);
    }
    get isFollowUpRequired() {
        return this.disposition === 'In Discussion' ;
    }
    // get isNotInterested(){
    //     return this.disposition === 'Not Interested';
    // }

    get showEmptyState() {
        return this.dispositions.length === 0;
    }

    get totalPages() {
        return Math.ceil(this.dispositions.length / this.pageSize);
    }

    get paginatedDispositions() {

        const start = (this.currentPage - 1) * this.pageSize;
        const end = start + this.pageSize;

        return this.dispositions.slice(start, end);
    }

    get disablePrevious() {
        return this.currentPage <= 1;
    }

    get disableNext() {
        return this.currentPage >= this.totalPages;
    }

    get showPagination() {
        return this.dispositions.length > this.pageSize;
    }
    get showOtherReason() {
        return this.lossReason === 'Other';
    }

    /* PAGINATION METHODS */

    handlePrevious() {

        if (this.currentPage > 1) {
            this.currentPage--;
        }
    }

    handleNext() {

        if (this.currentPage < this.totalPages) {
            this.currentPage++;
        }
    }

    /* FORM METHODS */
    handleAddDisposition() {
        this.showForm = true;
    }

    handleCancel() {
        this.resetForm();
        this.showForm = false;
    }
    handleSubject(event) {
        this.subject = event.target.value;
    }

    handleDescription(event) {
        this.description = event.target.value;
    }

    handleDisposition(event) {
        this.disposition = event.target.value;
        if (this.disposition === 'Not Interested') {
            this.showLossReasonModal = true;
        }
        if (this.disposition === 'Good Response') {
            this.showContactedModal = true;
        }
    }
    handleCallDateTime(event) {
        const selectedDateTime = event.target.value;
        const selectedDate = new Date(selectedDateTime);
        const today = new Date();
        today.setHours(0, 0, 0, 0);

        if (selectedDate < today) {
            event.target.setCustomValidity(
                'Call Date Time cannot be before today.'
            );
            event.target.reportValidity();
            this.callDateTime = '';
            event.target.value = '';
            return;
        }

        event.target.setCustomValidity('');
        this.callDateTime = selectedDateTime;
    }

    handleFollowUpDateTime(event) {
        const selectedDateTime = event.target.value;
        const selectedDate = new Date(selectedDateTime);
        const today = new Date();
        today.setHours(0, 0, 0, 0);

        if (selectedDate < today) {
            event.target.setCustomValidity(
                'Follow-up Date Time cannot be before today.'
            );
            event.target.reportValidity();
            this.followUpDateTime = null;
            event.target.value = '';
            return;
        }

        event.target.setCustomValidity('');
        this.followUpDateTime = selectedDateTime;
    }
    handleLossReason(event) {
        this.lossReason = event.detail.value;
    }
    handleOtherReason(event) {
        this.otherLossReason = event.target.value;
    }
    handlePurchasePurpose(event) {
        this.purchasePurpose = event.detail.value;
    }
    handleUnitType(event) {
        this.unitType = event.detail.value;
    }
    handleUnitSize(event) {
        const value = event.target.value;

        if (value === null || value === undefined || value === '') {
            event.target.setCustomValidity('Unit Sq.ft is required.');
            event.target.reportValidity();
            this.unitSize = '';
            return;
        }

        if (!/^\d+(\.\d+)?$/.test(String(value))) {
            event.target.setCustomValidity('Please enter only numeric values in Unit Sq.ft.');
            event.target.reportValidity();
            this.unitSize = '';
            return;
        }

        event.target.setCustomValidity('');
        this.unitSize = value;
    }
    handlePurchaseTimeline(event) {
        this.purchaseTimeline = event.detail.value;
    }
    handleAssessBudget(event) {
        this.assessBudget = event.detail.value;
    }
    handleAssessFinanceReadiness(event) {
        this.assessFinanceReadiness = event.detail.value;
    }
    handleLossReasonSave() {
        if (!this.lossReason) {
            return;
        }
        if (this.lossReason === 'Other' && !this.otherLossReason) {
        return;
            }
        this.showLossReasonModal  = false;
    }
    handleContactedSave() {
        if (!this.purchasePurpose) {
            return;
        }
        if (!this.unitType) {
            return;
        }
        if (!this.unitSize) {
            return;
        }
        if (!this.purchaseTimeline) {
            return;
        }
        if (!this.assessBudget) {
            return;
        }
        if (!this.assessFinanceReadiness) {
            return;
        }
        this.showContactedModal  = false;
    }
    closeLossReasonModal() {
        this.showLossReasonModal = false;
        this.lossReason = null;
        this.otherLossReason = null;
        this.disposition = '';
    }
    closeContactedModal() {
        this.showContactedModal = false;
        this.disposition = '';
        this.purchasePurpose = null;
        this.unitType = null;
        this.unitSize = null;
        this.purchaseTimeline = null;
        this.assessBudget = null;
        this.assessFinanceReadiness = null;
    }
    async saveDisposition() {
        const allValid = [...this.template.querySelectorAll(
                'lightning-input, lightning-combobox'
            )].reduce((validSoFar, field) => {
                field.reportValidity();
                return validSoFar && field.checkValidity();
            }, true);

            if (!allValid) {
                return;
            }

        await saveDisposition({
            leadId: this.recordId,
            subject: this.subject,
            description: this.description,
            disposition: this.disposition,
            callDateTime: this.callDateTime,
            followUpDateTime: this.followUpDateTime,
            lossReason: this.lossReason,
            otherLossReason: this.otherLossReason,
            purchasePurpose: this.purchasePurpose,
            unitType: this.unitType,
            unitSize: this.unitSize,
            purchaseTimeline: this.purchaseTimeline,
            assessBudget: this.assessBudget,
            assessFinanceReadiness: this.assessFinanceReadiness
        })
        .then(() => {

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'Disposition Saved Successfully',
                    variant: 'success'
                })
            );
            this.resetForm();
            this.showForm = false;
            refreshApex(this.wiredResult);
        })
        .catch(error => {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: error.body.message,
                    variant: 'error'
                })
            );
        });
        await notifyRecordUpdateAvailable([
            { recordId: this.recordId }
        ]);
    }
    resetForm() {
        this.subject = '';
        this.description = '';
        this.disposition = '';
        this.callDateTime = '';
        this.followUpDateTime = null;

        this.lossReason = null;
        this.otherLossReason = null;

        this.purchasePurpose = null;
        this.unitType = null;
        this.unitSize = null;
        this.purchaseTimeline = null;
        this.assessBudget = null;
        this.assessFinanceReadiness = null;

        this.showLossReasonModal = false;
        this.showContactedModal = false;

        this.template.querySelectorAll(
            'lightning-input, lightning-textarea, lightning-combobox'
        ).forEach(field => {
            field.value = null;
        });
    }

}