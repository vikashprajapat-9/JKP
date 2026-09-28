import { LightningElement, wire, track } from 'lwc';
import getMyAccountsPageData from '@salesforce/apex/customerPortalController.getMyAccountsPageData';
import getMyAccountDetails from '@salesforce/apex/customerPortalController.getMyAccountDetails';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
const ALL_PROJECTS_VALUE = 'ALL';
const ALL_PROJECTS_LABEL = 'All Projects';
const SWIPE_THRESHOLD_PX = 40;

export default class CustomerPortal_MyAccounts extends LightningElement {
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
            this.pageDescription = data.description;
            this.filterOptions = this.buildFilterOptions(data.projectFilters);
            this.rawAccounts = (data.accounts || []).map((acc) => this.initializeAccountCard(acc));
        } else if (error) {
            this.isLoading = false;
            this.hasError = true;
            console.error('Error loading My Accounts page data', error);
            this.showErrorToast('Error in loading the account data');
        }
    }

    buildFilterOptions(projectFilters) {
        const options = [{ label: ALL_PROJECTS_LABEL, value: ALL_PROJECTS_VALUE }];
        (projectFilters || []).forEach((f) => {
            options.push({ label: f.label, value: f.value });
        });
        return options.map((opt) => ({
            ...opt,
            itemClass:
                opt.value === this.selectedProjectFilter
                    ? 'filter-menu-item filter-menu-item-active'
                    : 'filter-menu-item'
        }));
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

    get showListView() {
        return !this.isLoading && !this.hasError && this.currentView === 'list';
    }

    get showDetailView() {
        return !this.isLoading && !this.hasError && this.currentView === 'detail';
    }

    get selectedFilterLabel() {
        const match = this.filterOptions.find((o) => o.value === this.selectedProjectFilter);
        return match ? match.label : 'Filter By Projects';
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
            dotClass:
                img.index === account.currentIndex ? 'carousel-dot carousel-dot-active' : 'carousel-dot'
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

    get myAccountTabClass() {
        return this.activeTab === 'myAccount' ? 'tab-btn tab-btn-active' : 'tab-btn';
    }

    get myPayablesTabClass() {
        return this.activeTab === 'myPayables' ? 'tab-btn tab-btn-active' : 'tab-btn';
    }

    get isMyAccountTab() {
        return this.activeTab === 'myAccount';
    }

    get isMyPayablesTab() {
        return this.activeTab === 'myPayables';
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
            itemClass:
                opt.value === value ? 'filter-menu-item filter-menu-item-active' : 'filter-menu-item'
        }));
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
            a.id === accountId ? { ...a, currentIndex: newIndex } : a
        );
    }

    handleViewDetails(event) {
        const accountId = event.currentTarget.dataset.accountId;
        this.selectedAccountId = accountId;
        this.currentView = 'detail';
        this.activeTab = 'myAccount';
        this.expandedPayableId = undefined;
        this.loadAccountDetails(accountId);
    }

    handleBack() {
        this.currentView = 'list';
        this.accountDetails = undefined;
        this.payableRows = [];
        this.selectedAccountId = undefined;
    }

    async loadAccountDetails(accountId) {
        this.isDetailLoading = true;
        try {
            const data = await getMyAccountDetails({ accountId });
            this.accountDetails = data;
            this.payableRows = (data.payables || []).map((p) => this.decoratePayable(p));
        } catch (error) {
            this.hasError = true;
            console.error('Error loading account details', error);
            this.showErrorToast('Error loading account details.');
        } finally {
            this.isDetailLoading = false;
        }
    }

    handleShowMyAccount() {
        this.activeTab = 'myAccount';
    }

    handleShowMyPayables() {
        this.activeTab = 'myPayables';
    }

    decoratePayable(payable) {
        const isExpanded = payable.id === this.expandedPayableId;
        return {
            ...payable,
            isExpanded,
            chevronIcon: isExpanded ? 'utility:chevronup' : 'utility:chevrondown'
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

    handleRetry() {
        this.hasError = false;
        this.isLoading = true;
        getMyAccountsPageData()
            .then((data) => {
                this.isLoading = false;
                this.pageDescription = data.description;
                this.filterOptions = this.buildFilterOptions(data.projectFilters);
                this.rawAccounts = (data.accounts || []).map((acc) => this.initializeAccountCard(acc));
            })
            .catch((error) => {
                this.isLoading = false;
                this.hasError = true;
                console.error('Retry failed', error);
                this.showErrorToast('Retry failed');
            });
    }

    showErrorToast(message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Something went wrong',
                message,
                variant: 'error',
                mode: 'dismissable'
            })
        );
    }

    handleFilterKeydown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            event.currentTarget.click();
        } else if (event.key === 'Escape') {
            this.isFilterMenuOpen = false;
        }
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
}