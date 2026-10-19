import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getTermsConditionsData from '@salesforce/apex/CustomerPortalController.getTermsConditionsData';

const LOADING_TEXT = 'Loading';
const ERROR_TEXT = "We couldn't load this page right now. Please try again in a moment.";
const EMPTY_TEXT = 'The Terms & Conditions will be available here soon.';
const TOAST_ERROR_TITLE = 'Error';
const TOAST_ERROR_MESSAGE = 'Unable to load page content. Please try again.';

export default class CustomerPortal_TermsConditions extends LightningElement {

    pageData;
    isLoading = true;
    hasError = false;

    loadingText = LOADING_TEXT;
    errorText = ERROR_TEXT;
    emptyText = EMPTY_TEXT;

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