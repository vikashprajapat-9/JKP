import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LOGOUT_IMAGE from '@salesforce/resourceUrl/LogoutImage';
import basePath from '@salesforce/community/basePath';

export default class CustomerPortal_Logout extends LightningElement {
    logoutImage = LOGOUT_IMAGE;

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
                    title: 'Error',
                    message: 'Unable to log out. Please try again.',
                    variant: 'error'
                })
            );
        }
    }
}