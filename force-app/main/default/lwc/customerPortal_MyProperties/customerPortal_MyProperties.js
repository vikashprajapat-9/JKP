import { LightningElement } from 'lwc';
import getMyProperties from '@salesforce/apex/customerPortalController.getMyProperties';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const VIEW_LIST = 'LIST_VIEW';
const VIEW_DETAIL = 'DETAIL_VIEW';

const TAB_BOOKING = 'BOOKING_DETAILS';
const TAB_PAYMENT = 'PAYMENT_PLAN';

export default class CustomerPortal_MyProperties extends LightningElement {

    pageData;
    isLoading = true;
    hasError = false;

    currentView = VIEW_LIST;
    activeTab = TAB_BOOKING;

    selectedProjectFilter = '';
    isFilterMenuOpen = false;

    selectedPropertyId;
    expandedBookingId = null;

    connectedCallback() {
        this.loadMyProperties();
    }

    // async loadMyProperties() {
    //     debugger
    //     this.isLoading = true;
    //     this.hasError = false;

    //     try {
    //         this.pageData = await getMyProperties();
    //     } catch (error) {
    //         this.hasError = true;
    //         console.error('customerPortal_MyProperties: failed to load data', error);
    //     } finally {
    //         this.isLoading = false;
    //     }
    // }

    async loadMyProperties() {
        this.isLoading = true;
        this.hasError = false;

        try {
            this.pageData = await getMyProperties();
        } catch (error) {
            this.hasError = true;
            console.error('customerPortal_MyProperties: failed to load data', error);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'Unable to load your properties. Please try again.',
                    variant: 'error'
                })
            );
        } finally {
            this.isLoading = false;
        }
    }

    get showContent() {
        return !this.isLoading && !this.hasError && this.pageData;
    }

    get isListView() {
        return this.currentView === VIEW_LIST;
    }

    get isDetailView() {
        return this.currentView === VIEW_DETAIL;
    }

    get isBookingTab() {
        return this.activeTab === TAB_BOOKING;
    }

    get isPaymentTab() {
        return this.activeTab === TAB_PAYMENT;
    }

    get bookingTabClass() {
        return this.isBookingTab ? 'mp-tab mp-tab_active' : 'mp-tab';
    }

    get paymentTabClass() {
        return this.isPaymentTab ? 'mp-tab mp-tab_active' : 'mp-tab';
    }

    get filterButtonLabel() {
        if (!this.selectedProjectFilter) {
            return 'Filter By Projects';
        }
        return this.selectedProjectFilter;
    }

    get filterCaretClass() {
        return this.isFilterMenuOpen ? 'filter-caret filter-caret_open' : 'filter-caret';
    }

    get allProjectsOptionClass() {
        return !this.selectedProjectFilter ? 'filter-menu-item filter-menu-item_active' : 'filter-menu-item';
    }

    get filterOptionsDecorated() {
        if (!this.pageData || !this.pageData.projectFilters) {
            return [];
        }
        return this.pageData.projectFilters.map((opt) => {
            return {
                ...opt,
                itemClass:
                    this.selectedProjectFilter === opt.value
                        ? 'filter-menu-item filter-menu-item_active'
                        : 'filter-menu-item'
            };
        });
    }

    toggleFilterMenu() {
        this.isFilterMenuOpen = !this.isFilterMenuOpen;
    }

    handleFilterSelect(event) {
        this.selectedProjectFilter = event.currentTarget.dataset.value || '';
        this.isFilterMenuOpen = false;
    }

    get filteredProperties() {
        if (!this.pageData || !this.pageData.properties) {
            return [];
        }
        const all = this.selectedProjectFilter
            ? this.pageData.properties.filter((p) => p.projectName === this.selectedProjectFilter)
            : this.pageData.properties;

        return all.map((p, idx) => {
            return { ...p, srNo: idx + 1 };
        });
    }

    get hasNoFilteredProperties() {
        return this.filteredProperties.length === 0;
    }

    handleOpenDetails(event) {
        this.selectedPropertyId = event.currentTarget.dataset.id;
        this.currentView = VIEW_DETAIL;
        this.activeTab = TAB_BOOKING;
        this.expandedBookingId = null;
    }

    handleBack() {
        this.currentView = VIEW_LIST;
        this.selectedPropertyId = null;
        this.expandedBookingId = null;
    }

    get selectedProperty() {
        if (!this.pageData || !this.pageData.properties || !this.selectedPropertyId) {
            return null;
        }
        const prop = this.pageData.properties.find((p) => p.id === this.selectedPropertyId);
        if (!prop) {
            return null;
        }

        const total = (prop.paymentPlan || []).reduce((sum, row) => {
            const numeric = parseFloat((row.amount || '').replace(/[^0-9.]/g, ''));
            return sum + (isNaN(numeric) ? 0 : numeric);
        }, 0);

        return {
            ...prop,
            applicants: (prop.applicants || []).map((a, idx) => {
                return {
                    ...a,
                    avatarClass: idx === 0 ? 'applicant-avatar applicant-avatar_blue' : 'applicant-avatar applicant-avatar_orange'
                };
            }),
            paymentPlanTotal: prop.paymentPlanTotal || this.formatCurrency(total)
        };
    }

    formatCurrency(value) {
        return 'LKR ' + Math.round(value).toLocaleString('en-US');
    }


    handleShowBookingTab() {
        this.activeTab = TAB_BOOKING;
    }

    handleShowPaymentTab() {
        this.activeTab = TAB_PAYMENT;
        this.expandedBookingId = null;
    }

    // get decoratedBookings() {
    //     debugger
    //     const prop = this.selectedProperty;
    //     if (!prop || !prop.bookingDetails) {
    //         return [];
    //     }
    //     return prop.bookingDetails.map((booking, idx) => {
    //         return {
    //             ...booking,
    //             srNo: idx + 1,
    //             isExpanded: booking.id === this.expandedBookingId
    //         };
    //     });
    // }

    get decoratedBookings() {
        const prop = this.selectedProperty;
        if (!prop || !prop.bookingDetails) {
            return [];
        }
        return prop.bookingDetails.map((booking, idx) => {
            return {
                ...booking,
                srNo: idx + 1,
                isExpanded: booking.id === this.expandedBookingId
            };
        });
    }

    get bookingRows() {
        const rows = [];
        this.decoratedBookings.forEach((booking) => {
            rows.push({
                key: booking.id,
                isDetail: false,
                booking
            });
            if (booking.isExpanded) {
                rows.push({
                    key: booking.id + '-detail',
                    isDetail: true,
                    booking
                });
            }
        });
        return rows;
    }

    handleToggleBooking(event) {
        const id = event.currentTarget.dataset.id;
        this.expandedBookingId = this.expandedBookingId === id ? null : id;
    }
}