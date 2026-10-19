import { LightningElement, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getLeads from '@salesforce/apex/partnerWebPortalLeadController.getLeads';
import getLeadFilters from '@salesforce/apex/partnerWebPortalLeadController.getLeadFilters';
import getProjectOptions from '@salesforce/apex/partnerWebPortalLeadController.getProjectOptions';
import getBudgetOptions from '@salesforce/apex/partnerWebPortalLeadController.getBudgetOptions';
import exportCSV from '@salesforce/apex/partnerWebPortalLeadController.exportCSV';
import createLead from '@salesforce/apex/partnerWebPortalLeadController.createLead';

const LABELS = {
    PENDING_APPROVAL_STAGE: 'Pending approval',
    PHONE_INVALID: 'Please enter a valid Mobile Number: 9 to 15 digits, with an optional + and spaces, brackets or dashes.'
};

const EXPORT_ERROR = 'The leads could not be exported. Please try again.';

// The Mobile Number check Salesforce makes (LeadLogicController.isPhoneNumber): digits with spaces, brackets or dashes
// and an optional leading +, holding 9 to 15 digits without a leading 0
const PHONE_PATTERN = /^\+?[0-9 ()-]+$/;
const MIN_PHONE_DIGITS = 9;
const MAX_PHONE_DIGITS = 15;

function isPhone(value) {
    const text = (value || '').trim();
    const digits = text.replace(/\D/g, '').replace(/^0+/, '').length;
    return PHONE_PATTERN.test(text) && digits >= MIN_PHONE_DIGITS && digits <= MAX_PHONE_DIGITS;
}

// Stage badge colours by Lead Status, in the groups of the page's filters
const BADGES = {
    'Site Visit Scheduled': 'badge badge-scheduled',
    New: 'badge badge-active',
    Assigned: 'badge badge-active',
    'In-Discussion': 'badge badge-active',
    Contacted: 'badge badge-active',
    Qualified: 'badge badge-active',
    Visited: 'badge badge-visited',
    Converted: 'badge badge-booked',
    'Not Reachable': 'badge badge-active',
    'Not Interested': 'badge badge-lost',
    'Not Qualified': 'badge badge-lost',
    'Site Visit Done by Other Agent': 'badge badge-cancelled',
    // A CP lead waiting for the Direct Sales Manager's and JKP CP Manager's approval
    [LABELS.PENDING_APPROVAL_STAGE]: 'badge badge-pending'
};

export default class PartnerWebPortalLead extends LightningElement {

    PAGE_SIZE = 10;

    // ---------- LIST STATE ----------
    @track searchKey = '';
    // A filter's key, or blank for all the team's leads (the first chip) until one is chosen
    @track activeFilter = '';
    @track currentPage = 1;
    @track successMessage = '';
    @track errorMessage = '';
    // The lead in the Edit popup, and the confirmation once it is saved
    editLeadId = null;
    docsLeadId = null;
    infoMessage = '';
    // Brings the error banner into view once it is rendered (showError)
    scrollToError = false;
    // The channel partner lead rules' notice: { message, approval } (approval: no lead yet, it awaits approval)
    leadNotice = null;

    leads = [];
    totalRecords = 0;
    totalPages = 0;
    pageSize = this.PAGE_SIZE;

    filterTabs = [];
    wiredLeadsResult;
    searchTimeout;

    // ---------- FORM STATE ----------
    @track isFormView = false;
    @track isSaving = false;

    @track form = {
        fullName: '',
        company: '',
        email: '',
        phone: '',
        address: '',
        project: '',
        budget: '',
        description: ''
    };

    projectOptions = [];
    budgetOptions = [];

    // ---------- WIRE: PROJECT OPTIONS ----------
    @wire(getProjectOptions)
    wiredProjectOptions({ data, error }) {
        if (data) {
            this.projectOptions = data.map(function(opt) {
                return { label: opt.label, value: opt.value };
            });
        } else if (error) {
            console.error('Project options error:', error);
        }
    }

    // ---------- WIRE: BUDGET OPTIONS ----------
    @wire(getBudgetOptions)
    wiredBudgetOptions({ data, error }) {
        if (data) {
            this.budgetOptions = data.map(function(opt) {
                return { label: opt.label, value: opt.value };
            });
        } else if (error) {
            console.error('Budget options error:', error);
        }
    }

    // ---------- WIRE: FILTER TABS (Partner Portal Lead Filter records) ----------
    @wire(getLeadFilters)
    wiredFilters({ data, error }) {
        if (data) this.filterTabs = data;
        else if (error) console.error('Lead filters error:', error);
    }

    // ---------- WIRE: LEADS ----------
    @wire(getLeads, {
        filterKey: '$activeFilter',
        searchKey: '$searchKey',
        pageNumber: '$currentPage',
        pageSize: '$pageSize'
    })
    wiredLeads(result) {
        this.wiredLeadsResult = result;
        var data = result.data;
        var error = result.error;

        if (data) {
            var self = this;
            this.leads = data.leads.map(function(l) {
                return Object.assign({}, l, {
                    badgeClass: self.getBadgeClass(l.stage),
                    editLabel: 'Edit ' + l.leadName,
                    documentsLabel: 'Documents of ' + l.leadName,
                    viewLabel: 'View only: ' + (l.readOnlyReason || l.leadName)
                });
            });
            this.totalRecords = data.totalRecords;
            this.totalPages = data.totalPages;
        } else if (error) {
            console.error('Leads error:', error);
            this.leads = [];
            this.totalRecords = 0;
            this.totalPages = 0;
        }
    }

    // ---------- GETTERS ----------
    get filterButtons() {
        var self = this;
        return this.filterTabs.map(function(tab, index) {
            var active = tab.key === self.activeFilter || (!self.activeFilter && index === 0);
            return {
                label: tab.label,
                value: tab.key,
                pressed: String(active),
                className: active ? 'filter-btn active' : 'filter-btn'
            };
        });
    }

    get activeFilterLabel() {
        var active = this.filterButtons.find(function(tab) { return tab.pressed === 'true'; });
        return active ? active.label : 'All';
    }

    get hasLeads() { return this.leads && this.leads.length > 0; }
    get noLeads()  { return !this.hasLeads; }

    get entriesText() {
        if (this.totalRecords === 0) return 'Showing 0 entries';
        var start = (this.currentPage - 1) * this.pageSize + 1;
        var end = Math.min(this.currentPage * this.pageSize, this.totalRecords);
        return 'Showing ' + start + ' to ' + end + ' of ' + this.totalRecords + ' entries';
    }

    get isPrevDisabled() { return this.currentPage <= 1; }
    get isNextDisabled() { return this.currentPage >= this.totalPages; }

    get paginationButtons() {
        var pages = [];
        for (var i = 1; i <= this.totalPages; i++) {
            pages.push({
                value: i,
                label: String(i),
                className: i === this.currentPage ? 'page-num active' : 'page-num'
            });
        }
        return pages;
    }

    get saveButtonLabel() {
        return this.isSaving ? 'Saving...' : 'Register Lead';
    }

    getBadgeClass(stage) {
        return BADGES[stage] || 'badge badge-neutral';
    }

    // ---------- LIST HANDLERS ----------
    handleNavigation() {
        this.form = {
            fullName: '',
            company: '',
            email: '',
            phone: '',
            address: '',
            project: '',
            budget: '',
            description: ''
        };
        this.errorMessage = '';
        this.isFormView = true;
    }

    handleSearch(event) {
        var value = event.target.value;
        var self = this;
        window.clearTimeout(this.searchTimeout);
        this.searchTimeout = window.setTimeout(function() {
            self.searchKey = value;
            self.currentPage = 1;
        }, 400);
    }

    handleFilterClick(event) {
        this.activeFilter = event.currentTarget.dataset.value;
        this.currentPage = 1;
    }

    handlePageClick(event) {
        this.currentPage = parseInt(event.currentTarget.dataset.value, 10);
    }

    handlePrev() { if (this.currentPage > 1) this.currentPage--; }
    handleNext() { if (this.currentPage < this.totalPages) this.currentPage++; }

    // Downloads the leads of the chosen filter and search as a CSV file Excel opens (UTF-8 with a byte-order mark)
    async handleExport() {
        this.errorMessage = '';
        try {
            var csv = await exportCSV({
                filterKey: this.activeFilter,
                searchKey: this.searchKey
            });
            var content = '\uFEFF' + csv;
            var link = document.createElement('a');
            var url;
            try {
                url = URL.createObjectURL(new Blob([content], { type: 'text/csv;charset=utf-8' }));
            } catch (blobError) {
                url = 'data:text/csv;charset=utf-8,' + encodeURIComponent(content);
            }
            link.href = url;
            link.download = this.exportFileName;
            link.click();
            if (url.indexOf('blob:') === 0) {
                window.setTimeout(function() { URL.revokeObjectURL(url); }, 1000);
            }
        } catch (e) {
            console.error('Export error:', e);
            this.errorMessage = EXPORT_ERROR;
        }
    }

    // For example "Leads - Active-Nurturing - 2026-10-03.csv"
    get exportFileName() {
        var today = new Date();
        var pad = function(n) { return n < 10 ? '0' + n : String(n); };
        var date = today.getFullYear() + '-' + pad(today.getMonth() + 1) + '-' + pad(today.getDate());
        return 'Leads - ' + this.activeFilterLabel.replace(/[\\/:*?"<>|]/g, '-') + ' - ' + date + '.csv';
    }

    // ---------- FORM HANDLERS ----------
    handleFormChange(event) {
        var field = event.target.dataset.field;
        var value = event.target.value;

        this.form = Object.assign({}, this.form, {
            [field]: value
        });
        this.errorMessage = ''; // Clear error on user edit
    }

    handleFormCancel() {
        this.errorMessage = '';
        this.isFormView = false;
    }

    handleCloseError() {
        this.errorMessage = '';
    }

    get showSuccess() {
        return Boolean(this.successMessage || this.leadNotice);
    }

    get isApprovalRequested() {
        return Boolean(this.leadNotice && this.leadNotice.approval);
    }

    get successTitle() {
        return this.isApprovalRequested ? 'Approval requested' : 'New Lead has been created!';
    }

    // ---------- EDIT POPUP ----------

    handleEdit(event) {
        this.infoMessage = '';
        this.editLeadId = event.currentTarget.dataset.id;
    }

    // ---------- DOCUMENTS POPUP ----------

    handleDocuments(event) {
        this.infoMessage = '';
        this.docsLeadId = event.currentTarget.dataset.id;
    }

    handleDocumentsClose() {
        this.docsLeadId = null;
        if (this.wiredLeadsResult) {
            refreshApex(this.wiredLeadsResult);
        }
    }

    // The list is refreshed too: a lead the popup refused (changed meanwhile) shows its current state
    handleEditClose() {
        this.editLeadId = null;
        if (this.wiredLeadsResult) {
            refreshApex(this.wiredLeadsResult);
        }
    }

    handleEditSaved(event) {
        this.editLeadId = null;
        this.infoMessage = event.detail && event.detail.message ? event.detail.message : '';
        if (this.wiredLeadsResult) {
            refreshApex(this.wiredLeadsResult);
        }
        if (this.infoMessage) {
            const shown = this.infoMessage;
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            window.setTimeout(() => {
                if (this.infoMessage === shown) {
                    this.infoMessage = '';
                }
            }, 6000);
        }
    }

    handleCloseInfo() {
        this.infoMessage = '';
    }

    handleCloseSuccess() {
        this.successMessage = '';
        this.leadNotice = null;
    }

    async handleRegisterLead() {
        this.errorMessage = '';

        // Force sync from DOM
        this.template.querySelectorAll('input, select, textarea').forEach(function(input) {
            var field = input.dataset && input.dataset.field ? input.dataset.field : null;
            if (field && input.type !== 'file' && input.type !== 'checkbox') {
                this.form[field] = input.value;
            }
        }.bind(this));

        // Client-side Validations
        if (!this.form.fullName || !this.form.fullName.trim()) {
            this.showError('Full Name is required.');
            return;
        }
        if (!this.form.phone || !this.form.phone.trim()) {
            this.showError('Mobile Number is required.');
            return;
        }
        if (!isPhone(this.form.phone)) {
            this.showError(LABELS.PHONE_INVALID);
            return;
        }
        if (!this.form.email || !this.form.email.trim()) {
            this.showError('Email ID is required.');
            return;
        }
        if (!this.form.project) {
            this.showError('Please select an Interested Project.');
            return;
        }
        if (!this.form.budget) {
            this.showError('Please select a valid Budget Aligned.');
            return;
        }

        this.isSaving = true;

        try {
            var result = await createLead({
                fullName:    this.form.fullName ? this.form.fullName.trim() : '',
                company:     this.form.company ? this.form.company.trim() : '',
                email:       this.form.email ? this.form.email.trim() : '',
                phone:       this.form.phone ? this.form.phone.trim() : '',
                address:     this.form.address ? this.form.address.trim() : '',
                project:     this.form.project ? this.form.project.trim() : '',
                budget:      this.form.budget ? this.form.budget.trim() : '',
                description: this.form.description ? this.form.description.trim() : ''
            });

            this.isFormView = false;
            if (result && result.outcome === 'APPROVAL_REQUESTED') {
                // Direct Sales has the customer: the lead is saved as Pending approval and waits for both managers
                this.successMessage = 'Lead ID: ' + result.leadId + ' (' + LABELS.PENDING_APPROVAL_STAGE + ')';
                this.leadNotice = { message: result.message, approval: true };
            } else {
                this.successMessage = 'Lead created successfully! Lead ID: ' + (result ? result.leadId : '');
                this.leadNotice = result && result.outcome === 'CREATED_WITH_NOTICE' ? { message: result.message, approval: false } : null;
                if (!this.leadNotice) {
                    // Auto-hide success message after 7 seconds; a notice stays until it is closed
                    var self = this;
                    window.setTimeout(function() {
                        self.successMessage = '';
                    }, 7000);
                }
            }

            if (this.wiredLeadsResult) {
                refreshApex(this.wiredLeadsResult);
            }

        } catch (err) {
            console.error('Lead creation error:', err);
            var msg = 'Failed to register lead';
            if (err && err.body && err.body.message) {
                msg = err.body.message;
            } else if (err && err.message) {
                msg = err.message;
            }
            this.showError(msg);
        } finally {
            this.isSaving = false;
        }
    }

    // Shows the form's error banner and brings it into view: Register Lead is at the bottom of a long form, the
    // banner at its top
    showError(message) {
        this.errorMessage = message;
        this.scrollToError = true;
    }

    renderedCallback() {
        if (!this.scrollToError) {
            return;
        }
        const banner = this.template.querySelector('.error-banner');
        if (banner) {
            this.scrollToError = false;
            if (typeof banner.scrollIntoView === 'function') {
                banner.scrollIntoView({ behavior: 'smooth', block: 'center' });
            }
            banner.focus();
        }
    }
}