import { LightningElement, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getLeads from '@salesforce/apex/partnerWebPortalLeadController.getLeads';
import getStageOptions from '@salesforce/apex/partnerWebPortalLeadController.getStageOptions';
import getProjectOptions from '@salesforce/apex/partnerWebPortalLeadController.getProjectOptions';
import getBudgetOptions from '@salesforce/apex/partnerWebPortalLeadController.getBudgetOptions';
import exportCSV from '@salesforce/apex/partnerWebPortalLeadController.exportCSV';
import createLead from '@salesforce/apex/partnerWebPortalLeadController.createLead';

export default class PartnerWebPortalLead extends LightningElement {

    PAGE_SIZE = 10;

    // ---------- LIST STATE ----------
    @track searchKey = '';
    @track activeFilter = 'All';
    @track currentPage = 1;
    @track successMessage = '';
    @track errorMessage = '';

    leads = [];
    totalRecords = 0;
    totalPages = 0;
    pageSize = this.PAGE_SIZE;

    filterTabs = ['All'];
    wiredLeadsResult;
    searchTimeout;

    // ---------- FORM STATE ----------
    @track isFormView = false;
    @track isSaving = false;

    @track form = {
        fullName: '',
        company: '',
        leadSource: 'Partner Portal',
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

    // ---------- WIRE: FILTER TABS ----------
    @wire(getStageOptions)
    wiredStages({ data, error }) {
        if (data) this.filterTabs = data;
        else if (error) console.error('Stage options error:', error);
    }

    // ---------- WIRE: LEADS ----------
    @wire(getLeads, {
        stageFilter: '$activeFilter',
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
                    badgeClass: self.getBadgeClass(l.stage)
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
        return this.filterTabs.map(function(tab) {
            return {
                label: tab,
                value: tab,
                className: tab === self.activeFilter ? 'filter-btn active' : 'filter-btn'
            };
        });
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
        var map = {
            'Open - Not Contacted': 'badge badge-scheduled',
            'Working - Contacted': 'badge badge-active',
            'Closed - Converted': 'badge badge-booked',
            'Closed - Not Converted': 'badge badge-lost',
            Active: 'badge badge-active',
            Visited: 'badge badge-visited',
            Booked: 'badge badge-booked',
            Scheduled: 'badge badge-scheduled',
            Lost: 'badge badge-lost',
            New: 'badge badge-scheduled',
            Open: 'badge badge-scheduled',
            Contacted: 'badge badge-active',
            Working: 'badge badge-active',
            Qualified: 'badge badge-booked',
            Converted: 'badge badge-booked',
            Unqualified: 'badge badge-lost',
            Cancelled: 'badge badge-cancelled'
        };
        return map[stage] || 'badge badge-neutral';
    }

    // ---------- LIST HANDLERS ----------
    handleNavigation() {
        this.form = {
            fullName: '',
            company: '',
            leadSource: 'Partner Portal',
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

    async handleExport() {
        try {
            var base64 = await exportCSV({
                stageFilter: this.activeFilter,
                searchKey: this.searchKey
            });
            var link = document.createElement('a');
            link.href = 'data:text/csv;base64,' + base64;
            link.download = 'leads_export.csv';
            link.click();
        } catch (e) {
            console.error('Export error:', e);
            this.errorMessage = 'Failed to export CSV';
        }
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

    handleCloseSuccess() {
        this.successMessage = '';
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
            this.errorMessage = 'Full Name is required.';
            return;
        }
        if (!this.form.phone || !this.form.phone.trim()) {
            this.errorMessage = 'Mobile Number is required.';
            return;
        }
        if (!this.form.project) {
            this.errorMessage = 'Please select an Interested Project.';
            return;
        }
        if (!this.form.budget) {
            this.errorMessage = 'Please select a valid Budget Aligned.';
            return;
        }

        this.isSaving = true;

        try {
            var leadId = await createLead({
                fullName:    this.form.fullName ? this.form.fullName.trim() : '',
                company:     this.form.company ? this.form.company.trim() : '',
                leadSource:  this.form.leadSource ? this.form.leadSource.trim() : 'Partner Portal',
                email:       this.form.email ? this.form.email.trim() : '',
                phone:       this.form.phone ? this.form.phone.trim() : '',
                address:     this.form.address ? this.form.address.trim() : '',
                project:     this.form.project ? this.form.project.trim() : '',
                budget:      this.form.budget ? this.form.budget.trim() : '',
                description: this.form.description ? this.form.description.trim() : ''
            });

            console.log('Lead created successfully:', leadId);

            // Set success message for list view
            this.successMessage = 'Lead created successfully! Lead ID: ' + leadId;
            this.isFormView = false;

            if (this.wiredLeadsResult) {
                refreshApex(this.wiredLeadsResult);
            }

            // Auto-hide success message after 7 seconds
            var self = this;
            window.setTimeout(function() {
                self.successMessage = '';
            }, 7000);

        } catch (err) {
            console.error('Lead creation error:', err);
            var msg = 'Failed to register lead';
            if (err && err.body && err.body.message) {
                msg = err.body.message;
            } else if (err && err.message) {
                msg = err.message;
            }
            this.errorMessage = msg;
        } finally {
            this.isSaving = false;
        }
    }
}