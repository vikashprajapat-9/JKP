import { LightningElement } from 'lwc';
import getMyProperties from '@salesforce/apex/CustomerPortalController.getMyProperties';
import getMyPropertyDetails from '@salesforce/apex/CustomerPortalController.getMyPropertyDetails';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import CP_ASSETS from '@salesforce/resourceUrl/customerPortalAssets';
import { BACK_ARROW, FILTER_FUNNEL, FILTER_CHEVRON, PERSON } from './icons';

const VIEW_LIST = 'LIST_VIEW';
const VIEW_DETAIL = 'DETAIL_VIEW';

const TAB_BOOKING = 'BOOKING_DETAILS';
const TAB_PAYMENT = 'PAYMENT_PLAN';

// Shown where a field has no value (Figma p24 uses "-" in the total row).
const EMPTY_VALUE = '-';

// Visible text (Figma pages 21-24). Plain constants: the portal does not use Custom Labels.
const TEXT = {
    loading: 'Loading properties',
    loadingDetails: 'Loading property details',
    loadError: "We couldn't load My Properties right now. Please try again in a moment.",
    toastTitle: 'Error',
    toastLoadError: 'Unable to load your properties. Please try again.',
    detailsError: 'Unable to load property details.',
    filterPlaceholder: 'Filter By Projects',
    allProjects: 'All Projects',
    emptyFiltered: 'No properties found for this project.',
    emptyAll: 'You have no properties yet.',
    back: 'Back',
    colSr: 'Sr.',
    colDescription: 'Description',
    colUnitNumber: 'Unit Number',
    colCarParks: 'No. of car parks:',
    colType: 'Type',
    colAction: 'Action',
    viewDetails: 'View Details',
    tabsLabel: 'Property details',
    tabBooking: 'Booking Details',
    tabPayment: 'Payment Plan',
    bankDetails: 'Bank Details',
    payDescription: 'Description',
    payPercentage: '%',
    payTrancheDate: 'Tranche Date',
    payAmount: 'Amount(LKR)',
    payTotal: 'Total (Inclusive of taxes)'
};

const APPLICANT_LABELS = {
    dateOfBirth: 'Date of Birth:',
    companyName: 'Company Name:',
    mobileNumber: 'Mobile Number:',
    email: 'Email ID:',
    address: 'Address:',
    nic: 'National Identity Card (NIC) Number:',
    tin: 'Taxpayer Identification Number (TIN):',
    passport: 'Passport Number :',
    vatNumber: 'VAT Number (VAT):',
    businessRegistrationNumber: 'Business Registration Number:'
};

// Figma p23 (First Applicant, a person) and p22 (Second Applicant, a company): two rows of fields each.
const PERSON_ROWS = [
    ['dateOfBirth', 'mobileNumber', 'email', 'address'],
    ['nic', 'tin', 'passport']
];
const COMPANY_ROWS = [
    ['companyName', 'mobileNumber', 'email', 'address'],
    ['vatNumber', 'businessRegistrationNumber']
];
const COMPANY_KEYS = ['companyName', 'vatNumber', 'businessRegistrationNumber'];

// Figma p23: the expanded booking panel (booking rows, divider, "Bank Details" rows).
const BOOKING_ROWS = [
    [
        ['spaDate', 'SPA Date:'],
        ['flatVilla', 'Flat/Villa:'],
        ['towerBlockVilla', 'Tower/Block/Villa:'],
        ['squareFeet', 'Square Feet:']
    ],
    [
        ['purchasedPrice', 'Purchased Price(inc. tax)'],
        ['unitNumber', 'Unit Number:'],
        ['escrowAccountNumber', 'Escrow Account No.:']
    ]
];
const BANK_ROWS = [
    [
        ['accountName', 'Account Name:'],
        ['accountNo', 'Account No.:'],
        ['bankName', 'Bank Name:']
    ],
    [
        ['branchName', 'Branch Name:'],
        ['swiftCode', 'Swift Code:']
    ]
];

const ICONS = {
    back: BACK_ARROW,
    funnel: FILTER_FUNNEL,
    filterChevron: FILTER_CHEVRON,
    person: PERSON
};

function hasValue(value) {
    return value !== null && value !== undefined && String(value).trim() !== '';
}

function displayValue(value) {
    return hasValue(value) ? String(value) : EMPTY_VALUE;
}

// One row of label / value pairs for the booking panel; rows of four use the 4-column grid, the others 3 columns.
function panelRow(source, fields, rowKey) {
    const data = source || {};
    return {
        key: rowKey,
        rowClass: fields.length >= 4 ? 'bk-fields bk-fields_4' : 'bk-fields bk-fields_3',
        fields: fields.map(([name, label]) => ({
            key: rowKey + '-' + name,
            label,
            value: displayValue(data[name])
        }))
    };
}

