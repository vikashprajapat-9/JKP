import { LightningElement, wire } from 'lwc';
import basePath from '@salesforce/community/basePath';
import getUserProfile from '@salesforce/apex/partnerUserProfileController.getUserProfile';

const LOAD_ERROR = 'Your profile could not be loaded right now. Please try again.';

export default class PartnerUserProfile extends LightningElement {
    profile;
    isLoading = true;
    error;

    @wire(getUserProfile)
    wiredProfile({ error, data }) {
        // The wire first calls with neither, while the profile is still on its way
        if (data) {
            this.profile = data;
            this.error = undefined;
            this.isLoading = false;
        } else if (error) {
            this.profile = undefined;
            this.error = (error.body && error.body.message) || LOAD_ERROR;
            this.isLoading = false;
            console.error('Error fetching user profile:', error);
        }
    }

    // The portal asks to confirm, as for the menu's Logout. On a page of its own, the profile logs out of this site
    // directly: the site's own logout, not the domain's, which belongs to another site.
    handleLogout() {
        const confirmedByPortal = !this.dispatchEvent(new CustomEvent('logout', { bubbles: true, composed: true, cancelable: true }));
        if (!confirmedByPortal) {
            window.location.replace(basePath + '/secur/logout.jsp');
        }
    }
}