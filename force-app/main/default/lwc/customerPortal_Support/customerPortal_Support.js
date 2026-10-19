import { LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import CP_ASSETS from '@salesforce/resourceUrl/customerPortalAssets';
import getSupportPageData from '@salesforce/apex/CustomerPortalController.getSupportPageData';
import createServiceRequest from '@salesforce/apex/CustomerPortalController.createServiceRequest';

// Visible text (Figma pages 56-60). The page intro, DLP period, rows and the success text come from Apex.
const LABELS = {
    title: 'Support',
    raiseRequest: 'Raise a Service Request',
    loading: 'Loading your service requests...',
    loadError: 'Something went wrong while loading your service requests. Please try again.',
    retry: 'Retry',
    filter: 'Filter By Projects',
    colSr: 'Sr.',
    colDescription: 'Description',
    colProject: 'Project',
    colRequestId: 'Service request ID',
    colCreatedDate: 'Created Date',
    colType: 'Type',
    colStatus: 'Status',
    empty: 'No Service Request Raised',
    close: 'Close',
    modalTitle: 'Raise a service request',
    modalIntro:
        'Please select the type of issue that best matches your inquiry or request below. Our team is dedicated to ' +
        'addressing your needs promptly and efficiently. Thank you for choosing John Keels Properties ! Your ' +
        'satisfaction is our priority.',
    issue: 'Select an issue',
    issuePlaceholder: 'Select an issue you have faced',
    property: 'Select Property',
    propertyPlaceholder: 'Select your property',
    unit: 'Select Unit No.',
    unitPlaceholder: 'Select your unit no.',
    location: 'Location',
    masterCategory: 'Master Category',
    subCategory: 'Sub Category',
    subject: 'Subject',
    subjectPlaceholder: 'What is this request about?',
    description: 'Description',
    descriptionPlaceholder: 'Describe your issue',
    submit: 'Submit',
    // used only when Apex returns no title / message (Figma p59 wording)
    successTitle: 'Your request has been raised successfully!',
    successMessage:
        'We have received your service request and it is now being reviewed by our team. Thank you for contacting ' +
        'JK Properties Estates.',
    submitErrorTitle: 'Unable to raise service request',
    submitErrorMessage: 'Something went wrong while raising the service request.'
};

const ERRORS = {
    property: 'Please select a property.',
    unitNumber: 'Please select a unit.',
    issue: 'Please select an issue.',
    dlpLocation: 'Please select a location.',
    dlpMasterCategory: 'Please select a master category.',
    dlpSubCategory: 'Please select a sub category.',
    subject: 'Enter a subject.',
    description: 'Please enter a description.'
};

// Icons traced from the Figma PDF (funnel p60, close X as in the shared modal)
const ICONS = {
    funnel:
        'M2.03 1.2H15.37A.83 .83 0 0 1 16.2 2.03V3.35A.83 .83 0 0 1 15.96 3.94L10.61 9.29A.83 .83 0 0 0 10.37 9.88' +
        'V15.13A.83 .83 0 0 1 9.33 15.94L7.66 15.52A.83 .83 0 0 1 7.03 14.72V9.88A.83 .83 0 0 0 6.79 9.29L1.44 3.94' +
        'A.83 .83 0 0 1 1.2 3.35V2.03A.83 .83 0 0 1 2.03 1.2Z',
    close: 'M14 1.41L12.59 0L7 5.59L1.41 0L0 1.41L5.59 7L0 12.59L1.41 14L7 8.41L12.59 14L14 12.59L8.41 7L14 1.41Z'
};

// Status -> shared badge colour (Figma p60: Pending red, Resolved green)
const STATUS_BADGES = {
    pending: 'cp-badge_pending',
    open: 'cp-badge_pending',
    new: 'cp-badge_pending',
    'in progress': 'cp-badge_progress',
    'in-progress': 'cp-badge_progress',
    resolved: 'cp-badge_success',
    completed: 'cp-badge_completed',
    closed: 'cp-badge_neutral',
    cancelled: 'cp-badge_cancelled',
    canceled: 'cp-badge_cancelled'
};

const EMPTY_FORM = {
    property: '',
    unitNumber: '',
    issue: '',
    subject: '',
    description: '',
    dlpLocation: '',
    dlpMasterCategory: '',
    dlpSubCategory: ''
};

function badgeClass(status) {
    const key = String(status || '')
        .trim()
        .toLowerCase()
        .replace(/\s+/g, ' ');
    return 'cp-badge ' + (STATUS_BADGES[key] || 'cp-badge_neutral');
}

function selectClass(isEmpty, hasError) {
    let cls = 'cp-select';
    if (isEmpty) cls += ' sr-select_empty';
    if (hasError) cls += ' cp-input_invalid';
    return cls;
}

export default class CustomerPortal_Support extends LightningElement {
    labels = LABELS;
    icons = ICONS;
    emptyImageUrl = CP_ASSETS + '/empty-state.svg';
    successImageUrl = CP_ASSETS + '/success-request.png';

    isLoading = true;
    hasError = false;
    pageDescription = '';
    dlpLabel = '';
    dlpPeriods = [];
    serviceRequests = [];
    projectFilters = [];
    issueOptions = [];
    propertyOptions = [];
    projectUnitGroups = [];
    dlpLocations = [];

    wiredResult;

    selectedProject = '';

    isRequestModalOpen = false;
    isSuccessModalOpen = false;
    successTitle = '';
    successMessage = '';

    form = { ...EMPTY_FORM };
    showValidation = false;
    isSubmitting = false;
    submitError;

    // move focus into a modal once it has rendered
    focusModalPending = false;
    overlayPointerDown = false;

    @wire(getSupportPageData)
    wiredPageData(result) {
        this.wiredResult = result;
        const { data, error } = result;
        if (data) {
            this.isLoading = false;
            this.hasError = false;
            this.pageDescription = data.description;
            this.dlpLabel = data.dlpLabel;
            this.dlpPeriods = data.dlpPeriods || [];
            this.serviceRequests = data.serviceRequests || [];
            this.projectFilters = data.projectFilters || [];
            this.issueOptions = data.issueOptions || [];
            this.propertyOptions = data.propertyOptions || [];
            this.projectUnitGroups = data.projectUnitGroups || [];
            this.dlpLocations = data.dlpLocations || [];
        } else if (error) {
            this.isLoading = false;
            this.hasError = true;
            console.error('Error loading Support page data', error);
        }
    }

    renderedCallback() {
        if (this.focusModalPending) {
            const panel = this.template.querySelector('.cp-modal');
            if (panel) {
                this.focusModalPending = false;
                panel.focus();
            }
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

    // ---------------------------------------------------------------
    // List (Figma p56 empty, p60 table)
    // ---------------------------------------------------------------

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
                key: r.id || 'sr-' + index,
                srNo: index + 1,
                badgeClass: badgeClass(r.status)
            }));
    }

    get hasDisplayedRequests() {
        return this.displayedRequests.length > 0;
    }

    get filterOptions() {
        const options = this.projectFilters.slice();
        if (!options.some((o) => !o.value)) {
            options.unshift({ label: LABELS.filter, value: '' });
        }
        return options.map((opt, index) => ({
            ...opt,
            key: index + '-' + (opt.value || ''),
            selected: (opt.value || '') === this.selectedProject
        }));
    }

    get selectedFilterLabel() {
        if (!this.selectedProject) return LABELS.filter;
        const match = this.projectFilters.find((o) => o.value === this.selectedProject);
        return match ? match.label : LABELS.filter;
    }

    handleFilterChange(event) {
        this.selectedProject = event.target.value || '';
    }

    // ---------------------------------------------------------------
    // Modals (Figma p57 / p58 form, p59 success)
    // ---------------------------------------------------------------

    handleOpenRequestModal() {
        this.form = { ...EMPTY_FORM };
        this.showValidation = false;
        this.isRequestModalOpen = true;
        this.focusModalPending = true;
    }

    handleCloseRequestModal() {
        this.isRequestModalOpen = false;
    }

    handleCloseSuccessModal() {
        this.isSuccessModalOpen = false;
        this.successTitle = '';
        this.successMessage = '';
    }

    closeOpenModal() {
        if (this.isSuccessModalOpen) {
            this.handleCloseSuccessModal();
        } else if (this.isRequestModalOpen) {
            this.handleCloseRequestModal();
        }
    }

    // close on a click on the dimmed overlay only (not when a text selection inside the panel ends outside it)
    handleOverlayMouseDown(event) {
        this.overlayPointerDown = event.target === event.currentTarget;
    }

    handleOverlayClick(event) {
        const onOverlay = event.target === event.currentTarget && this.overlayPointerDown;
        this.overlayPointerDown = false;
        if (onOverlay) {
            this.closeOpenModal();
        }
    }

    handleModalKeydown(event) {
        if (event.key === 'Escape' || event.key === 'Esc') {
            event.stopPropagation();
            this.closeOpenModal();
        }
    }

    // ---------------------------------------------------------------
    // Select an issue (issue, property, unit, subject, description)
    // ---------------------------------------------------------------

    get issueOptionsView() {
        return this.issueOptions.map((o) => ({ ...o, selected: o.value === this.form.issue }));
    }

    get isIssueEmpty() {
        return !this.form.issue;
    }

    get selectedIssue() {
        return this.issueOptions.find((o) => o.value === this.form.issue) || null;
    }

    get isDlpIssue() {
        const selected = this.selectedIssue;
        return !!(selected && selected.value === 'DLP Issue');
    }



    // ---------------------------------------------------------------
    // Select Property -> Select Unit
    // ---------------------------------------------------------------

    get propertyOptionsView() {
        return this.propertyOptions.map((o) => ({ ...o, selected: o.value === this.form.property }));
    }

    get isPropertyEmpty() {
        return !this.form.property;
    }

    get unitOptionsView() {
        const group = this.projectUnitGroups.find((g) => g.project === this.form.property);
        const units = group && group.units ? group.units : [];
        return units.map((o) => ({ ...o, selected: o.value === this.form.unitNumber }));
    }

    get isUnitEmpty() {
        return !this.form.unitNumber;
    }

    // ---------------------------------------------------------------
    // DLP cascade: Location -> Master Category -> Sub Category
    // ---------------------------------------------------------------

    get dlpLocationOptionsView() {
        return this.dlpLocations.map((l) => ({
            label: l.label,
            value: l.value,
            selected: l.value === this.form.dlpLocation
        }));
    }

    get isDlpLocationEmpty() {
        return !this.form.dlpLocation;
    }

    get selectedDlpLocation() {
        return this.dlpLocations.find((l) => l.value === this.form.dlpLocation) || null;
    }

    get showMasterCategoryField() {
        return this.isDlpIssue && !!this.form.dlpLocation;
    }

    get dlpMasterCategoryOptionsView() {
        const loc = this.selectedDlpLocation;
        const masters = loc && loc.masterCategories ? loc.masterCategories : [];
        return masters.map((m) => ({
            label: m.label,
            value: m.value,
            selected: m.value === this.form.dlpMasterCategory
        }));
    }

    get isDlpMasterCategoryEmpty() {
        return !this.form.dlpMasterCategory;
    }

    get selectedDlpMasterCategory() {
        const loc = this.selectedDlpLocation;
        if (!loc || !loc.masterCategories) return null;
        return loc.masterCategories.find((m) => m.value === this.form.dlpMasterCategory) || null;
    }

    get showSubCategoryField() {
        return this.isDlpIssue && !!this.form.dlpMasterCategory;
    }

    get dlpSubCategoryOptionsView() {
        const master = this.selectedDlpMasterCategory;
        const subs = master && master.subCategories ? master.subCategories : [];
        return subs.map((s) => ({
            label: s.label,
            value: s.value,
            selected: s.value === this.form.dlpSubCategory
        }));
    }

    get isDlpSubCategoryEmpty() {
        return !this.form.dlpSubCategory;
    }

    // ---------------------------------------------------------------
    // Field changes; each reset follows the real dependency between the fields
    // ---------------------------------------------------------------

    handleFieldChange(event) {
        const field = event.currentTarget.dataset.field;
        const value = event.currentTarget.value;
        const updated = { ...this.form, [field]: value };

        if (field === 'property') {
            updated.unitNumber = '';
        } else if (field === 'issue') {
            const selected = this.issueOptions.find((o) => o.value === value);
            if (!selected || !selected.requiresDetails) {
                updated.subject = updated.subject || '';
            }
            updated.dlpLocation = '';
            updated.dlpMasterCategory = '';
            updated.dlpSubCategory = '';
        } else if (field === 'dlpLocation') {
            updated.dlpMasterCategory = '';
            updated.dlpSubCategory = '';
        } else if (field === 'dlpMasterCategory') {
            updated.dlpSubCategory = '';
        }

        this.form = updated;
    }

    validationErrors() {
        const f = this.form;
        const errs = {};
        if (!f.property) errs.property = ERRORS.property;
        if (!f.unitNumber || !f.unitNumber.trim()) errs.unitNumber = ERRORS.unitNumber;
        if (!f.issue) errs.issue = ERRORS.issue;

        if (this.isDlpIssue) {
            if (!f.dlpLocation) errs.dlpLocation = ERRORS.dlpLocation;
            if (!f.dlpMasterCategory) errs.dlpMasterCategory = ERRORS.dlpMasterCategory;
            if (!f.dlpSubCategory) errs.dlpSubCategory = ERRORS.dlpSubCategory;
        }

        if (!f.subject || !f.subject.trim()) {
            errs.subject = ERRORS.subject;
        }
        if (!f.description || !f.description.trim()) errs.description = ERRORS.description;
        return errs;
    }

    get errors() {
        return this.showValidation ? this.validationErrors() : {};
    }

    get isFormComplete() {
        return Object.keys(this.validationErrors()).length === 0;
    }

    // Figma p57 greys the button out until the form is complete; it stays clickable so a click lists what is missing
    get submitAriaDisabled() {
        return this.isFormComplete ? 'false' : 'true';
    }

    get issueSelectClass() {
        return selectClass(this.isIssueEmpty, !!this.errors.issue);
    }

    get propertySelectClass() {
        return selectClass(this.isPropertyEmpty, !!this.errors.property);
    }

    get unitSelectClass() {
        return selectClass(this.isUnitEmpty, !!this.errors.unitNumber);
    }

    get dlpLocationSelectClass() {
        return selectClass(this.isDlpLocationEmpty, !!this.errors.dlpLocation);
    }

    get dlpMasterCategorySelectClass() {
        return selectClass(this.isDlpMasterCategoryEmpty, !!this.errors.dlpMasterCategory);
    }

    get dlpSubCategorySelectClass() {
        return selectClass(this.isDlpSubCategoryEmpty, !!this.errors.dlpSubCategory);
    }

    get subjectInputClass() {
        return this.errors.subject ? 'cp-input cp-input_invalid' : 'cp-input';
    }

    get descriptionClass() {
        return this.errors.description ? 'cp-textarea sr-textarea cp-input_invalid' : 'cp-textarea sr-textarea';
    }

    async handleSubmit() {
        this.showValidation = true;
        if (Object.keys(this.validationErrors()).length > 0 || this.isSubmitting) {
            return;
        }

        this.isSubmitting = true;
        this.submitError = undefined;
        try {
            const response = await createServiceRequest({
                issueType: this.form.issue,
                propertyName: this.form.property,
                unitNumber: this.form.unitNumber.trim(),
                subject: this.form.subject.trim(),
                description: this.form.description.trim(),
                dlpLocation: this.isDlpIssue ? this.form.dlpLocation : '',
                dlpMasterCategory: this.isDlpIssue ? this.form.dlpMasterCategory : '',
                dlpSubCategory: this.isDlpIssue ? this.form.dlpSubCategory : ''
            });

            if (response && response.success === false) {
                this.submitError = LABELS.submitErrorMessage;
                return;
            }

            this.isRequestModalOpen = false;
            this.successTitle = (response && response.title) || LABELS.successTitle;
            this.successMessage = (response && response.message) || LABELS.successMessage;
            this.isSuccessModalOpen = true;
            this.focusModalPending = true;

            refreshApex(this.wiredResult).catch((error) => {
                console.error('Refresh after submit failed', error);
            });
        } catch (error) {
            // Toasts do not show on this site: the reason stays in the popup, in the server's words when they read
            // like a sentence for the customer
            console.error('Error raising service request', error);
            const message = (error && error.body && error.body.message) || '';
            const readable = message && message.length < 200 && !/exception|system\.|field_|invalid_|apex|script-thrown/i.test(message);
            this.submitError = readable ? message : LABELS.submitErrorMessage;
        } finally {
            this.isSubmitting = false;
        }
    }

}