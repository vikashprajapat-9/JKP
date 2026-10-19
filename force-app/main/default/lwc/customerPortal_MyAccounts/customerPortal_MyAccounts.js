import { LightningElement, wire, track } from 'lwc';
import getMyAccountsPageData from '@salesforce/apex/CustomerPortalController.getMyAccountsPageData';
import getMyAccountDetails from '@salesforce/apex/CustomerPortalController.getMyAccountDetails';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import CP_ASSETS from '@salesforce/resourceUrl/customerPortalAssets';
import { ICONS } from './icons';

const ALL_PROJECTS_VALUE = 'ALL';
const SWIPE_THRESHOLD_PX = 40;

// Visible text (plain constants, no Custom Labels)
const LABELS = {
    title: 'Accounts',
    allProjects: 'All Projects',
    filterPlaceholder: 'Filter By Projects',
    loadingAccounts: 'Loading your accounts...',
    loadingDetails: 'Loading account details...',
    loadError: 'Something went wrong while loading your accounts. Please try again later.',
    retry: 'Retry',
    noAccounts: 'No accounts found for this project.',
    viewDetails: 'View Details',
    previousImage: 'Previous image',
    nextImage: 'Next image',
    showImage: 'Show image ',
    back: 'Back',
    backToAccounts: 'Back to accounts',
    tabsLabel: 'Account views',
    myAccount: 'My Account',
    myPayables: 'My Payables',
    totalValueBilled: 'Total Value Billed',
    totalAmountDue: 'Total Amount Due',
    totalInterestAccumulated: 'Total Interest Accumulated',
    totalAmountPaid: 'Total Amount Paid',
    percentagePaid: 'Percentage Paid',
    customisationCharges: 'Customisation Charges',
    purchasedPrice: 'Purchased Price(Incl Tax)',
    totalPayable: 'Total Payable',
    totalPayableNote: 'Includes due amount, applicable interest,\nand customization charges.',
    downloadSummary: 'Download Account Summary',
    payableStatus: 'Status:',
    payableDueDate: 'Due Date:',
    payableDetails: 'Details:',
    noPayables: 'No payables found.',
    toastTitle: 'Something went wrong',
    loadErrorToast: 'Error in loading the account data',
    detailErrorToast: 'Error loading account details.',
    retryErrorToast: 'Retry failed'
};

export default class CustomerPortal_MyAccounts extends LightningElement {
    labels = LABELS;
    icons = ICONS;
    emptyImageUrl = CP_ASSETS + '/empty-state.svg';

    @track isLoading = true;
    @track hasError = false;
    @track pageDescription = '';
    @track filterOptions = [];
    @track rawAccounts = [];

    selectedProjectFilter = ALL_PROJECTS_VALUE;
    isFilterMenuOpen = false;

    currentView = 'list';

    @track isDetailLoading = false;
    @track accountDetails;
    @track payableRows = [];
    selectedAccountId;
    activeTab = 'myAccount';
    expandedPayableId;

    touchStartX = null;

    @wire(getMyAccountsPageData)
    wiredPageData({ data, error }) {
        if (data) {
            this.isLoading = false;
            this.hasError = false;
            this.applyPageData(data);
        } else if (error) {
            this.isLoading = false;
            this.hasError = true;
            console.error('Error loading My Accounts page data', error);
            this.showErrorToast(LABELS.loadErrorToast);
        }
    }

    applyPageData(data) {
        this.pageDescription = data.description;
        this.filterOptions = this.buildFilterOptions(data.projectFilters);
        this.rawAccounts = (data.accounts || []).map((acc) => this.initializeAccountCard(acc));
    }

    buildFilterOptions(projectFilters) {
        const options = [{ label: LABELS.allProjects, value: ALL_PROJECTS_VALUE }];
        (projectFilters || []).forEach((f) => {
            options.push({ label: f.label, value: f.value });
        });
        return options.map((opt) => ({
            ...opt,
            itemClass: this.filterItemClass(opt.value === this.selectedProjectFilter)
        }));
    }

    filterItemClass(isActive) {
        return isActive ? 'acc-filter__item acc-filter__item_active' : 'acc-filter__item';
    }

    initializeAccountCard(acc) {
        const images = (acc.images || []).map((img, index) => ({
            key: acc.id + '-img-' + index,
            url: img.url,
            index
        }));
        return {
            id: acc.id,
            projectName: acc.projectName,
            unitNumber: acc.unitNumber,
            filterValue: acc.filterValue,
            images,
            currentIndex: 0
        };
    }

    // ---------- views ----------
    get showListView() {
        return !this.isLoading && !this.hasError && this.currentView === 'list';
    }

    get showDetailView() {
        return !this.isLoading && !this.hasError && this.currentView === 'detail';
    }

    get showHead() {
        return !this.isLoading && !this.hasError;
    }

