import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import CP_ASSETS from '@salesforce/resourceUrl/customerPortalAssets';
import getDashboardData from '@salesforce/apex/CustomerPortalController.getDashboardData';
import getHandoverData from '@salesforce/apex/CustomerPortalController.getHandoverData';

const AUTOPLAY_MS = 1000;

// Figma p7 ring: 110px wide, 13.5px stroke (outer radius 55, inner 41.5) -> circle radius 48.25 in a 110 viewBox
const RING_RADIUS = 48.25;
const RING_CIRCUMFERENCE = 2 * Math.PI * RING_RADIUS;

const LABELS = {
    loading: 'Loading',
    listSeparator: ', ',
    welcome: 'Welcome',
    customerId: 'Customer ID',
    heroLabel: 'Featured projects',
    showSlide: 'Show slide',
    quickLinks: 'Quick links',
    supportTitle: 'Support',
    handoverTitle: 'Handover',
    view: 'View',
    viewSupport: 'View support requests',
    viewHandover: 'View handover checklist',
    referText: 'You love JK Properties, your friends are going to love us too.',
    referButton: 'Refer & Earn Now',
    faqTitle: 'FAQs',
    faqText: 'Billing, Agreement, Home Loan, etc.',
    back: 'Back to dashboard',
    handoverPageTitle: 'Handover (Checklist for Final Handing over)',
    selectProperty: 'Select Property',
    selectPlaceholder: 'Select',
    projectName: 'Project Name:',
    colSr: 'Sr.',
    colActivity: 'Activity',
    colDescription: 'Description',
    colStatus: 'Status',
    colRemarks: 'Remarks',
    noProperties: 'No properties are available for handover yet.',
    noCards: 'There is no handover checklist for this property yet.',
    noItems: 'There are no checklist items for this type yet.',
    errorTitle: 'Error',
    dashboardError: 'Unable to load dashboard data. Please try again.',
    handoverError: 'Unable to load handover data. Please try again.',
    retry: 'Try again'
};

// Row status -> outlined pill colour (Figma p12: Completed green, Rectification amber, N/A red)
function pillClass(status) {
    const value = (status || '').trim().toLowerCase();
    if (value === 'completed') {
        return 'ho-pill ho-pill_completed';
    }
    if (value === 'n/a' || value === 'na' || value === 'not applicable') {
        return 'ho-pill ho-pill_na';
    }
    return 'ho-pill ho-pill_pending';
}

export default class CustomerPortal_Dashboard extends LightningElement {
    labels = LABELS;
    referEarnImage = CP_ASSETS + '/refer-earn.png';
    faqBadgeImage = CP_ASSETS + '/faq-badge.svg';
    emptyImage = CP_ASSETS + '/empty-state.svg';

    isLoading = true;
    isHandoverLoading = false;
    isHandoverView = false;
    dashboardErrorMessage = '';
    handoverErrorMessage = '';

    dashboard;
    activeIndex = 0;
    _timer;
    _handoverRequest = 0;

    selectedPropertyId;
    selectedProperty;
    handoverTitle = '';
    handoverProperties = [];
    hasHandoverData = false;

    // each card carries its own checklist items; one card's table is open at a time
    checklistCards = [];
    selectedCardId = null;

    connectedCallback() {
        this.loadDashboard();
    }

    disconnectedCallback() {
        this.stopAutoplay();
    }

    async loadDashboard() {
        this.isLoading = true;
        this.dashboardErrorMessage = '';
        try {
            this.dashboard = await getDashboardData();
            this.activeIndex = 0;
            this.startAutoplay();
        } catch (error) {
            console.error('Dashboard load failed', error);
            this.dashboardErrorMessage = LABELS.dashboardError;
            this.showError(LABELS.dashboardError);
        } finally {
            this.isLoading = false;
        }
    }

    handleRetry() {
        this.loadDashboard();
    }

    // ---------- Dashboard: head ----------
    get welcomeText() {
        const name = this.dashboard && this.dashboard.customerName;
        return name ? `${LABELS.welcome} ${name}!` : `${LABELS.welcome}!`;
    }

    get customerIdText() {
        const id = this.dashboard && this.dashboard.customerId;
        return id ? `${LABELS.customerId} ${id}` : '';
    }

