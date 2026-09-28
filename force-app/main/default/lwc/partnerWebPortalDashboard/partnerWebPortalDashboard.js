import { LightningElement, wire, track } from 'lwc';
import getTotalLead from '@salesforce/apex/PartnerPortalDashboard.getLeaddetail';
import getTotalVisit from '@salesforce/apex/PartnerPortalDashboard.getSitedetail';
import getCurrentUser from '@salesforce/apex/PartnerPortalDashboard.getCurrentUser';

export default class PartnerWebPortalDashboard extends LightningElement {

    leadcount = '';
    visitcount = '';
    error;
    userName = '';

    // ================= BANNER CAROUSEL =================
    @track bannerIndex = 0;

    bannerImages = [
        'https://picsum.photos/seed/banner1/500/80',
        'https://picsum.photos/seed/banner2/500/80'
    ];

    get bannerSlides() {
        return this.bannerImages.map((url, i) => ({
            url,
            index: i,
            key: 'banner-' + i,
            slideClass: i === this.bannerIndex
                ? 'banner-slide active'
                : 'banner-slide',
            dotClass: i === this.bannerIndex
                ? 'banner-dot active'
                : 'banner-dot'
        }));
    }

    handleBannerPrev() {
        const total = this.bannerImages.length;
        this.bannerIndex = (this.bannerIndex - 1 + total) % total;
    }

    handleBannerNext() {
        const total = this.bannerImages.length;
        this.bannerIndex = (this.bannerIndex + 1) % total;
    }

    handleBannerDot(event) {
        this.bannerIndex = Number(event.currentTarget.dataset.index);
    }

    // Auto-rotate every 5s (remove if unwanted)
    bannerTimer;

    connectedCallback() {
        this.bannerTimer = window.setInterval(() => {
            this.handleBannerNext();
        }, 5000);
    }

    disconnectedCallback() {
        if (this.bannerTimer) {
            window.clearInterval(this.bannerTimer);
        }
    }

    // ================= WIRES =================
    @wire(getTotalLead)
    wiredLead({ data, error }) {
        if (data) {
            this.leadcount = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.leadcount = undefined;
        }
    }

    @wire(getTotalVisit)
    wiredVisit({ data, error }) {
        if (data) {
            this.visitcount = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.visitcount = undefined;
        }
    }

    @wire(getCurrentUser)
    wireduser({ data }) {
        if (data) {
            this.userName = data;
        }
    }
}