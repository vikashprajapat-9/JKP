import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getMyTeam from '@salesforce/apex/partnerWebPortalMyTeamController.getMyTeam';

const LABELS = {
    EXCLUSIVE_ONLY: 'You can add executives once your partnership has exclusive access.'
};

const PAGE_SIZE = 4;
const NO_VALUE = '–';

export default class PartnerWebPortalMyTeam extends LightningElement {

    partnerName = '';
    partnerInitials = '';
    stats = { totalLeads: 0, totalBookings: 0, totalExecutives: 0 };
    members = [];
    error;
    isLoading = true;
    searchKey = '';
    showAddMember = false;
    // Add Executive is offered only to a channel head whose partnership is Exclusive; the server says so
    canAddExecutive = false;
    currentPage = 1;
    wiredTeamResult;
    labels = { exclusiveOnly: LABELS.EXCLUSIVE_ONLY };

    @wire(getMyTeam)
    wiredTeam(result) {
        this.wiredTeamResult = result;
        const { data, error } = result;
        if (data) {
            this.partnerName = data.partnerName || '';
            this.partnerInitials = data.partnerInitials || '';
            this.stats = data.stats || this.stats;
            this.members = (data.members || []).map(m => ({
                ...m,
                avatarClass: 'avatar ' + (m.avatarColorClass || 'avatar-blue')
            }));
            this.canAddExecutive = data.canAddExecutive === true;
            this.error = undefined;
            this.isLoading = false;
        } else if (error) {
            this.error = error.body && error.body.message ? error.body.message : 'Your team could not be loaded right now. Please try again.';
            this.canAddExecutive = false;
            this.isLoading = false;
            console.error('My Team wire error:', error);
        }
    }

    // ---------- HERO FIGURES (a dash until they are known, so a failed load never reads as zero) ----------
    get hasFigures() {
        return !this.isLoading && !this.error;
    }

    get leadsDisplay() {
        return this.hasFigures ? String(Number(this.stats.totalLeads) || 0) : NO_VALUE;
    }

    get bookingsDisplay() {
        return this.hasFigures ? String(Number(this.stats.totalBookings) || 0) : NO_VALUE;
    }

    // Figma shows the executive count zero-padded (e.g. "04")
    get executivesDisplay() {
        if (!this.hasFigures) return NO_VALUE;
        const n = Number(this.stats.totalExecutives) || 0;
        return n < 10 ? '0' + n : String(n);
    }

    get hasNoTeam() {
        return this.hasFigures && this.members.length === 0;
    }

    // During the temporary access (any partnership that is not Exclusive) a note stands where Add Executive would be,
    // once the team has loaded
    get showExclusiveNote() {
        return this.hasFigures && !this.canAddExecutive;
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

    // The form opens only for a channel head who may add executives
    handleAddExecutive() {
        if (this.canAddExecutive) {
            this.showAddMember = true;
        }
    }

    handleCloseAddMember() {
        this.showAddMember = false;
    }

    // A new executive changes the figures and the team list
    handleMemberAdded() {
        return refreshApex(this.wiredTeamResult);
    }
}