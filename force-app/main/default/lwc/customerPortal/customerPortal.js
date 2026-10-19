import { LightningElement } from 'lwc';
import { loadStyle } from 'lightning/platformResourceLoader';
import getPortalData from '@salesforce/apex/CustomerPortalController.getPortalData';
import CP_FONTS from '@salesforce/resourceUrl/customerPortalFonts';
import CP_ASSETS from '@salesforce/resourceUrl/customerPortalAssets';
import basePath from '@salesforce/community/basePath';
import isCustomer from '@salesforce/apex/CustomerPortalLoginController.isCustomer';

const LABELS = {
    loading: 'Loading portal',
    loadError: "We couldn't load the portal right now. Please try again in a moment.",
    notCustomerTitle: 'This portal is only for John Keells Properties customers.',
    notCustomerText: 'Please sign in with your customer login. Channel partners use the Partner Portal.',
    logOut: 'Log out',
    logoAlt: 'John Keells Properties'
};

export default class CustomerPortal extends LightningElement {

    labels = LABELS;
    portalData;
    isLoading = true;
    hasError = false;
    // The signed-in person is not a contact of a Customer account: the portal stays closed
    notCustomer = false;
    logoUrl = CP_ASSETS + '/logo.svg';
    _activePage = 'dashboard';
    // The dashboard's own view ('dashboard' or 'handover'): the handover checklist sits on white, as in Figma p8-p13
    dashboardView = 'dashboard';

    get activePage() {
        return this._activePage;
    }

    set activePage(value) {
        this._activePage = value;
        this.dashboardView = 'dashboard';
    }
    isLogoutModalOpen = false;
    isMobileSidebarOpen = false;

    connectedCallback() {
        // 'JKP DIN' font faces (the Figma's DIN face)
        loadStyle(this, CP_FONTS + '/fonts.css').catch(() => {
            // The system font stack is used if the fonts cannot be loaded
        });
        this.loadPortalData();
    }

    async loadPortalData() {
        this.isLoading = true;
        this.hasError = false;

        try {
            // Only contacts of Customer accounts may use the portal. The login page refuses everyone else; this also
            // covers a session that started elsewhere (for example the automatic login after a password reset). If the
            // check itself fails, the portal opens as before.
            let allowed = true;
            try {
                allowed = await isCustomer();
            } catch (checkError) {
                allowed = true;
            }
            if (allowed === false) {
                this.notCustomer = true;
                return;
            }
            this.portalData = await getPortalData();
        } catch (error) {
            this.hasError = true;
            console.error('customerPortal: failed to load portal data', error);
        } finally {
            this.isLoading = false;
        }
    }

    get showPortal() {
        return !this.isLoading && !this.hasError && !this.notCustomer && this.portalData;
    }

    // Figma: the Dashboard sits on a light grey page (#fafafa), every other screen on white
    get mainClass() {
        return this.isDashboardPage && this.dashboardView !== 'handover' ? 'portal-main portal-main_tinted' : 'portal-main';
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

    handleDashboardViewChange(event) {
        this.dashboardView = event.detail && event.detail.view === 'handover' ? 'handover' : 'dashboard';
    }

    handleDashboardNavigation(event) {
        const allowed = ['myProperties', 'constructionStatus', 'myDocuments', 'myAccounts', 'referrals', 'faqs', 'support'];
        const page = event.detail && event.detail.page;
        if (allowed.includes(page)) {
            this.activePage = page;
        }
    }

    handleMenuSelect(event) {
        const selectedPage = event.detail.value;

        if (selectedPage === 'logout') {
            // Figma p94 shows the logout popup over the Projects page
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

    handleNotCustomerLogout() {
        const loginUrl = basePath + '/login';
        window.location.replace(basePath + '/secur/logout.jsp?retUrl=' + encodeURIComponent(loginUrl));
    }

    handleLogout() {
        this.isLogoutModalOpen = false;
    }

    // The Profile screen sends the saved name and photo: the header avatar follows without a reload
    handleProfileUpdated(event) {
        event.stopPropagation();
        const detail = event.detail || {};
        if (!this.portalData) {
            return;
        }
        const headerData = { ...(this.portalData.headerData || {}) };
        if (detail.fullName) {
            headerData.userName = detail.fullName;
        }
        if (Object.prototype.hasOwnProperty.call(detail, 'photoUrl')) {
            headerData.avatarUrl = detail.photoUrl || null;
        }
        this.portalData = { ...this.portalData, headerData };
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