    get dashboardDate() {
        return (this.dashboard && this.dashboard.dashboardDate) || '';
    }

    get showDateSeparator() {
        return Boolean(this.customerIdText && this.dashboardDate);
    }

    // ---------- Dashboard: hero carousel (Figma p7, p9, p11) ----------
    get slides() {
        return (this.dashboard && this.dashboard.heroSlides) || [];
    }

    get hasSlides() {
        return this.slides.length > 0;
    }

    get heroSlides() {
        return this.slides.map((s, index) => {
            const active = index === this.activeIndex;
            return {
                ...s,
                index,
                slideClass: active ? 'dash-slide dash-slide_active' : 'dash-slide',
                ariaHidden: active ? 'false' : 'true',
                dotClass: active ? 'cp-dot cp-dot_active' : 'cp-dot',
                ariaCurrent: active ? 'true' : undefined,
                dotLabel: `${LABELS.showSlide} ${index + 1}`
            };
        });
    }

    get activeSlide() {
        return this.slides[this.activeIndex];
    }

    startAutoplay = () => {
        this.stopAutoplay();
        if (this.slides.length > 1 && !this.isHandoverView) {
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            this._timer = setInterval(() => {
                this.activeIndex = (this.activeIndex + 1) % this.slides.length;
            }, AUTOPLAY_MS);
        }
    };

    stopAutoplay() {
        if (this._timer) {
            clearInterval(this._timer);
            this._timer = null;
        }
    }

    pauseAutoplay = () => {
        this.stopAutoplay();
    };

    handleDotClick(event) {
        this.activeIndex = Number(event.currentTarget.dataset.index);
        this.startAutoplay();
    }

    // ---------- Dashboard: quick links ----------
    get quickLinks() {
        const links = (this.dashboard && this.dashboard.quickLinks) || [];
        return links.map((l) => ({
            ...l,
            isProperties: l.iconKey === 'properties',
            isConstruction: l.iconKey === 'construction',
            isDocuments: l.iconKey === 'documents',
            // Figma p7: the My Properties icon is navy, the other three are black
            iconClass: l.iconKey === 'properties' ? 'dash-quick__icon dash-quick__icon_brand' : 'dash-quick__icon'
        }));
    }

    // ---------- Dashboard: Support / Handover rings ----------
    static dash(pct) {
        const p = Math.max(0, Math.min(100, Number(pct) || 0));
        return `${((p / 100) * RING_CIRCUMFERENCE).toFixed(2)} ${RING_CIRCUMFERENCE.toFixed(2)}`;
    }

    get supportData() {
        return (this.dashboard && this.dashboard.supportData) || {};
    }

    get handoverSummary() {
        return (this.dashboard && this.dashboard.handoverData) || {};
    }

    get supportDash() {
        return CustomerPortal_Dashboard.dash(this.supportData.progress);
    }

    get handoverDash() {
        return CustomerPortal_Dashboard.dash(this.handoverSummary.percentage);
    }

    get supportCount() {
        const count = this.supportData.pendingCount;
        return count === undefined || count === null ? '' : String(count);
    }

    get supportStatus() {
        return this.supportData.status || '';
    }

    get handoverPercentText() {
        const pct = this.handoverSummary.percentage;
        return pct === undefined || pct === null ? '' : `${pct}%`;
    }

    get handoverStatus() {
        return this.handoverSummary.status || '';
    }

    // the two ring lines are separate boxes; screen readers get them as one phrase
    get supportRingText() {
        return [this.supportCount, this.supportStatus].filter(Boolean).join(' ');
    }

    get handoverRingText() {
        return [this.handoverPercentText, this.handoverStatus].filter(Boolean).join(' ');
    }

    handleNavigate(event) {
        const page = event.currentTarget.dataset.page;
        if (page) {
            this.dispatchEvent(new CustomEvent('navigate', { detail: { page } }));
        }
    }

    // ---------- Handover checklist (Figma p8, p10, p12, p13) ----------
    async handleOpenHandover() {
        this.stopAutoplay();
        this.isHandoverView = true;
        this.notifyViewChange();
        this.scrollToTop();
        await this.loadHandover(this.selectedPropertyId);
    }

    handleBack() {
        this.isHandoverView = false;
        this.notifyViewChange();
        this.scrollToTop();
        this.startAutoplay();
    }