    // ---------- list view (Figma p61) ----------
    // Figma shows "Filter By Projects" while every project is shown
    get selectedFilterLabel() {
        if (this.selectedProjectFilter === ALL_PROJECTS_VALUE) {
            return LABELS.filterPlaceholder;
        }
        const match = this.filterOptions.find((o) => o.value === this.selectedProjectFilter);
        return match ? match.label : LABELS.filterPlaceholder;
    }

    get filterExpanded() {
        return this.isFilterMenuOpen ? 'true' : 'false';
    }

    get displayedAccounts() {
        const filtered =
            this.selectedProjectFilter === ALL_PROJECTS_VALUE
                ? this.rawAccounts
                : this.rawAccounts.filter((a) => a.filterValue === this.selectedProjectFilter);

        return filtered.map((account) => this.decorateAccountForRender(account));
    }

    get hasNoAccounts() {
        return this.displayedAccounts.length === 0;
    }

    decorateAccountForRender(account) {
        const total = account.images.length;
        const decoratedImages = account.images.map((img) => ({
            key: img.key,
            index: img.index,
            label: LABELS.showImage + (img.index + 1),
            isCurrent: img.index === account.currentIndex ? 'true' : 'false',
            dotClass: img.index === account.currentIndex ? 'cp-dot cp-dot_active acc-dot' : 'cp-dot acc-dot'
        }));
        const activeImage = account.images[account.currentIndex] || account.images[0];

        return {
            id: account.id,
            projectName: account.projectName,
            unitNumber: account.unitNumber,
            filterValue: account.filterValue,
            images: decoratedImages,
            activeImageUrl: activeImage ? activeImage.url : '',
            showDots: total > 1,
            showArrows: total > 1
        };
    }

    toggleFilterMenu() {
        this.isFilterMenuOpen = !this.isFilterMenuOpen;
    }

    handleFilterSelect(event) {
        const value = event.currentTarget.dataset.value;
        this.selectedProjectFilter = value;
        this.isFilterMenuOpen = false;
        this.filterOptions = this.filterOptions.map((opt) => ({
            ...opt,
            itemClass: this.filterItemClass(opt.value === value)
        }));
    }

