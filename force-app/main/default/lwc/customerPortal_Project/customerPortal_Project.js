import { LightningElement } from 'lwc';
import CP_ASSETS from '@salesforce/resourceUrl/customerPortalAssets';

const INTRO = 'Explore our extensive property projects and take the first step towards finding your dream home with John Keells Properties. Our curated selection offers a variety of options to suit your needs and preferences. Start your journey with us today and discover the perfect place to call home.';

// The Projects page of the Customer Portal (Figma p16-p20). It shows the Partner Portal's project components
// (c-partner-web-portal-project and its detail page and file viewer) with portal="customer": they read every active
// project through CustomerPortalController and draw the Customer Portal's own markup and look for that flag.
export default class CustomerPortal_Project extends LightningElement {
    labels = { intro: INTRO };
    // Picture of the empty list (Figma p56 style), from the Customer Portal's own static resource
    emptyImage = CP_ASSETS + '/empty-state.svg';
}