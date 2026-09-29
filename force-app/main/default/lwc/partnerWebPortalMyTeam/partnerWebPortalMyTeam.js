import { LightningElement, wire } from 'lwc';
import getMyTeam from '@salesforce/apex/partnerWebPortalMyTeamController.getMyTeam';

const PAGE_SIZE = 4;

export default class PartnerWebPortalMyTeam extends LightningElement {

    stats = { totalLeads: 0, totalBookings: 0, totalExecutives: 0 };
    members = [];
    error;
    searchKey = '';
    showAddMember = false;
    currentPage = 1;

    @wire(getMyTeam)
    wiredTeam({ data, error }) {
        if (data) {
            this.stats = data.stats || this.stats;
            this.members = (data.members || []).map(m => ({
                ...m,
                avatarClass: 'avatar ' + (m.avatarColorClass || 'avatar-blue')
            }));
        } else if (error) {
            this.error = error.body ? error.body.message : 'Failed to load team';
            console.error('My Team wire error:', error);
        }
    }

    // ---------- SEARCH + PAGINATION (client-side over loaded members) ----------
    get filteredMembers() {
        const key = this.searchKey.trim().toLowerCase();
        if (!key) return this.members;
        return this.members.filter(m => (m.fullName || '').toLowerCase().includes(key));
    }

    get totalPages() {
        return Math.max(1, Math.ceil(this.filteredMembers.length / PAGE_SIZE));
    }

    get pagedMembers() {
        const start = (this.currentPage - 1) * PAGE_SIZE;
        return this.filteredMembers.slice(start, start + PAGE_SIZE);
    }

    get hasNoResults() {
        return this.members.length > 0 && this.filteredMembers.length === 0;
    }

    get showPagination() {
        return this.filteredMembers.length > 0;
    }

    get entriesText() {
        const total = this.filteredMembers.length;
        const start = (this.currentPage - 1) * PAGE_SIZE + 1;
        const end = Math.min(this.currentPage * PAGE_SIZE, total);
        return `Showing ${start} to ${end} of ${total} entries`;
    }

    get paginationButtons() {
        const buttons = [];
        for (let i = 1; i <= this.totalPages; i++) {
            buttons.push({
                value: i,
                label: String(i),
                className: i === this.currentPage ? 'page-num active' : 'page-num'
            });
        }
        return buttons;
    }

    get isPrevDisabled() {
        return this.currentPage <= 1;
    }

    get isNextDisabled() {
        return this.currentPage >= this.totalPages;
    }

    handleSearch(event) {
        this.searchKey = event.target.value || '';
        this.currentPage = 1;
    }

    handlePageClick(event) {
        this.currentPage = Number(event.currentTarget.dataset.value);
    }

    handlePrev() {
        if (!this.isPrevDisabled) this.currentPage -= 1;
    }

    handleNext() {
        if (!this.isNextDisabled) this.currentPage += 1;
    }

    // Figma shows the executive count zero-padded (e.g. "04")
    get executivesDisplay() {
        const n = Number(this.stats && this.stats.totalExecutives) || 0;
        return n < 10 ? '0' + n : String(n);
    }

    handleAddExecutive() {
        this.showAddMember = true;
    }

    handleCloseAddMember() {
        this.showAddMember = false;
    }
}