import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import CP_ASSETS from '@salesforce/resourceUrl/customerPortalAssets';
import basePath from '@salesforce/community/basePath';

// Wording of the Figma logout popup (p94)
const LABELS = {
    title: 'Logout?',
    message:
        'You are about to log out of your JK Properties Estates account. Thank you for using our portal, and we look forward to your return.',
    cancel: 'No',
    confirm: 'Yes',
    errorTitle: 'Error',
    errorMessage: 'Unable to log out. Please try again.'
};

export default class CustomerPortal_Logout extends LightningElement {
    labels = LABELS;
    logoutImage = CP_ASSETS + '/logout.png';

    _keydownHandler;
    _focused = false;

    connectedCallback() {
        this._keydownHandler = (event) => {
            if (event.key === 'Escape') {
                this.handleCancel();
            }
        };
        window.addEventListener('keydown', this._keydownHandler);
    }

    disconnectedCallback() {
        window.removeEventListener('keydown', this._keydownHandler);
    }

    renderedCallback() {
        if (!this._focused) {
            this._focused = true;
            const cancel = this.template.querySelector('.logout-cancel');
            if (cancel) {
                cancel.focus();
            }
        }
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleLogout() {
        try {
            this.dispatchEvent(new CustomEvent('logout'));

            const loginUrl = basePath + '/login';
            window.location.replace(
                basePath + '/secur/logout.jsp?retUrl=' + encodeURIComponent(loginUrl)
            );
        } catch (error) {
            console.error('Logout failed', error);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: LABELS.errorTitle,
                    message: LABELS.errorMessage,
                    variant: 'error'
                })
            );
        }
    }
}