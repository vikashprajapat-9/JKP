import { LightningElement, api, wire, track } from 'lwc';

import getDispositions from '@salesforce/apex/LeadDispositionController.getDispositions';
import saveDisposition from '@salesforce/apex/LeadDispositionController.saveDisposition';

import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

export default class LeadDisposition extends LightningElement {

    @api recordId;

    @track dispositions = [];

    wiredResult;

    showForm = false;

    subject = '';
    description = '';
    disposition = '';

    /* PAGINATION */

    pageSize = 5;
    currentPage = 1;

    dispositionOptions = [
        { label: 'Connected', value: 'Connected' },
        { label: 'Not Connected', value: 'Not Connected' },
        { label: 'Interested', value: 'Interested' },
        { label: 'Not Interested', value: 'Not Interested' },
        { label: 'Callback Requested', value: 'Callback Requested' },
        { label: 'Site Visit Scheduled', value: 'Site Visit Scheduled' },
        { label: 'Site Visit Completed', value: 'Site Visit Completed' },
        { label: 'Negotiation Ongoing', value: 'Negotiation Ongoing' },
        { label: 'Booking Confirmed', value: 'Booking Confirmed' },
        { label: 'Closed Won', value: 'Closed Won' },
        { label: 'Closed Lost', value: 'Closed Lost' }
    ];

    @wire(getDispositions, { leadId: '$recordId' })
    wiredDispositions(result) {

        this.wiredResult = result;

        if (result.data) {
            this.dispositions = result.data;
        } else {
            this.dispositions = [];
        }
    }

    /* GETTERS */

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
    }

    saveDisposition() {

        saveDisposition({
            leadId: this.recordId,
            subject: this.subject,
            description: this.description,
            disposition: this.disposition
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