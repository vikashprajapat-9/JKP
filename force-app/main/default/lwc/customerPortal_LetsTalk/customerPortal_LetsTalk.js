import { LightningElement } from 'lwc';
import getLetsTalkPageData from '@salesforce/apex/CustomerPortalController.getLetsTalkPageData';

export default class CustomerPortal_LetsTalk extends LightningElement {
    isLoading = true;
    hasError = false;

    pageTitle = '';
    pageDescription = '';
    projects = [];
    selectedProjectId;

    isDropdownOpen = false;

    _outsideClickHandler;

    connectedCallback() {
        this.loadPageData();
        this._outsideClickHandler = (event) => {
            if (this.isDropdownOpen && !this.template.contains(event.target)) {
                this.isDropdownOpen = false;
            }
        };
        document.addEventListener('click', this._outsideClickHandler, true);
    }

    disconnectedCallback() {
        if (this._outsideClickHandler) {
            document.removeEventListener('click', this._outsideClickHandler, true);
        }
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

    get selectedProjectData() {
        return this.projects.find((p) => p.id === this.selectedProjectId) || null;
    }

    get selectedProjectName() {
        const project = this.selectedProjectData;
        return project ? project.name : '';
    }

    get projectOptions() {
        return this.projects.map((p) => {
            const isSelected = p.id === this.selectedProjectId;
            return {
                id: p.id,
                name: p.name,
                isSelected,
                itemClass: isSelected ? 'dropdown-item dropdown-item_selected' : 'dropdown-item'
            };
        });
    }

    get chevronClass() {
        return this.isDropdownOpen ? 'chevron chevron_open' : 'chevron';
    }

    handleToggleDropdown() {
        this.isDropdownOpen = !this.isDropdownOpen;
    }

    handleSelectProject(event) {
        this.selectedProjectId = event.currentTarget.dataset.id;
        this.isDropdownOpen = false;
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

    handleCallUs() {
        const project = this.selectedProjectData;
        if (project && project.phoneUrl) {
            window.location.href = project.phoneUrl;
        }
    }
}