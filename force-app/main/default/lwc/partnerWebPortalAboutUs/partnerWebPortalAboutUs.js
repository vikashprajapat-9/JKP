import { LightningElement, wire } from 'lwc';
import getChannelPartnerInfo from '@salesforce/apex/partnerWebPortalInfoController.getChannelPartnerInfo';

// True when the rich text has any text to show (images are not shown on the portal)
function hasText(html) {
    if (!html) {
        return false;
    }
    return html.replace(/<[^>]*>/g, '').replace(/&nbsp;|&#160;/gi, ' ').trim().length > 0;
}

// The text is the About Us field of the channel partner portal's Portal Info record
export default class PartnerWebPortalAboutUs extends LightningElement {
    content;
    loadError;
    isLoading = true;

    @wire(getChannelPartnerInfo)
    wiredInfo({ data, error }) {
        if (error) {
            this.loadError = 'About Us could not be loaded. Please refresh the page to try again.';
            this.isLoading = false;
        } else if (data) {
            this.content = data.aboutUs;
            this.loadError = undefined;
            this.isLoading = false;
        }
    }

    get hasContent() {
        return hasText(this.content);
    }

    get busy() {
        return String(this.isLoading);
    }
}