// The applicant's rows as Figma shows them: the person or company set (always shown, "-" when empty),
// plus any other filled-in field so no data is hidden.
function applicantRows(applicant, index) {
    const isCompany = COMPANY_KEYS.some((name) => hasValue(applicant[name]));
    const rows = (isCompany ? COMPANY_ROWS : PERSON_ROWS).map((row) => [...row]);
    const shown = new Set(rows.flat());
    Object.keys(APPLICANT_LABELS).forEach((name) => {
        if (!shown.has(name) && hasValue(applicant[name])) {
            rows[1].push(name);
        }
    });
    return rows.map((names, rowIndex) => {
        const rowKey = 'ap-' + index + '-' + rowIndex;
        return {
            key: rowKey,
            rowClass: 'ap-fields ap-fields_n' + Math.min(names.length, 5),
            fields: names.map((name) => ({
                key: rowKey + '-' + name,
                label: APPLICANT_LABELS[name],
                value: displayValue(applicant[name])
            }))
        };
    });
}

export default class CustomerPortal_MyProperties extends LightningElement {
    text = TEXT;
    icons = ICONS;
    emptyValue = EMPTY_VALUE;
    emptyImageUrl = CP_ASSETS + '/empty-state.svg';

    pageData;
    isLoading = true;
    hasError = false;
    propertyDetails;
    isDetailsLoading = false;
    hasDetailsError = false;
    currentView = VIEW_LIST;
    activeTab = TAB_BOOKING;

    selectedProjectFilter = '';
    isFilterMenuOpen = false;

    selectedPropertyId;
    expandedBookingId = null;

