import { LightningElement, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getSiteVisit from '@salesforce/apex/partnerWebPortalSiteVisit.getSiteVisit';
import getStageOptions from '@salesforce/apex/partnerWebPortalSiteVisit.getStageOptions';
import getCustomerOptions from '@salesforce/apex/partnerWebPortalSiteVisit.getCustomerOptions';
import getProjectOptions from '@salesforce/apex/partnerWebPortalSiteVisit.getProjectOptions';
import exportCSV from '@salesforce/apex/partnerWebPortalSiteVisit.exportCSV';
import createSiteVisit from '@salesforce/apex/partnerWebPortalSiteVisit.createSiteVisit';

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
        visitDate: '',
        description: ''
    };

    // Time picker states
    @track timeHours = '10';
    @track timeMinutes = '00';
    @track timePeriod = 'AM';

    customerOptions = [];
    projectOptions = [];
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
                projectName: v.projectName,
                status: v.status || 'Upcoming'
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

    // Auto-select project when customer (lead) is picked
    handleCustomerChange(event) {
        const selectedLeadId = event.target.value;
        this.form = Object.assign({}, this.form, {
            leadId: selectedLeadId
        });

        const match = this.rawCustomerList.find(c => c.value === selectedLeadId);
        if (match && match.projectId) {
            this.form.projectId = match.projectId;
        }
        this.errorMessage = '';
    }

    get hasVisits() { return Array.isArray(this.visits) && this.visits.length > 0; }

    get filterButtons() {
        return this.filterTabs.map(tab => ({
            label: tab,
            value: tab,
            className: tab === this.activeFilter ? 'filter-btn active' : 'filter-btn'
        }));
    }

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
        return this.isSaving || !this.form.leadId;
    }

    get saveButtonLabel() {
        return this.isSaving ? 'Scheduling...' : 'Confirm Site Visit';
    }

    // ---------- LIST HANDLERS ----------
    handleNavigation() {
        const today = new Date().toISOString().split('T')[0];
        this.form = {
            leadId: '',
            projectId: '',
            visitDate: today,
            description: ''
        };
        this.timeHours = '10';
        this.timeMinutes = '00';
        this.timePeriod = 'AM';
        this.errorMessage = '';
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
        this.currentPage = Number(event.currentTarget.dataset.value);
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
            link.download = 'site_visits_export.csv';
            link.click();
        } catch (e) {
            console.error('Export error:', e);
            this.errorMessage = 'Failed to export CSV';
        }
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

        if (!this.form.leadId) {
            this.errorMessage = 'Customer (Lead) is required.';
            return;
        }

        const formattedTime = (this.timeHours || '10') + ':' + (this.timeMinutes || '00') + ' ' + this.timePeriod;

        this.isSaving = true;
        try {
            const visitId = await createSiteVisit({
                leadId:      this.form.leadId,
                projectId:   this.form.projectId ? this.form.projectId : null,
                visitDate:   this.form.visitDate ? this.form.visitDate : null,
                visitTime:   formattedTime,
                description: this.form.description ? this.form.description : ''
            });

            console.log('✅ Site Visit scheduled:', visitId);

            this.successMessage = 'Site Visit scheduled successfully! Visit ID: ' + visitId;
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
            const msg = (err && err.body && err.body.message) ? err.body.message : 'Failed to schedule site visit';
            this.errorMessage = msg;
        } finally {
            this.isSaving = false;
        }
    }
}