import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAboutUsData from '@salesforce/apex/CustomerPortalController.getAboutUsData';

export default class CustomerPortal_AboutUs extends LightningElement {

    pageData;
    isLoading = true;
    hasError = false;

    connectedCallback() {
        this.loadAboutUs();
    }

    async loadAboutUs() {
        this.isLoading = true;
        this.hasError = false;

        try {
            this.pageData = await getAboutUsData();
        } catch (error) {
            this.hasError = true;
            console.error('customerPortal_AboutUs: failed to load About Us content', error);
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