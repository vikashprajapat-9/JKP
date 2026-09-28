import { LightningElement, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSiteVisit from '@salesforce/apex/partnerWebPortalSiteVisit.getSiteVisit';
import getStageOptions from '@salesforce/apex/partnerWebPortalSiteVisit.getStageOptions';
import exportCSV from '@salesforce/apex/partnerWebPortalSiteVisit.exportCSV';
import createSiteVisit from '@salesforce/apex/partnerWebPortalSiteVisit.createSiteVisit';

export default class PartnerWebPortalSiteVisit extends LightningElement {

    PAGE_SIZE = 10;

    // ---------- LIST STATE ----------
    @track searchKey = '';
    @track activeFilter = 'All';
    @track currentPage = 1;
    @track successMessage = '';
    @track createdVisitId = '';
    visits = [];
    totalRecords = 0;
    totalPages = 0;
    pageSize = this.PAGE_SIZE;

    filterTabs = ['All'];
    wiredVisitsResult;
    searchTimeout;

    // ---------- FORM STATE ----------
    @track isFormView = false;
    @track isSaving = false;

    @track form = {
        visitName: '',
        channelPartnerId: '',
        opportunityId: '',
        reason: '',
        visitDate: ''
    };

    // ---------- WIRE: FILTER TABS ----------
    @wire(getStageOptions)
    wiredStages({ data, error }) {
        if (data) this.filterTabs = data;
        else if (error) console.error('Stage options error:', error);
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
            console.error('❌ Site Visit wire error:', JSON.stringify(error));
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
                channelPartnerName: v.channelPartner,
                opportunityName: v.opportunityName,
                opportunityPhone: v.opportunityMobile,
                opportunityStage: v.opportunityStage
            };
            row.badgeClass = this.getBadgeClass(row.opportunityStage);
            return row;
        });

        this.visits = rows;
        this.totalRecords = data.totalRecords;
        this.totalPages = data.totalPages;
    }

    // ---------- HELPERS ----------
    getBadgeClass(stage) {
        const map = {
            'Qualify':              'badge badge-scheduled',
            'Prospecting':          'badge badge-active',
            'Proposal/Price Quote': 'badge badge-visited',
            'Negotiation/Review':   'badge badge-booked',
            'Closed Won':           'badge badge-active',
            'Closed Lost':          'badge badge-lost'
        };
        return map[stage] || 'badge';
    }

    // ---------- GETTERS ----------
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
        return this.isSaving ? 'Saving...' : 'Register Site Visit';
    }

    // ---------- LIST HANDLERS ----------
    handleNavigation() {
        this.form = {
            visitName: '',
            channelPartnerId: '',
            opportunityId: '',
            reason: '',
            visitDate: ''
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
            this.showToast('Error', 'Failed to export CSV', 'error');
        }
    }

    handleApplyFilter() {
        if (this.wiredVisitsResult) refreshApex(this.wiredVisitsResult);
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

   async handleRegisterVisit() {
    if (!this.form.visitName) {
        this.showToast('Error', 'Visit Name is required', 'error');
        return;
    }

    this.isSaving = true;
    try {
        const visitId = await createSiteVisit({
            visitName:        this.form.visitName,
            channelPartnerId: this.form.channelPartnerId,
            opportunityId:    this.form.opportunityId,
            reason:           this.form.reason,
            visitDate:        this.form.visitDate || null
        });

        console.log('✅ Site Visit created:', visitId);

        // Store success info for the banner
        this.createdVisitId = visitId;
        this.successMessage = `Site Visit created successfully. Id: ${visitId}`;

        // Switch back to list view
        this.isFormView = false;

        // Refresh the list
        if (this.wiredVisitsResult) {
            refreshApex(this.wiredVisitsResult);
        }

        // Auto-hide the banner after 8 seconds
        window.setTimeout(() => {
            this.successMessage = '';
        }, 8000);

    } catch (err) {
        console.error('❌ Site Visit creation error:', JSON.stringify(err));
        const msg = err.body ? err.body.message : 'Failed to register site visit';
        this.showToast('Error', msg, 'error');
    } finally {
        this.isSaving = false;
    }
}

handleCloseBanner() {
    this.successMessage = '';
}

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}