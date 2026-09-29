import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getTermsConditionsData from '@salesforce/apex/CustomerPortalController.getTermsConditionsData';

export default class CustomerPortal_TermsConditions extends LightningElement {

    pageData;
    isLoading = true;
    hasError = false;

    connectedCallback() {
        this.loadTermsConditions();
    }

    async loadTermsConditions() {
        this.isLoading = true;
        this.hasError = false;

        try {
            this.pageData = await getTermsConditionsData();
        } catch (error) {
            this.hasError = true;
            console.error('customerPortal_TermsConditions: failed to load Terms & Conditions content', error);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'Unable to load page content. Please try again.',
                    variant: 'error',
                    mode: 'dismissable'
                })
            );
        } finally {
            this.isLoading = false;
        }
    }

    get showContent() {
        return !this.isLoading && !this.hasError && this.pageData;
    }

    get pageTitle() {
        return this.pageData ? this.pageData.title : '';
    }

    get pageDescription() {
        return this.pageData ? this.pageData.description : '';
    }
}