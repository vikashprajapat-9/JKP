import { LightningElement } from 'lwc';
import INTRO from '@salesforce/label/c.Customer_Portal_Projects_Intro';

// The Projects page of the Customer Portal. It shows the same page as the Partner Portal (c-partner-web-portal-project)
// for every active project; CustomerPortalProjectController reads the projects and their OneDrive photos and files.
export default class CustomerPortal_Project extends LightningElement {
    labels = { intro: INTRO };
}