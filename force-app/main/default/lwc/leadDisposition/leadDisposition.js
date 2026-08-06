import { LightningElement, api, wire, track } from 'lwc';

import getDispositions from '@salesforce/apex/LeadDispositionController.getDispositions';
import saveDisposition from '@salesforce/apex/LeadDispositionController.saveDisposition';
import getPicklistValues from '@salesforce/apex/Utility.getPicklistValues';

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

    /* PAGINATION */

    pageSize = 5;
    currentPage = 1;


    /* GETTERS */
    get isFollowUpRequired() {
        return this.disposition === 'In Discussion' || this.disposition === 'Not Reachable';
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
        this.callDateTime = event.target.value;
        console.log('Call DateTime:', this.callDateTime);

    }
    handleFollowUpDateTime(event) {
        this.followUpDateTime = event.target.value;
        console.log('Follow-up DateTime:', this.followUpDateTime);
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
        this.unitSize = event.target.value;
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

    saveDisposition() {
        const allValid = [...this.template.querySelectorAll(
                'lightning-input, lightning-combobox'
            )].reduce((validSoFar, field) => {
                field.reportValidity();
                return validSoFar && field.checkValidity();
            }, true);

            if (!allValid) {
                return;
            }

        saveDisposition({
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

            this.showForm = false;

            this.subject = '';
            this.description = '';
            this.disposition = '';

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
    }
}