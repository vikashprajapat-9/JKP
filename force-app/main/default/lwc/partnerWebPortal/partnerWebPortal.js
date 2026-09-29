import { LightningElement, wire } from 'lwc';
import { loadStyle } from 'lightning/platformResourceLoader';
import PORTAL_THEME from '@salesforce/resourceUrl/JKPortalTheme';
import getCurrentUser from '@salesforce/apex/PartnerPortalDashboard.getCurrentUser';

const NAV_ITEMS = [
    { page: 'dashboard', label: 'Dashboard', icon: 'utility:home' },
    { page: 'leads', label: 'Leads', icon: 'utility:user' },
    { page: 'siteVisits', label: 'Site Visits', icon: 'utility:location' },
    { page: 'myTeam', label: 'My Team', icon: 'utility:people' },
    { page: 'projects', label: 'Projects', icon: 'utility:list' },
    { page: 'commission', label: 'Commission', icon: 'utility:money' },
    { page: 'marketing', label: 'Marketing', icon: 'utility:announcement' },
    { page: 'aboutUs', label: 'About Us', icon: 'utility:info' },
    { page: 'terms', label: 'Terms & Conditions', icon: 'utility:description' },
    { page: 'logout', label: 'Logout', icon: 'utility:logout' }
];

export default class PartnerWebPortal extends LightningElement {

    selectedPage = 'dashboard';
    userName = '';
    showLogoutConfirm = false;
    logoUrl = PORTAL_THEME + '/logo.png';

    @wire(getCurrentUser)
    wiredUser({ data }) {
        if (data) {
            this.userName = data;
        }
    }

    connectedCallback() {
        loadStyle(this, PORTAL_THEME + '/theme.css').catch(() => {
            // Font falls back to the system stack if the theme fails to load.
        });
    }

    get navItems() {
        return NAV_ITEMS.map(item => ({
            ...item,
            cssClass: this.selectedPage === item.page ? 'nav-item active' : 'nav-item'
        }));
    }

    handleNavigation(event) {
        const page = event.currentTarget.dataset.page;
        if (page === 'logout') {
            this.showLogoutConfirm = true;
        } else {
            this.selectedPage = page;
        }
    }

    // ---------- RENDER CONDITIONS (Boolean) ----------
    get isDashboard() { return this.selectedPage === 'dashboard'; }
    get isLeads()     { return this.selectedPage === 'leads'; }
    get isSiteVisit() { return this.selectedPage === 'siteVisits'; }
    get isMyTeam()    { return this.selectedPage === 'myTeam'; }
    get isProjects()  { return this.selectedPage === 'projects'; }
    get isCommission() { return this.selectedPage === 'commission'; }
    get isMarketing() { return this.selectedPage === 'marketing'; }
    get isAboutUs()   { return this.selectedPage === 'aboutUs'; }
    get isTerms()     { return this.selectedPage === 'terms'; }
    get isProfile()   { return this.selectedPage === 'profile'; }

    // ---------- LABELS ----------
    get selectedPageLabel() {
        const labels = {
            commission: 'Commission'
        };
        return labels[this.selectedPage] || '';
    }

    get userInitials() {
        if (!this.userName) return 'U';
        return this.userName
            .split(' ')
            .filter(n => n)
            .map(n => n.charAt(0))
            .join('')
            .slice(0, 2)
            .toUpperCase();
    }

    handleNotifications() {
        // Notifications are not built yet.
    }

    handleProfile() {
        this.selectedPage = 'profile';
    }

    closeLogout() {
        this.showLogoutConfirm = false;
    }

    confirmLogout() {
        window.location.replace('/secur/logout.jsp');
    }
}