    handleFilterKeydown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            event.currentTarget.click();
        } else if (event.key === 'Escape') {
            this.isFilterMenuOpen = false;
        }
    }

    handleDotClick(event) {
        const accountId = event.currentTarget.dataset.accountId;
        const index = parseInt(event.currentTarget.dataset.index, 10);
        this.setAccountImageIndex(accountId, index);
    }

    handlePrevImage(event) {
        const accountId = event.currentTarget.dataset.accountId;
        const account = this.rawAccounts.find((a) => a.id === accountId);
        if (!account) return;
        const total = account.images.length;
        const newIndex = (account.currentIndex - 1 + total) % total;
        this.setAccountImageIndex(accountId, newIndex);
    }

    handleNextImage(event) {
        const accountId = event.currentTarget.dataset.accountId;
        const account = this.rawAccounts.find((a) => a.id === accountId);
        if (!account) return;
        const total = account.images.length;
        const newIndex = (account.currentIndex + 1) % total;
        this.setAccountImageIndex(accountId, newIndex);
    }

    setAccountImageIndex(accountId, newIndex) {
        this.rawAccounts = this.rawAccounts.map((a) =>
            (a.id === accountId ? { ...a, currentIndex: newIndex } : a)
        );
    }

    handleCardTouchStart(event) {
        this.touchStartX =
            event.changedTouches && event.changedTouches.length
                ? event.changedTouches[0].clientX
                : null;
    }

    handleCardTouchEnd(event) {
        if (this.touchStartX === null || !event.changedTouches || !event.changedTouches.length) {
            return;
        }
        const deltaX = event.changedTouches[0].clientX - this.touchStartX;
        this.touchStartX = null;

        if (Math.abs(deltaX) < SWIPE_THRESHOLD_PX) {
            return;
        }

        const accountId = event.currentTarget.dataset.accountId;
        const account = this.rawAccounts.find((a) => a.id === accountId);
        if (!account || account.images.length < 2) {
            return;
        }
        const total = account.images.length;
        const newIndex =
            deltaX < 0
                ? (account.currentIndex + 1) % total
                : (account.currentIndex - 1 + total) % total;
        this.setAccountImageIndex(accountId, newIndex);
    }

    handleViewDetails(event) {
        const accountId = event.currentTarget.dataset.accountId;
        this.selectedAccountId = accountId;
        this.currentView = 'detail';
        this.activeTab = 'myAccount';
        this.expandedPayableId = undefined;
        this.isFilterMenuOpen = false;
        this.loadAccountDetails(accountId);
    }

    handleBack() {
        this.currentView = 'list';
        this.accountDetails = undefined;
        this.payableRows = [];
        this.selectedAccountId = undefined;
    }

    // ---------- detail view (Figma p62-64) ----------
    async loadAccountDetails(accountId) {
        this.isDetailLoading = true;
        try {
            const data = await getMyAccountDetails({ accountId });
            this.accountDetails = data;
            this.payableRows = ((data && data.payables) || []).map((p) => this.decoratePayable(p));
        } catch (error) {
            this.hasError = true;
            console.error('Error loading account details', error);
            this.showErrorToast(LABELS.detailErrorToast);
        } finally {
            this.isDetailLoading = false;
        }
    }

    get myAccountTabClass() {
        return this.activeTab === 'myAccount' ? 'cp-tab cp-tab_active' : 'cp-tab';
    }

    get myPayablesTabClass() {
        return this.activeTab === 'myPayables' ? 'cp-tab cp-tab_active' : 'cp-tab';
    }

    get isMyAccountTab() {
        return this.activeTab === 'myAccount';
    }

    get isMyPayablesTab() {
        return this.activeTab === 'myPayables';
    }

    get myAccountSelected() {
        return this.isMyAccountTab ? 'true' : 'false';
    }

    get myPayablesSelected() {
        return this.isMyPayablesTab ? 'true' : 'false';
    }

    get myAccountTabIndex() {
        return this.isMyAccountTab ? '0' : '-1';
    }

    get myPayablesTabIndex() {
        return this.isMyPayablesTab ? '0' : '-1';
    }

    handleShowMyAccount() {
        this.activeTab = 'myAccount';
    }

    handleShowMyPayables() {
        this.activeTab = 'myPayables';
    }

    // Arrow keys move between the two tabs (tablist pattern)
    handleTabKeydown(event) {
        if (event.key !== 'ArrowRight' && event.key !== 'ArrowLeft') {
            return;
        }
        event.preventDefault();
        this.activeTab = this.isMyAccountTab ? 'myPayables' : 'myAccount';
        const target = this.template.querySelector('.acc-tabs [data-tab="' + this.activeTab + '"]');
        if (target) {
            target.focus();
        }
    }

    get summary() {
        return (this.accountDetails && this.accountDetails.accountSummary) || {};
    }

    get summaryTitle() {
        return this.accountDetails ? this.accountDetails.projectName : '';
    }

    // Two columns of figures, in the Figma order (p62)
    get summaryColumns() {
        const s = this.summary;
        return [
            {
                key: 'left',
                items: [
                    { key: 'billed', label: LABELS.totalValueBilled, value: s.totalValueBilled },
                    { key: 'due', label: LABELS.totalAmountDue, value: s.totalAmountDue },
                    { key: 'interest', label: LABELS.totalInterestAccumulated, value: s.totalInterestAccumulated }
                ]
            },
            {
                key: 'right',
                items: [
                    { key: 'paid', label: LABELS.totalAmountPaid, value: s.totalAmountPaid },
                    { key: 'percentage', label: LABELS.percentagePaid, value: s.percentagePaid },
                    { key: 'customisation', label: LABELS.customisationCharges, value: s.customisationCharges }
                ]
            }
        ];
    }

    get hasPayables() {
        return this.payableRows.length > 0;
    }

    decoratePayable(payable) {
        const isExpanded = payable.id === this.expandedPayableId;
        return {
            ...payable,
            isExpanded,
            ariaExpanded: isExpanded ? 'true' : 'false',
            chevronClass: isExpanded ? 'acc-payable__chevron acc-payable__chevron_open' : 'acc-payable__chevron',
            detailText: payable.details || payable.description
        };
    }

    handlePayableToggle(event) {
        const payableId = event.currentTarget.dataset.payableId;
        this.expandedPayableId = this.expandedPayableId === payableId ? undefined : payableId;
        this.payableRows = this.payableRows.map((p) => this.decoratePayable(p));
    }

    handleDownloadSummary() {
        const url = this.accountDetails && this.accountDetails.accountSummary
            ? this.accountDetails.accountSummary.downloadUrl
            : null;
        if (url) {
            window.open(url, '_blank');
        }
    }

    // Reloads the page data, and the open account when the error came from its details
    handleRetry() {
        this.hasError = false;
        this.isLoading = true;
        getMyAccountsPageData()
            .then((data) => {
                this.isLoading = false;
                this.applyPageData(data);
                if (this.currentView === 'detail' && this.selectedAccountId) {
                    this.loadAccountDetails(this.selectedAccountId);
                }
            })
            .catch((error) => {
                this.isLoading = false;
                this.hasError = true;
                console.error('Retry failed', error);
                this.showErrorToast(LABELS.retryErrorToast);
            });
    }

    showErrorToast(message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: LABELS.toastTitle,
                message,
                variant: 'error',
                mode: 'dismissable'
            })
        );
    }
}