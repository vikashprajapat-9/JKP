import { LightningElement, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getSiteVisit from '@salesforce/apex/partnerWebPortalSiteVisit.getSiteVisit';
import getStageOptions from '@salesforce/apex/partnerWebPortalSiteVisit.getStageOptions';
import getCustomerOptions from '@salesforce/apex/partnerWebPortalSiteVisit.getCustomerOptions';
import getProjectOptions from '@salesforce/apex/partnerWebPortalSiteVisit.getProjectOptions';
import exportCSV from '@salesforce/apex/partnerWebPortalSiteVisit.exportCSV';
import createSiteVisit from '@salesforce/apex/partnerWebPortalSiteVisit.createSiteVisit';
import getRequirementTypeOptions from '@salesforce/apex/partnerWebPortalSiteVisit.getRequirementTypeOptions';
import REQUEST_NOTE from '@salesforce/label/c.Partner_Visit_Request_Note';
import SUCCESS_TITLE from '@salesforce/label/c.Partner_Visit_Success_Title';
import SUCCESS_TEXT from '@salesforce/label/c.Partner_Visit_Success_Text';
import DATE_PAST from '@salesforce/label/c.Partner_Visit_Date_Past';
import PROJECT_HINT from '@salesforce/label/c.Partner_Visit_Project_Hint';
import PROJECT_PLACEHOLDER from '@salesforce/label/c.Partner_Visit_Project_Placeholder';
import PROJECT_CHOOSE_HINT from '@salesforce/label/c.Partner_Visit_Project_Choose_Hint';

const EXPORT_ERROR = 'The site visits could not be exported. Please try again.';

// Every field of the Request Site Visit form is required, in the order the form shows them
const REQUIRED_FIELDS = ['leadId', 'projectId', 'requirementType', 'visitDate', 'visitTime', 'description'];
const MISSING = {
    leadId: 'Choose the customer.',
    projectId: 'Choose the project.',
    requirementType: 'Choose the requirement type.',
    visitDate: 'Choose the visit date.',
    visitTime: 'Enter the visit time.',
    description: 'Enter a description.'
};
const WRONG_TIME = 'Enter a valid visit time, for example 10:30 AM.';

// The next full hour as the form's hours, minutes and AM/PM (4:00 PM at 3:20 PM): a time still ahead for a visit today;
// 10:00 AM late at night (the visit is then for another day)
function nextHour() {
    const hour = new Date().getHours() + 1;
    if (hour > 23) {
        return { hours: '10', minutes: '00', period: 'AM' };
    }
    const twelve = hour % 12 === 0 ? 12 : hour % 12;
    return { hours: String(twelve).padStart(2, '0'), minutes: '00', period: hour < 12 ? 'AM' : 'PM' };
}

// Today where the partner is, as yyyy-mm-dd (toISOString would give the UTC date, yesterday early in the morning in Sri Lanka)
function localToday() {
    const now = new Date();
    const pad = n => String(n).padStart(2, '0');
    return now.getFullYear() + '-' + pad(now.getMonth() + 1) + '-' + pad(now.getDate());
}

export default class PartnerWebPortalSiteVisit extends LightningElement {

    PAGE_SIZE = 10;

    // ---------- LIST STATE ----------
    @track searchKey = '';
    @track activeFilter = 'All';
    @track currentPage = 1;
    @track successMessage = '';
    @track errorMessage = '';
    @track showSuccessModal = false;

    visits = [];
    totalRecords = 0;
    totalPages = 0;
    pageSize = this.PAGE_SIZE;

    filterTabs = ['All'];
    wiredVisitsResult;
    wiredCustomersResult;
    searchTimeout;

    // ---------- FORM STATE ----------
    @track isFormView = false;
    @track isSaving = false;

    @track form = {
        leadId: '',
        projectId: '',
        requirementType: '',
        visitDate: '',
        description: ''
    };

    labels = {
        requestNote: REQUEST_NOTE,
        successTitle: SUCCESS_TITLE,
        successText: SUCCESS_TEXT,
        projectPlaceholder: PROJECT_PLACEHOLDER
    };

    // Fields left empty show their message; after Confirm Site Visit every missing field does
    touched = {};
    submitAttempted = false;

    // Time picker states
    @track timeHours = '10';
    @track timeMinutes = '00';
    @track timePeriod = 'AM';

    customerOptions = [];
    projectOptions = [];
    requirementTypeOptions = [];
    rawCustomerList = [];

    // ---------- WIRE: CUSTOMERS (LEADS) ----------
    @wire(getCustomerOptions)
    wiredCustomers(result) {
        this.wiredCustomersResult = result;
        const data = result.data;
        const error = result.error;
        if (data) {
            this.rawCustomerList = data;
            this.customerOptions = data.map(cust => ({
                label: cust.label,
                value: cust.value
            }));
            // The list is reloaded when the form opens: a customer chosen before it came back takes its lead's project
            // as it is now, so that the request is for the project the form shows
            const chosen = data.find(cust => cust.value === this.form.leadId);
            if (chosen && chosen.projectId && chosen.projectId !== this.form.projectId) {
                this.form = Object.assign({}, this.form, { projectId: chosen.projectId });
            }
        } else if (error) {
            console.error('Customer options error:', error);
        }
    }

    // ---------- WIRE: PROJECTS ----------
    @wire(getProjectOptions)
    wiredProjects({ data, error }) {
        if (data) {
            this.projectOptions = data.map(proj => ({
                label: proj.label,
                value: proj.value
            }));
        } else if (error) {
            console.error('Project options error:', error);
        }
    }

    // ---------- WIRE: REQUIREMENT TYPES ----------
    @wire(getRequirementTypeOptions)
    wiredRequirementTypes({ data, error }) {
        if (data) {
            this.requirementTypeOptions = data.map(option => ({ label: option.label, value: option.value }));
        } else if (error) {
            console.error('Requirement type options error:', error);
        }
    }

    // ---------- WIRE: STATUS FILTER TABS ----------
    @wire(getStageOptions)
    wiredStages({ data, error }) {
        if (data) this.filterTabs = data;
        else if (error) console.error('Status options error:', error);
    }

    // ---------- WIRE: VISITS ----------
    @wire(getSiteVisit, {
        stageFilter: '$activeFilter',
        searchKey: '$searchKey',
        pageNumber: '$currentPage',
        pageSize: '$pageSize'
    })
    wiredSiteVisit(result) {
        this.wiredVisitsResult = result;
        const data = result.data;
        const error = result.error;

        if (error) {
            console.error('❌ Site Visit wire error:', error);
            this.visits = [];
            this.totalRecords = 0;
            this.totalPages = 0;
            return;
        }

        if (!data) return;

        const rows = (data.visits || []).map(v => {
            const row = {
                Id: v.visitName ? v.visitName : 'visit',
                rowNo: v.rowNo,
                Name: v.visitName,
                formattedDate: v.createdDate,
                leadName: v.leadName,
                channelPartner: v.channelPartner,
                projectName: v.projectName,
                visitDate: v.visitDate,
                status: v.status
            };
            row.badgeClass = this.getBadgeClass(row.status);
            return row;
        });

        this.visits = rows;
        this.totalRecords = data.totalRecords;
        this.totalPages = data.totalPages;
    }

    // ---------- BADGE COLORS ----------
    getBadgeClass(status) {
        const val = (status || '').toLowerCase();
        if (val.includes('requested')) return 'badge badge-requested';    // Waiting for JKP's approval
        if (val.includes('rejected')) return 'badge badge-cancelled';     // Red
        if (val.includes('not visited')) return 'badge badge-ended';      // Grey: the customer did not come
        if (val.includes('incomplete')) return 'badge badge-incomplete';  // Amber
        if (val.includes('completed')) return 'badge badge-completed';    // Green
        if (val.includes('upcoming') || val.includes('scheduled')) return 'badge badge-scheduled'; // Light orange
        if (val.includes('cancel')) return 'badge badge-cancelled';       // Red
        if (val.includes('ended')) return 'badge badge-ended';            // Grey
        return 'badge badge-default';                                     // Blue
    }

    // ---------- TIME GETTERS & HANDLERS ----------
    get amButtonClass() {
        return 'toggle-pill ' + (this.timePeriod === 'AM' ? 'active' : '');
    }

    get pmButtonClass() {
        return 'toggle-pill ' + (this.timePeriod === 'PM' ? 'active' : '');
    }

    handleSelectAM() { this.timePeriod = 'AM'; }
    handleSelectPM() { this.timePeriod = 'PM'; }

    handleHourChange(event) {
        let val = event.target.value.replace(/\D/g, '');
        if (val.length > 2) val = val.substring(0, 2);
        this.timeHours = val;
    }

    handleMinuteChange(event) {
        let val = event.target.value.replace(/\D/g, '');
        if (val.length > 2) val = val.substring(0, 2);
        this.timeMinutes = val;
    }

    // The project is the chosen lead's: a lead's site visits are for the project it was created for. An old lead without
    // a project leaves it empty, for the partner to choose from their projects.
    handleCustomerChange(event) {
        const selectedLeadId = event.target.value;
        const match = this.rawCustomerList.find(c => c.value === selectedLeadId);
        this.form = Object.assign({}, this.form, {
            leadId: selectedLeadId,
            projectId: match && match.projectId ? match.projectId : ''
        });
        this.errorMessage = '';
    }

    // The chosen customer (lead), with its project
    get selectedCustomer() {
        return this.rawCustomerList.find(c => c.value === this.form.leadId);
    }

    // An old lead without a project: the partner chooses the project, as before; otherwise it is shown read-only
    get chooseProject() {
        const customer = this.selectedCustomer;
        return Boolean(customer) && !customer.projectId;
    }

    get projectName() {
        const customer = this.selectedCustomer;
        return customer && customer.projectName ? customer.projectName : '';
    }

    // Why the chosen lead's project cannot have a site visit now (it is not open for site visits), or ''
    get projectUnavailableReason() {
        const customer = this.selectedCustomer;
        return customer && customer.projectUnavailableReason ? customer.projectUnavailableReason : '';
    }

    get projectHint() {
        return this.chooseProject ? PROJECT_CHOOSE_HINT : PROJECT_HINT;
    }

    // The options with the chosen one marked: a select's own value does not reliably show a choice made in code
    get customerChoices() {
        return this.customerOptions.map(option => ({ ...option, selected: option.value === this.form.leadId }));
    }

    get projectChoices() {
        return this.projectOptions.map(option => ({ ...option, selected: option.value === this.form.projectId }));
    }

    get requirementTypeChoices() {
        return this.requirementTypeOptions.map(option => ({ ...option, selected: option.value === this.form.requirementType }));
    }

    get todayDate() {
        return localToday();
    }

    get hasVisits() { return Array.isArray(this.visits) && this.visits.length > 0; }

    get filterButtons() {
        return this.filterTabs.map(tab => ({
            label: tab,
            value: tab,
            pressed: String(tab === this.activeFilter),
            className: tab === this.activeFilter ? 'filter-btn active' : 'filter-btn'
        }));
    }

    get noVisits() { return !this.hasVisits; }

    get entriesText() {
        if (this.totalRecords === 0) return 'Showing 0 entries';
        const start = (this.currentPage - 1) * this.pageSize + 1;
        const end = Math.min(this.currentPage * this.pageSize, this.totalRecords);
        return 'Showing ' + start + ' to ' + end + ' of ' + this.totalRecords + ' entries';
    }

    get isPrevDisabled() { return this.currentPage <= 1; }
    get isNextDisabled() { return this.currentPage >= this.totalPages; }

    get paginationButtons() {
        const pages = [];
        for (let i = 1; i <= this.totalPages; i++) {
            pages.push({
                value: i,
                label: String(i),
                className: i === this.currentPage ? 'page-num active' : 'page-num'
            });
        }
        return pages;
    }

    get isConfirmDisabled() {
        return this.isSaving;
    }

    // ---------- REQUIRED FIELDS ----------
    isTimeEmpty() {
        return !String(this.timeHours || '').trim() || !String(this.timeMinutes || '').trim();
    }

    isTimeValid() {
        const hours = Number(this.timeHours);
        const minutes = Number(this.timeMinutes);
        return /^\d{1,2}$/.test(String(this.timeHours)) && /^\d{1,2}$/.test(String(this.timeMinutes))
            && hours >= 1 && hours <= 12 && minutes >= 0 && minutes <= 59;
    }

    isComplete(field) {
        if (field === 'visitTime') return !this.isTimeEmpty() && this.isTimeValid();
        if (field === 'visitDate' && this.form.visitDate && this.form.visitDate < localToday()) return false;
        if (field === 'projectId' && this.projectUnavailableReason) return false;
        return String(this.form[field] || '').trim() !== '';
    }

    // A missing value shows once the field is left or Confirm Site Visit is pressed; a wrong time shows at once
    problemOf(field) {
        // The lead's project is filled in, not chosen: it only shows why it cannot have a site visit now
        if (field === 'projectId' && !this.chooseProject) {
            return this.projectUnavailableReason;
        }
        const empty = field === 'visitTime' ? this.isTimeEmpty() : String(this.form[field] || '').trim() === '';
        if (empty) {
            return this.touched[field] || this.submitAttempted ? MISSING[field] : '';
        }
        if (field === 'visitDate' && this.form.visitDate < localToday()) {
            return DATE_PAST;
        }
        return field === 'visitTime' && !this.isTimeValid() ? WRONG_TIME : '';
    }

    get customerError() { return this.problemOf('leadId'); }
    get projectError() { return this.problemOf('projectId'); }
    get requirementTypeError() { return this.problemOf('requirementType'); }
    get dateError() { return this.problemOf('visitDate'); }
    get timeError() { return this.problemOf('visitTime'); }
    get descriptionError() { return this.problemOf('description'); }

    get customerClass() { return this.customerError ? 'form-control invalid' : 'form-control'; }
    get projectClass() {
        const className = this.chooseProject ? 'form-control' : 'form-control form-control-readonly';
        return this.projectError ? className + ' invalid' : className;
    }
    get requirementTypeClass() { return this.requirementTypeError ? 'form-control invalid' : 'form-control'; }
    get dateClass() { return this.dateError ? 'form-control invalid' : 'form-control'; }
    get timeBoxClass() { return this.timeError ? 'time-picker-box invalid' : 'time-picker-box'; }
    get descriptionClass() { return this.descriptionError ? 'form-control form-textarea invalid' : 'form-control form-textarea'; }

    get customerInvalid() { return String(Boolean(this.customerError)); }
    get projectInvalid() { return String(Boolean(this.projectError)); }
    get requirementTypeInvalid() { return String(Boolean(this.requirementTypeError)); }
    get dateInvalid() { return String(Boolean(this.dateError)); }
    get timeInvalid() { return String(Boolean(this.timeError)); }
    get descriptionInvalid() { return String(Boolean(this.descriptionError)); }

    handleBlur(event) {
        this.touched = { ...this.touched, [event.target.dataset.field]: true };
    }

    // The first field to fix gets the cursor; for the time, the box that is empty or wrong
    focusOn(field) {
        let selector = `[data-field="${field}"]`;
        if (field === 'visitTime') {
            const hours = Number(this.timeHours);
            const hoursFine = /^\d{1,2}$/.test(String(this.timeHours)) && hours >= 1 && hours <= 12;
            selector = `[data-part="${hoursFine ? 'minutes' : 'hours'}"]`;
        }
        const target = this.template.querySelector(selector);
        if (target) target.focus();
    }

    // A select's value set in code shows only when set on the element itself, so the dropdowns follow the form
    renderedCallback() {
        if (!this.isFormView) return;
        ['leadId', 'projectId', 'requirementType'].forEach(field => {
            const select = this.template.querySelector(`select[data-field="${field}"]`);
            const value = this.form[field] || '';
            if (select && select.value !== value) select.value = value;
        });
    }

    // Keeps the cursor in the field while a button is pressed: leaving an empty field shows its message, which would
    // move the button away before the click lands
    keepFocus(event) {
        event.preventDefault();
    }

    get saveButtonLabel() {
        return this.isSaving ? 'Sending...' : 'Send Request';
    }

    // ---------- LIST HANDLERS ----------
    handleNavigation() {
        this.form = {
            leadId: '',
            projectId: '',
            requirementType: '',
            visitDate: localToday(),
            description: ''
        };
        const next = nextHour();
        this.timeHours = next.hours;
        this.timeMinutes = next.minutes;
        this.timePeriod = next.period;
        this.errorMessage = '';
        this.touched = {};
        this.submitAttempted = false;
        this.isFormView = true;
        // Leads added since the page loaded (for example on the Leads page) appear under Customer
        if (this.wiredCustomersResult) {
            refreshApex(this.wiredCustomersResult);
        }
    }

    handleSearch(event) {
        const value = event.target.value;
        window.clearTimeout(this.searchTimeout);
        this.searchTimeout = window.setTimeout(() => {
            this.searchKey = value;
            this.currentPage = 1;
        }, 400);
    }

    handleFilterClick(event) {
        this.activeFilter = event.currentTarget.dataset.value;
        this.currentPage = 1;
    }

    handlePageClick(event) {
        this.currentPage = Number(event.currentTarget.dataset.value);
    }

    handlePrev() { if (this.currentPage > 1) this.currentPage--; }
    handleNext() { if (this.currentPage < this.totalPages) this.currentPage++; }

    // Downloads the visits of the chosen status and search as a CSV file Excel opens (UTF-8 with a byte-order mark)
    async handleExport() {
        this.errorMessage = '';
        try {
            const csv = await exportCSV({
                stageFilter: this.activeFilter,
                searchKey: this.searchKey
            });
            const content = '\uFEFF' + csv;
            const link = document.createElement('a');
            let url;
            try {
                url = URL.createObjectURL(new Blob([content], { type: 'text/csv;charset=utf-8' }));
            } catch (blobError) {
                url = 'data:text/csv;charset=utf-8,' + encodeURIComponent(content);
            }
            link.href = url;
            link.download = this.exportFileName;
            link.click();
            if (url.indexOf('blob:') === 0) {
                window.setTimeout(() => URL.revokeObjectURL(url), 1000);
            }
        } catch (e) {
            console.error('Export error:', e);
            this.errorMessage = EXPORT_ERROR;
        }
    }

    // For example "Site Visits - Upcoming - 2026-10-03.csv"
    get exportFileName() {
        const today = new Date();
        const pad = n => (n < 10 ? '0' + n : String(n));
        const date = today.getFullYear() + '-' + pad(today.getMonth() + 1) + '-' + pad(today.getDate());
        return 'Site Visits - ' + String(this.activeFilter || 'All').replace(/[\\/:*?"<>|]/g, '-') + ' - ' + date + '.csv';
    }

    // ---------- FORM HANDLERS ----------
    handleFormChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.value;
        this.form = Object.assign({}, this.form, {
            [field]: value
        });
        this.errorMessage = '';
    }

    handleFormCancel() {
        this.errorMessage = '';
        this.isFormView = false;
    }

    handleCloseError() { this.errorMessage = ''; }
    handleCloseSuccess() {
        this.successMessage = '';
        this.showSuccessModal = false;
    }

    async handleRegisterVisit() {
        this.errorMessage = '';
        this.submitAttempted = true;
        const firstMissing = REQUIRED_FIELDS.find(field => !this.isComplete(field));
        if (firstMissing) {
            this.focusOn(firstMissing);
            return;
        }

        const formattedTime = String(Number(this.timeHours)).padStart(2, '0') + ':'
            + String(Number(this.timeMinutes)).padStart(2, '0') + ' ' + this.timePeriod;

        this.isSaving = true;
        try {
            const visitId = await createSiteVisit({
                leadId:      this.form.leadId,
                projectId:   this.form.projectId,
                requirementType: this.form.requirementType,
                visitDate:   this.form.visitDate,
                visitTime:   formattedTime,
                description: this.form.description.trim()
            });

            console.log('✅ Site Visit requested:', visitId);

            this.successMessage = SUCCESS_TEXT;
            this.isFormView = false;
            this.showSuccessModal = true;

            if (this.wiredVisitsResult) {
                refreshApex(this.wiredVisitsResult);
            }
            if (this.wiredCustomersResult) {
                refreshApex(this.wiredCustomersResult);
            }

            const self = this;
            window.setTimeout(() => {
                self.successMessage = '';
            }, 7000);

        } catch (err) {
            console.error('❌ Site Visit error:', err);
            const msg = (err && err.body && err.body.message) ? err.body.message : 'The site visit request could not be sent. Please try again.';
            this.errorMessage = msg;
        } finally {
            this.isSaving = false;
        }
    }
}