    connectedCallback() {
        this.loadMyProperties();
    }

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
                    title: TEXT.toastTitle,
                    message: TEXT.toastLoadError,
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
        return this.isBookingTab ? 'cp-tab cp-tab_active' : 'cp-tab';
    }

    get paymentTabClass() {
        return this.isPaymentTab ? 'cp-tab cp-tab_active' : 'cp-tab';
    }

    get bookingTabSelected() {
        return this.isBookingTab ? 'true' : 'false';
    }

    get paymentTabSelected() {
        return this.isPaymentTab ? 'true' : 'false';
    }

    /* ---------- Project filter (Figma p21, "Filter By Projects") ---------- */

    get filterButtonLabel() {
        const opt = (this.pageData?.projectFilters || []).find((o) => o.value === this.selectedProjectFilter);
        return opt ? opt.label : TEXT.filterPlaceholder;
    }

    get filterExpanded() {
        return this.isFilterMenuOpen ? 'true' : 'false';
    }

    get filterCaretClass() {
        return this.isFilterMenuOpen ? 'mp-filter__caret mp-filter__caret_open' : 'mp-filter__caret';
    }

    get allProjectsOptionClass() {
        return !this.selectedProjectFilter ? 'mp-filter__option mp-filter__option_active' : 'mp-filter__option';
    }

    get allProjectsSelected() {
        return !this.selectedProjectFilter ? 'true' : 'false';
    }

    get filterOptionsDecorated() {
        if (!this.pageData || !this.pageData.projectFilters) {
            return [];
        }
        return this.pageData.projectFilters.map((opt) => {
            const isSelected = this.selectedProjectFilter === opt.value;
            return {
                ...opt,
                itemClass: isSelected ? 'mp-filter__option mp-filter__option_active' : 'mp-filter__option',
                ariaSelected: isSelected ? 'true' : 'false'
            };
        });
    }

    toggleFilterMenu() {
        this.isFilterMenuOpen = !this.isFilterMenuOpen;
    }

    closeFilterMenu() {
        this.isFilterMenuOpen = false;
    }

    handleFilterKeydown(event) {
        if (event.key === 'Escape' && this.isFilterMenuOpen) {
            event.stopPropagation();
            this.isFilterMenuOpen = false;
        }
    }

    handleFilterSelect(event) {
        this.selectedProjectFilter = event.currentTarget.dataset.value || '';
        this.isFilterMenuOpen = false;
    }

    /* ---------- List (Figma p21) ---------- */

    get filteredProperties() {
        if (!this.pageData || !this.pageData.properties) {
            return [];
        }
        const all = this.selectedProjectFilter
            ? this.pageData.properties.filter((p) => p.projectId === this.selectedProjectFilter)
            : this.pageData.properties;

        return all.map((p, idx) => {
            return {
                ...p,
                srNo: idx + 1,
                displayProjectName: displayValue(p.projectName),
                displayUnitNumber: displayValue(p.unitNumber),
                displayCarParks: displayValue(p.carParks),
                displayType: displayValue(p.type)
            };
        });
    }

    get hasNoFilteredProperties() {
        return this.filteredProperties.length === 0;
    }

    get emptyText() {
        return this.selectedProjectFilter ? TEXT.emptyFiltered : TEXT.emptyAll;
    }

    async handleOpenDetails(event) {
        this.selectedPropertyId = event.currentTarget.dataset.id;
        this.currentView = VIEW_DETAIL;
        this.activeTab = TAB_BOOKING;
        this.expandedBookingId = null;
        this.propertyDetails = null;
        this.hasDetailsError = false;
        this.isFilterMenuOpen = false;
        this.isDetailsLoading = true;
        try {
            this.propertyDetails = await getMyPropertyDetails({ propertyId: this.selectedPropertyId });
        } catch (error) {
            this.hasDetailsError = true;
            console.error('customerPortal_MyProperties: failed to load property details', error);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: TEXT.toastTitle,
                    message: TEXT.detailsError,
                    variant: 'error'
                })
            );
        } finally {
            this.isDetailsLoading = false;
        }
    }

    handleBack() {
        this.currentView = VIEW_LIST;
        this.selectedPropertyId = null;
        this.expandedBookingId = null;
        this.hasDetailsError = false;
    }

    /* ---------- Details (Figma p22-24) ---------- */

    get selectedProperty() {
        const d = this.propertyDetails;
        if (!d) {
            return null;
        }

        const paymentPlan = (d.paymentPlan || []).map((row, i) => ({
            ...row,
            key: 'pp-' + i,
            displayDescription: displayValue(row.description),
            displayPercentage: displayValue(row.percentage),
            displayTrancheDate: displayValue(row.trancheDate),
            displayAmount: displayValue(row.amount)
        }));

        const totalPct = paymentPlan.reduce((sum, row) => {
            const n = parseFloat(row.percentage);
            return sum + (isNaN(n) ? 0 : n);
        }, 0);

        return {
            ...d,
            paymentPlan,
            paymentPlanTotalPercentage: Math.round(totalPct * 100) / 100 + '%',
            displayPaymentPlanTotal: displayValue(d.paymentPlanTotal),
            applicants: (d.applicants || []).map((a, i) => ({
                ...a,
                key: 'ap-' + i,
                avatarClass: i === 0 ? 'ap-avatar ap-avatar_blue' : 'ap-avatar ap-avatar_amber',
                displayName: displayValue(a.name),
                rows: applicantRows(a, i)
            }))
        };
    }

    get showDetailsAlert() {
        return this.hasDetailsError && !this.isDetailsLoading && !this.propertyDetails;
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

    // Figma p22 shows the project name in the booking row; getMyPropertyDetails leaves description empty, so use the
    // description of the same unit's row in the list (getMyProperties sets it to the project name).
    bookingDescription(booking) {
        if (hasValue(booking.description)) {
            return booking.description;
        }
        const listRow = (this.pageData?.properties || []).find((p) => p.id === booking.id);
        return listRow ? listRow.description || listRow.projectName : null;
    }

    get decoratedBookings() {
        const prop = this.selectedProperty;
        if (!prop || !prop.bookingDetails) {
            return [];
        }
        return prop.bookingDetails.map((booking, idx) => {
            const isExpanded = booking.id === this.expandedBookingId;
            return {
                ...booking,
                srNo: idx + 1,
                isExpanded,
                ariaExpanded: isExpanded ? 'true' : 'false',
                rowClass: isExpanded ? 'bk-row bk-row_open' : 'bk-row',
                displayDescription: displayValue(this.bookingDescription(booking)),
                displayUnitNumber: displayValue(booking.unitNumber),
                displayCarParks: displayValue(booking.carParks),
                displayType: displayValue(booking.type),
                panelRows: BOOKING_ROWS.map((row, i) => panelRow(booking, row, booking.id + '-b' + i)),
                bankRows: BANK_ROWS.map((row, i) => panelRow(booking.bankDetails, row, booking.id + '-k' + i))
            };
        });
    }

    get bookingRows() {
        const rows = [];
        this.decoratedBookings.forEach((booking) => {
            rows.push({
                key: booking.id,
                isDetail: false,
                trClass: booking.rowClass,
                booking
            });
            if (booking.isExpanded) {
                rows.push({
                    key: booking.id + '-detail',
                    isDetail: true,
                    trClass: 'bk-detail-row',
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