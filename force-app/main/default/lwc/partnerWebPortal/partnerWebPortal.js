import { LightningElement } from 'lwc';

export default class PartnerWebPortal extends LightningElement {

    selectedPage = 'dashboard';

    userName = '';
    searchText = '';

    handleNavigation(event) {
        this.selectedPage = event.currentTarget.dataset.page;
    }

    // ---------- RENDER CONDITIONS (Boolean) ----------
    get isDashboard() { return this.selectedPage === 'dashboard'; }
    get isLeads()     { return this.selectedPage === 'leads'; }
    get isSiteVisit() { return this.selectedPage === 'siteVisits'; }
    get isMyTeam()    { return this.selectedPage === 'myTeam'; }
    get isProjects()  { return this.selectedPage === 'projects'; }
    get isMarketing() { return this.selectedPage === 'marketing'; }
    get isAboutUs()   { return this.selectedPage === 'aboutUs'; }
    get isTerms()     { return this.selectedPage === 'terms'; }

    // ---------- CSS CLASS HELPERS ----------
    getPageClass(page) {
        return this.selectedPage === page ? 'nav-item active' : 'nav-item';
    }

    get dashboardClass()  { return this.getPageClass('dashboard'); }
    get leadsClass()      { return this.getPageClass('leads'); }
    get siteVisitClass()  { return this.getPageClass('siteVisits'); }
    get myTeamClass()     { return this.getPageClass('myTeam'); }
    get projectsClass()   { return this.getPageClass('projects'); }
    get commissionClass() { return this.getPageClass('commission'); }
    get marketingClass()  { return this.getPageClass('marketing'); }
    get aboutUsClass()    { return this.getPageClass('aboutUs'); }
    get termsClass()      { return this.getPageClass('terms'); }
    get logoutClass()     { return this.getPageClass('logout'); }

    // ---------- LABELS (only for pages with no dedicated component) ----------
    get selectedPageLabel() {
        const labels = {
            commission: 'Commission',
            logout:     'Logout'
        };
        return labels[this.selectedPage] || '';
    }

    get userInitials() {
        return this.userName
            .split(' ')
            .map(n => n.charAt(0))
            .join('')
            .slice(0, 2)
            .toUpperCase();
    }

    handleSearch(event) { this.searchText = event.target.value; }
    handleNotifications() { console.log('Notifications clicked'); }
    handleProfile() { console.log('Profile clicked'); }
}