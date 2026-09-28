import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LOGOUT_IMAGE from '@salesforce/resourceUrl/LogoutImage';

export default class CustomerPortal_Logout extends LightningElement {
    logoutImage = LOGOUT_IMAGE;

    handleCancel() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleLogout() {
        try {
            // TODO: Add actual logout/session termination logic here.
            // Placeholder only: notify the parent that the user confirmed.
            this.dispatchEvent(new CustomEvent('logout'));
        } catch (error) {
            console.error('Logout failed', error);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'Unable to log out. Please try again.',
                    variant: 'error'
                })
            );
        }
    }
}