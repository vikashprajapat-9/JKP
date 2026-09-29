import { LightningElement } from 'lwc';
import getPortalData from '@salesforce/apex/CustomerPortalController.getPortalData';

export default class CustomerPortal extends LightningElement {

    portalData;
    isLoading = true;
    hasError = false;
    activePage = 'dashboard';
    isLogoutModalOpen = false;
    isMobileSidebarOpen = false;

    connectedCallback() {
        this.loadPortalData();
    }

    async loadPortalData() {
        this.isLoading = true;
        this.hasError = false;

        try {
            this.portalData = await getPortalData();
        } catch (error) {
            this.hasError = true;
            console.error('customerProtal: failed to load portal data', error);
        } finally {
            this.isLoading = false;
        }
    }

    get showPortal() {
        return !this.isLoading && !this.hasError && this.portalData;
    }

    get isProfilePage() {
        return this.activePage === 'profile';
    }

    get isReferralsPage() {
        return this.activePage === 'referrals';
    }

    get isProjectsPage() {
        return this.activePage === 'projects';
    }

     get isConstructionStatusView() {
        return this.activePage === 'constructionStatus';
    }

    get isMyPropertiesPage() {
        return this.activePage === 'myProperties';
    }

    get isMyAccountsPage() {
        return this.activePage === 'myAccounts';
    }

    get isMyVisitsPage() {
        return this.activePage === 'myVisits';
    }

    get isSupportPage() {
        return this.activePage === 'support';
    }

    get isEventsPage() {
        return this.activePage === 'events';
    }

    get isFaqsPage() {
        return this.activePage === 'faqs';
    }

    get isMyDocumentsPage() {
        return this.activePage === 'myDocuments';
    }

    get isAboutUsPage() {
        return this.activePage === 'aboutUs';
    }

    get isTermsConditionsPage() {
        return this.activePage === 'termsConditions';
    }

    get isDashboardPage() {
        return this.activePage === 'dashboard';
    }

    get isLetsTalkPage() {
        return this.activePage === 'letsTalk';
    }

    handleDashboardNavigation(event) {
        const allowed = ['myProperties', 'constructionStatus', 'myDocuments','myAccounts', 'referrals', 'faqs', 'support'];
        const page = event.detail && event.detail.page;
        if (allowed.includes(page)) {
            this.activePage = page; 
        }
    }

    // handleMenuSelect(event) {
    //     this.activePage = event.detail.value;
    //     this.isMobileSidebarOpen = false;
    // }

    handleMenuSelect(event) {
        const selectedPage = event.detail.value;

        if (selectedPage === 'logout') {
            this.activePage = 'projects';   
            this.isLogoutModalOpen = true;
            this.isMobileSidebarOpen = false;
            return;
        }

        this.activePage = selectedPage;
        this.isMobileSidebarOpen = false;
    }

    handleLogoutModalClose() {
        this.isLogoutModalOpen = false;
        this.activePage = 'dashboard';
    }

    handleLogout() {
        this.isLogoutModalOpen = false;
    }

    handleProfileClick() {
        this.activePage = 'profile';
        this.isMobileSidebarOpen = false;
    }

    handleToggleSidebar() {
        this.isMobileSidebarOpen = !this.isMobileSidebarOpen;
    }

    handleCloseMobileMenu() {
        this.isMobileSidebarOpen = false;
    }
}