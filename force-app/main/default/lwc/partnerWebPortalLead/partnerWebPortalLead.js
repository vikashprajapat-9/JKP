import { LightningElement, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getLeads from '@salesforce/apex/partnerWebPortalLeadController.getLeads';
import getStageOptions from '@salesforce/apex/partnerWebPortalLeadController.getStageOptions';
import getBudgetOptions from '@salesforce/apex/partnerWebPortalLeadController.getBudgetOptions';
import exportCSV from '@salesforce/apex/partnerWebPortalLeadController.exportCSV';
import createLead from '@salesforce/apex/partnerWebPortalLeadController.createLead';

// Static Interested Project lookup Id
const PROJECT_ID = 'a01h2000000E9jNAAS';

export default class PartnerWebPortalLead extends LightningElement {

    PAGE_SIZE = 10;

    // ---------- LIST STATE ----------
    @track searchKey = '';
    @track activeFilter = 'All';
    @track currentPage = 1;

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
        project: PROJECT_ID,   // static lookup Id
        budget: '',
        description: ''
    };

    budgetOptions = [];

    // ---------- WIRE: FILTER TABS ----------
    @wire(getStageOptions)
    wiredStages({ data, error }) {
        if (data) this.filterTabs = data;
        else if (error) console.error('Stage options error:', error);
    }

    // ---------- WIRE: BUDGET OPTIONS ----------
    @wire(getBudgetOptions)
    wiredBudgetOptions({ data, error }) {
        if (data) {
            this.budgetOptions = data.map(opt => ({
                label: opt.label,
                value: opt.value
            }));
        } else if (error) {
            console.error('Budget options error:', error);
        }
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
        const data = result.data;
        const error = result.error;

        if (data) {
            this.leads = data.leads.map(l => ({
                ...l,
                badgeClass: this.getBadgeClass(l.stage)
            }));
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
        return this.filterTabs.map(tab => ({
            label: tab,
            value: tab,
            className: tab === this.activeFilter ? 'filter-btn active' : 'filter-btn'
        }));
    }

    get hasLeads() { return this.leads && this.leads.length > 0; }
    get noLeads()  { return !this.hasLeads; }

    get entriesText() {
        if (this.totalRecords === 0) return 'Showing 0 entries';
        const start = (this.currentPage - 1) * this.pageSize + 1;
        const end = Math.min(this.currentPage * this.pageSize, this.totalRecords);
        return `Showing ${start} to ${end} of ${this.totalRecords} entries`;
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

    get saveButtonLabel() {
        return this.isSaving ? 'Saving...' : 'Register Lead';
    }

    getBadgeClass(stage) {
        const map = {
            'Open - Not Contacted': 'badge badge-scheduled',
            'Working - Contacted': 'badge badge-active',
            'Closed - Converted': 'badge badge-booked',
            'Closed - Not Converted': 'badge badge-lost',
            Active: 'badge badge-active',
            Visited: 'badge badge-visited',
            Booked: 'badge badge-booked',
            Scheduled: 'badge badge-scheduled',
            Lost: 'badge badge-lost'
        };
        return map[stage] || 'badge';
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
            project: PROJECT_ID,
            budget: '',
            description: ''
        };
        this.isFormView = true;
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
        this.currentPage = parseInt(event.currentTarget.dataset.value, 10);
    }

    handlePrev() { if (this.currentPage > 1) this.currentPage--; }
    handleNext() { if (this.currentPage < this.totalPages) this.currentPage++; }

    async handleExport() {
        try {
            const base64 = await exportCSV({
                stageFilter: this.activeFilter,
                searchKey: this.searchKey
            });
            const link = document.createElement('a');
            link.href = 'data:text/csv;base64,' + base64;
            link.download = 'leads_export.csv';
            link.click();
        } catch (e) {
            console.error('Export error:', e);
            this.showToast('Error', 'Failed to export CSV', 'error');
        }
    }

    handleApplyFilter() {
        if (this.wiredLeadsResult) refreshApex(this.wiredLeadsResult);
    }

    // ---------- FORM HANDLERS ----------
    handleFormChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.value;

        const updated = { ...this.form };
        updated[field] = value;
        this.form = updated;
    }

    handleFormCancel() {
        this.isFormView = false;
    }

    async handleRegisterLead() {
        if (!this.form.fullName) {
            this.showToast('Error', 'Full Name is required', 'error');
            return;
        }
        if (!this.form.phone) {
            this.showToast('Error', 'Mobile Number is required', 'error');
            return;
        }

        this.isSaving = true;

        try {
            const leadId = await createLead({
                fullName:    this.form.fullName,
                company:     this.form.company,
                leadSource:  this.form.leadSource,
                email:       this.form.email,
                phone:       this.form.phone,
                address:     this.form.address,
                project:     this.form.project,   // static Id
                budget:      this.form.budget,
                description: this.form.description
            });

            console.log('✅ Lead created:', leadId);

            // Success toast with Lead Id
            this.showToast(
                'Success',
                `Lead created successfully. Lead Id: ${leadId}`,
                'success'
            );

            this.isFormView = false;
            if (this.wiredLeadsResult) {
                refreshApex(this.wiredLeadsResult);
            }

        } catch (err) {
            console.error('❌ Lead creation error:', JSON.stringify(err));
            const msg = err.body ? err.body.message : 'Failed to register lead';
            this.showToast('Error', msg, 'error');
        } finally {
            this.isSaving = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}