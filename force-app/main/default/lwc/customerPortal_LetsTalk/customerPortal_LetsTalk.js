import { LightningElement } from 'lwc';
import getLetsTalkPageData from '@salesforce/apex/CustomerPortalController.getLetsTalkPageData';
import CP_ASSETS from '@salesforce/resourceUrl/customerPortalAssets';

const TEXT = {
    loading: 'Loading contact details...',
    error: "We couldn't load this page right now. Please try again in a moment.",
    retry: 'Retry',
    selectProject: 'Select a project',
    empty: 'No contact details available yet.',
    propertyAddress: 'Property Address',
    email: 'Email',
    crmContact: 'CRM Contact',
    corporateAddress: 'Corporate Address',
    openMaps: 'Open Location on Maps',
    emailUs: 'Email us',
    callUs: 'Call us',
    noContact: 'Your contact person will be shared with you shortly.'
};

export default class CustomerPortal_LetsTalk extends LightningElement {
    isLoading = true;
    hasError = false;

    pageTitle = '';
    pageDescription = '';
    projects = [];
    selectedProjectId;

    text = TEXT;
    emptyImg = CP_ASSETS + '/empty-state.svg';

    connectedCallback() {
        this.loadPageData();
    }

    async loadPageData() {
        this.isLoading = true;
        this.hasError = false;

        try {
            const data = await getLetsTalkPageData();
            this.pageTitle = data.title;
            this.pageDescription = data.description;
            this.projects = data.projects || [];
            this.selectedProjectId = data.defaultProject;
        } catch (error) {
            this.hasError = true;
            console.error('customerPortal_LetsTalk: failed to load Lets Talk page data', error);
        } finally {
            this.isLoading = false;
        }
    }

    get showContent() {
        return !this.isLoading && !this.hasError;
    }

    get hasProjects() {
        return this.projects.length > 0;
    }

    // the chosen project; the first one when the default id is not in the list
    get selectedProjectData() {
        return this.projects.find((p) => p.id === this.selectedProjectId) || this.projects[0] || null;
    }

    // One card per opportunity on the chosen project: a project booked twice shows both CS Members
    get crmContacts() {
        const project = this.selectedProjectData;
        return project && project.crmContacts ? project.crmContacts : [];
    }

    get noCrmContact() {
        return this.crmContacts.length === 0;
    }

    // With one booking the card keeps the Figma's "Call us" action; with several, each entry shows its own number
    get hasOneContact() {
        return this.crmContacts.length === 1;
    }

    get singleContactPhoneUrl() {
        return this.hasOneContact ? this.crmContacts[0].phoneUrl : null;
    }

    get selectedProjectName() {
        const project = this.selectedProjectData;
        return project ? project.name : '';
    }

    get projectOptions() {
        const selected = this.selectedProjectData;
        return this.projects.map((p) => {
            return {
                id: p.id,
                name: p.name,
                isSelected: !!selected && p.id === selected.id
            };
        });
    }

    handleProjectChange(event) {
        this.selectedProjectId = event.target.value;
    }

    handleRetry() {
        this.loadPageData();
    }

    handleOpenPropertyMap() {
        const project = this.selectedProjectData;
        if (project && project.propertyMapUrl) {
            window.open(project.propertyMapUrl, '_blank', 'noopener,noreferrer');
        }
    }

    handleOpenCorporateMap() {
        const project = this.selectedProjectData;
        if (project && project.corporateMapUrl) {
            window.open(project.corporateMapUrl, '_blank', 'noopener,noreferrer');
        }
    }

    handleEmailUs() {
        const project = this.selectedProjectData;
        if (project && project.emailUrl) {
            window.location.href = project.emailUrl;
        }
    }

    handleCallUs(event) {
        const phoneUrl = event.currentTarget.dataset.phone;
        if (phoneUrl) {
            window.location.href = phoneUrl;
        }
    }
}