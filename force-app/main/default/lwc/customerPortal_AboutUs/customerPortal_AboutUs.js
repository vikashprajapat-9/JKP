import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAboutUsData from '@salesforce/apex/CustomerPortalController.getAboutUsData';

const LOADING_TEXT = 'Loading';
const ERROR_TEXT = "We couldn't load this page right now. Please try again in a moment.";
const EMPTY_TEXT = 'This page will be available here soon.';
const TOAST_ERROR_TITLE = 'Error';
const TOAST_ERROR_MESSAGE = 'Unable to load page content. Please try again.';

export default class CustomerPortal_AboutUs extends LightningElement {

    pageData;
    isLoading = true;
    hasError = false;

    loadingText = LOADING_TEXT;
    errorText = ERROR_TEXT;
    emptyText = EMPTY_TEXT;

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
                    title: TOAST_ERROR_TITLE,
                    message: TOAST_ERROR_MESSAGE,
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

    // The rich text of the Portal Info record (Type "Customer"); the page shows a note while it is still empty
    get pageBody() {
        return this.pageData ? this.pageData.body : '';
    }

    get hasBody() {
        const html = this.pageBody;
        return !!html && html.replace(/<[^>]*>/g, '').replace(/&nbsp;|&#160;/gi, ' ').trim().length > 0;
    }

}