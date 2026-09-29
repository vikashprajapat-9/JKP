import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import REFER_EARN_IMAGE from '@salesforce/resourceUrl/ReferEarnImage';
import getDashboardData from '@salesforce/apex/CustomerPortalController.getDashboardData';
import getHandoverData from '@salesforce/apex/CustomerPortalController.getHandoverData';
// CHANGED: updateHandoverStatus import removed — status-update logic no longer used.

const AUTOPLAY_MS = 1000;

export default class CustomerPortal_Dashboard extends LightningElement {
    referEarnImage = REFER_EARN_IMAGE;

    isLoading = true;
    isHandoverLoading = false;
    isHandoverView = false;

    dashboard;
    activeIndex = 0;
    _timer;

    selectedPropertyId;
    selectedProperty;
    handoverTitle = '';
    handoverProperties = [];

    // CHANGED: flat handoverItems replaced with checklistCards (each card carries its own items)
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
        try {
            this.dashboard = await getDashboardData();
            this.activeIndex = 0;
            this.startAutoplay();
        } catch (error) {
            console.error('Dashboard load failed', error);
            this.showError('Unable to load dashboard data. Please try again.');
        } finally {
            this.isLoading = false;
        }
    }

    get slides() {
        return (this.dashboard && this.dashboard.heroSlides) || [];
    }

    get heroSlides() {
        return this.slides.map((s, index) => {
            const active = index === this.activeIndex;
            return {
                ...s,
                index,
                slideClass: active ? 'slide active' : 'slide',
                ariaHidden: active ? 'false' : 'true',
                dotClass: active ? 'dot active' : 'dot',
                dotLabel: `Show slide ${index + 1}`
            };
        });
    }

    get activeSlide() {
        return this.slides[this.activeIndex];
    }

    startAutoplay = () => {
        this.stopAutoplay();
        if (this.slides.length > 1 && !this.isHandoverView) {
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

    get quickLinks() {
        const links = (this.dashboard && this.dashboard.quickLinks) || [];
        return links.map((l) => ({
            ...l,
            isProperties: l.iconKey === 'properties',
            isConstruction: l.iconKey === 'construction',
            isDocuments: l.iconKey === 'documents'
        }));
    }

    static dash(pct) {
        const p = Math.max(0, Math.min(100, Number(pct) || 0));
        const circumference = 2 * Math.PI * 42; // matches r="42" on the ring circles
        return `${((p / 100) * circumference).toFixed(2)} ${circumference.toFixed(2)}`;
    }

    get supportDash() {
        return CustomerPortal_Dashboard.dash(this.dashboard.supportData.progress);
    }

    get handoverDash() {
        return CustomerPortal_Dashboard.dash(this.dashboard.handoverData.percentage);
    }

    handleNavigate(event) {
        const page = event.currentTarget.dataset.page;
        if (page) {
            this.dispatchEvent(new CustomEvent('navigate', { detail: { page } }));
        }
    }

    async handleOpenHandover() {
        this.stopAutoplay();
        this.isHandoverView = true;
        await this.loadHandover(this.selectedPropertyId);
    }

    handleBack() {
        this.isHandoverView = false;
        this.startAutoplay();
    }

    async loadHandover(propertyId) {
        this.isHandoverLoading = true;
        try {
            const data = await getHandoverData({ propertyId: propertyId || null });
            this.handoverTitle = data.title;
            this.handoverProperties = data.properties || [];
            this.selectedProperty = data.selectedProperty;
            this.selectedPropertyId = data.selectedProperty ? data.selectedProperty.id : null;
            this.checklistCards = data.checklistCards || [];
            this.selectedCardId = null; // collapse any open table on (re)load
        } catch (error) {
            console.error('Handover load failed', error);
            this.showError('Unable to load handover data. Please try again.');
        } finally {
            this.isHandoverLoading = false;
        }
    }

    get propertyOptions() {
        return this.handoverProperties.map((p) => ({ ...p, selected: p.id === this.selectedPropertyId }));
    }

    handlePropertyChange(event) {
        this.selectedPropertyId = event.target.value;
        this.loadHandover(this.selectedPropertyId);
    }

    // CHANGED: one card's table open at a time — click again to collapse, click another to switch.
    get decoratedCards() {
        return this.checklistCards.map((card) => {
            const isOpen = this.selectedCardId === card.id;
            return {
                ...card,
                isOpen,
                cardClass: isOpen ? 'ho-card open' : 'ho-card',
                pillClass: card.statusClass === 'completed' ? 'pill completed' : 'pill inprogress',
                items: (card.checklistItems || []).map((item) => ({
                    ...item,
                    rowPillClass: item.status === 'Completed' ? 'row-pill completed' : 'row-pill pending'
                }))
            };
        });
    }

    handleCardClick(event) {
        const id = event.currentTarget.dataset.id;
        this.selectedCardId = this.selectedCardId === id ? null : id;
    }

    // REMOVED: handleAction / handleRemarksChange / decorate / replaceItem —
    // the checklist table is now read-only, so there is no status-update logic left in the UI.

    showError(message) {
        this.dispatchEvent(new ShowToastEvent({ title: 'Error', message, variant: 'error' }));
    }
}