    async loadHandover(propertyId) {
        const request = ++this._handoverRequest;
        this.isHandoverLoading = true;
        this.handoverErrorMessage = '';
        try {
            const data = await getHandoverData({ propertyId: propertyId || null });
            if (request !== this._handoverRequest) {
                return; // a newer property choice is loading; keep only the latest answer
            }
            this.handoverTitle = data.title;
            this.handoverProperties = data.properties || [];
            this.selectedProperty = data.selectedProperty;
            this.selectedPropertyId = data.selectedProperty ? data.selectedProperty.id : null;
            this.checklistCards = data.checklistCards || [];
            this.selectedCardId = null; // collapse any open table on (re)load
            this.hasHandoverData = true;
        } catch (error) {
            if (request !== this._handoverRequest) {
                return;
            }
            console.error('Handover load failed', error);
            this.handoverErrorMessage = LABELS.handoverError;
            this.showError(LABELS.handoverError);
        } finally {
            if (request === this._handoverRequest) {
                this.isHandoverLoading = false;
            }
        }
    }

    get handoverHeading() {
        return this.handoverTitle || LABELS.handoverPageTitle;
    }

    get propertyOptions() {
        return this.handoverProperties.map((p) => ({ ...p, selected: p.id === this.selectedPropertyId }));
    }

    // Figma p8: "Select" placeholder while no property is chosen
    get hasNoSelection() {
        return !this.selectedPropertyId;
    }

    // with no property at all an empty picker says nothing: the empty state stands alone
    get showPropertySelect() {
        return this.hasHandoverData && this.handoverProperties.length > 0;
    }

    get showHandoverSpinner() {
        return this.isHandoverLoading;
    }

    get showNoProperties() {
        return this.hasHandoverData && !this.isHandoverLoading && this.handoverProperties.length === 0;
    }

    get showChecklist() {
        return !this.isHandoverLoading && Boolean(this.selectedProperty);
    }

    get showNoCards() {
        return this.showChecklist && this.checklistCards.length === 0;
    }

    get projectNameText() {
        const name = this.selectedProperty && this.selectedProperty.projectName;
        return name ? `${LABELS.projectName} ${name}` : '';
    }

    handlePropertyChange(event) {
        this.selectedPropertyId = event.target.value;
        this.loadHandover(this.selectedPropertyId);
    }

    handleHandoverRetry() {
        this.loadHandover(this.selectedPropertyId);
    }

    get decoratedCards() {
        return this.checklistCards.map((card) => {
            const isOpen = this.selectedCardId === card.id;
            const items = (card.checklistItems || []).map((item) => ({
                ...item,
                pillClass: pillClass(item.status)
            }));
            return {
                ...card,
                isOpen,
                ariaExpanded: isOpen ? 'true' : 'false',
                ariaLabel: [card.title, card.description, card.status].filter(Boolean).join(LABELS.listSeparator),
                cardClass: isOpen ? 'cp-card ho-card ho-card_open' : 'cp-card ho-card',
                badgeClass:
                    card.statusClass === 'completed'
                        ? 'cp-badge cp-badge_completed ho-badge'
                        : 'cp-badge cp-badge_progress ho-badge',
                items,
                hasNoItems: items.length === 0
            };
        });
    }

    // one card's table open at a time: click again to collapse, click another to switch
    handleCardClick(event) {
        const id = event.currentTarget.dataset.id;
        this.selectedCardId = this.selectedCardId === id ? null : id;
    }

    // The shell paints the Dashboard on #fafafa (Figma p7); the handover pages are white (p8-p13).
    // The shell can listen to this to drop the tint while the checklist is open.
    notifyViewChange() {
        this.dispatchEvent(
            new CustomEvent('viewchange', { detail: { view: this.isHandoverView ? 'handover' : 'dashboard' } })
        );
    }

    // Switching views keeps the page scroll otherwise (e.g. coming back from a long checklist on a phone)
    scrollToTop() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        requestAnimationFrame(() => {
            const root = this.template.querySelector('.cp-page');
            if (root && typeof root.scrollIntoView === 'function') {
                root.scrollIntoView({ block: 'start' });
            }
        });
    }

    showError(message) {
        this.dispatchEvent(new ShowToastEvent({ title: LABELS.errorTitle, message, variant: 'error' }));
    }
}