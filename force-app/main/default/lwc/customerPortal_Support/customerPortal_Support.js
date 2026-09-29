import { LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import SUCCESS_ILLUSTRATION from '@salesforce/resourceUrl/SuccessReferralImage';
import getSupportPageData from '@salesforce/apex/CustomerPortalController.getSupportPageData';
import createServiceRequest from '@salesforce/apex/CustomerPortalController.createServiceRequest';

const EMPTY_FORM = { issue: '', property: '', unitNumber: '', otherDetails: '', description: '' };

export default class CustomerPortal_Support extends LightningElement {
    isLoading = true;
    hasError = false;
    pageDescription = '';
    dlpLabel = '';
    serviceRequests = [];
    projectFilters = [];
    issueOptions = [];
    propertyOptions = [];
    emptyStateImageUrl = '';
    emptyImageFailed = false;

    wiredResult;

    selectedProject = '';
    isFilterOpen = false;

    isRequestModalOpen = false;
    isSuccessModalOpen = false;
    successTitle = '';
    successMessage = '';
    successImageUrl = SUCCESS_ILLUSTRATION;

    form = { ...EMPTY_FORM };
    showValidation = false;
    isSubmitting = false;

    connectedCallback() {
        this.outsideClickHandler = this.handleDocumentClick.bind(this);
        document.addEventListener('click', this.outsideClickHandler);
    }

    disconnectedCallback() {
        document.removeEventListener('click', this.outsideClickHandler);
    }

    handleDocumentClick(event) {
        if (!this.isFilterOpen) return;
        const wrap = this.template.querySelector('.filter-wrap');
        if (wrap && !event.composedPath().includes(wrap)) {
            this.isFilterOpen = false;
        }
    }

    @wire(getSupportPageData)
    wiredPageData(result) {
        this.wiredResult = result;
        const { data, error } = result;
        if (data) {
            this.isLoading = false;
            this.hasError = false;
            this.pageDescription = data.description;
            this.dlpLabel = data.dlpLabel;
            this.serviceRequests = data.serviceRequests || [];
            this.projectFilters = data.projectFilters || [];
            this.issueOptions = data.issueOptions || [];
            this.propertyOptions = data.propertyOptions || [];
            this.emptyStateImageUrl = data.emptyStateImageUrl || '';
        } else if (error) {
            this.isLoading = false;
            this.hasError = true;
            console.error('Error loading Support page data', error);
        }
    }

    handleRetry() {
        this.hasError = false;
        this.isLoading = true;
        refreshApex(this.wiredResult).catch((error) => {
            this.isLoading = false;
            this.hasError = true;
            console.error('Retry failed', error);
        });
    }

    get showContent() {
        return !this.isLoading && !this.hasError;
    }

    get hasRequests() {
        return this.serviceRequests.length > 0;
    }

    get showToolbar() {
        return this.hasRequests;
    }

    get showDlp() {
        return this.hasRequests && !!this.dlpLabel;
    }

    get displayedRequests() {
        return this.serviceRequests
            .filter((r) => !this.selectedProject || r.projectName === this.selectedProject)
            .map((r, index) => ({
                ...r,
                srNo: index + 1,
                statusClass: this.getStatusClass(r.status)
            }));
    }

    get hasDisplayedRequests() {
        return this.displayedRequests.length > 0;
    }

    get showEmptyImage() {
        return !!this.emptyStateImageUrl && !this.emptyImageFailed;
    }

    handleEmptyImageError() {
        this.emptyImageFailed = true;
    }

    getStatusClass(status) {
        const slug = (status || 'unknown').toLowerCase().replace(/[^a-z0-9]+/g, '-');
        return 'status-pill status-' + slug;
    }

    get filterOptions() {
        return this.projectFilters.map((opt, index) => ({
            ...opt,
            key: index + '-' + opt.value,
            className: opt.value === this.selectedProject ? 'filter-option filter-option-active' : 'filter-option'
        }));
    }

    get selectedFilterLabel() {
        if (!this.selectedProject) return 'Filter By Projects';
        const match = this.projectFilters.find((o) => o.value === this.selectedProject);
        return match ? match.label : 'Filter By Projects';
    }

    get filterAriaExpanded() {
        return this.isFilterOpen ? 'true' : 'false';
    }

    handleToggleFilter() {
        this.isFilterOpen = !this.isFilterOpen;
    }

    handleSelectFilter(event) {
        this.selectedProject = event.currentTarget.dataset.value;
        this.isFilterOpen = false;
    }

    handleOpenRequestModal() {
        this.form = { ...EMPTY_FORM };
        this.showValidation = false;
        this.isRequestModalOpen = true;
    }

    handleCloseRequestModal() {
        this.isRequestModalOpen = false;
    }

    handleCloseSuccessModal() {
        this.isSuccessModalOpen = false;
        this.successTitle = '';
        this.successMessage = '';
    }

    handleOverlayClick() {
        if (this.isSuccessModalOpen) {
            this.handleCloseSuccessModal();
        } else {
            this.handleCloseRequestModal();
        }
    }

    stopPropagation(event) {
        event.stopPropagation();
    }

    get issueOptionsView() {
        return this.issueOptions.map((o) => ({ ...o, selected: o.value === this.form.issue }));
    }

    get propertyOptionsView() {
        return this.propertyOptions.map((o) => ({ ...o, selected: o.value === this.form.property }));
    }

    get isIssueEmpty() {
        return !this.form.issue;
    }

    get isPropertyEmpty() {
        return !this.form.property;
    }

    get showOthersField() {
        const selected = this.issueOptions.find((o) => o.value === this.form.issue);
        return !!(selected && selected.requiresDetails);
    }

    handleFieldChange(event) {
        const field = event.currentTarget.dataset.field;
        const value = event.currentTarget.value;
        const updated = { ...this.form, [field]: value };
        if (field === 'issue') {
            const selected = this.issueOptions.find((o) => o.value === value);
            if (!selected || !selected.requiresDetails) {
                updated.otherDetails = '';
            }
        }
        this.form = updated;
    }

    validationErrors() {
        const f = this.form;
        const errs = {};
        if (!f.issue) errs.issue = 'Please select an issue.';
        if (!f.property) errs.property = 'Please select a property.';
        if (!f.unitNumber || !f.unitNumber.trim()) errs.unitNumber = 'Please enter the unit number.';
        if (this.showOthersField && (!f.otherDetails || !f.otherDetails.trim())) {
            errs.otherDetails = 'Please specify the issue.';
        }
        if (!f.description || !f.description.trim()) errs.description = 'Please enter a description.';
        return errs;
    }

    get errors() {
        return this.showValidation ? this.validationErrors() : {};
    }

    get issueSelectClass() {
        return this.errors.issue ? 'form-select has-error' : 'form-select';
    }

    get propertySelectClass() {
        return this.errors.property ? 'form-select has-error' : 'form-select';
    }

    get unitInputClass() {
        return this.errors.unitNumber ? 'form-input has-error' : 'form-input';
    }

    get othersInputClass() {
        return this.errors.otherDetails ? 'form-input has-error' : 'form-input';
    }

    get descriptionClass() {
        return this.errors.description ? 'form-textarea has-error' : 'form-textarea';
    }

    async handleSubmit() {
        this.showValidation = true;
        if (Object.keys(this.validationErrors()).length > 0 || this.isSubmitting) {
            return;
        }

        this.isSubmitting = true;
        try {
            const response = await createServiceRequest({
                issueType: this.form.issue,
                propertyName: this.form.property,
                unitNumber: this.form.unitNumber.trim(),
                otherDetails: this.showOthersField ? this.form.otherDetails.trim() : '',
                description: this.form.description.trim()
            });

            if (response && response.success === false) {
                this.showSubmitErrorToast();
                return;
            }

            this.isRequestModalOpen = false;
            this.successTitle = response.title;
            this.successMessage = response.message;
            this.isSuccessModalOpen = true;

            refreshApex(this.wiredResult).catch((error) => {
                console.error('Refresh after submit failed', error);
            });
        } catch (error) {
            console.error('Error raising service request', error);
            this.showSubmitErrorToast();
        } finally {
            this.isSubmitting = false;
        }
    }

    showSubmitErrorToast() {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Unable to raise service request',
                message: 'Something went wrong while raising the service request.',
                variant: 'error',
                mode: 'dismissible'
            })
        );
    }
}