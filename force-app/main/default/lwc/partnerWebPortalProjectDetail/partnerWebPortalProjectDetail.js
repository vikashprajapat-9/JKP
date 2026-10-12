import { LightningElement, api } from 'lwc';
import LOCALE from '@salesforce/i18n/locale';
import CURRENCY from '@salesforce/i18n/currency';
import getProjectDetails from '@salesforce/apex/partnerWebPortalMarketingController.getProjectDetails';
import getCustomerProjectDetails from '@salesforce/apex/CustomerPortalProjectController.getProjectDetails';
import { amenityIconPath } from 'c/amenityIcons';

// Hero photos move to the next one on their own, like the project cards
const AUTO_SLIDE_MS = 2500;
// Document type icons (from Lucide, ISC License; see c/amenityIcons for the notice)
const DOC_ICONS = {
    pdf: 'M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z M14 2v4a2 2 0 0 0 2 2h4 M10 9H8 M16 13H8 M16 17H8',
    image: 'M5 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1 -2 2h-14a2 2 0 0 1 -2 -2v-14a2 2 0 0 1 2 -2Z M7 9a2 2 0 1 0 4 0a2 2 0 1 0 -4 0 M21 15l-3.086-3.086a2 2 0 0 0-2.828 0L6 21',
    video: 'M5 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1 -2 2h-14a2 2 0 0 1 -2 -2v-14a2 2 0 0 1 2 -2Z M7 3v18 M3 7.5h4 M3 12h18 M3 16.5h4 M17 3v18 M17 7.5h4 M17 16.5h4',
    file: 'M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z M14 2v4a2 2 0 0 0 2 2h4'
};

const isBlank = (value) => value === null || value === undefined || value === '';

// Direct OneDrive links stop working after about an hour, so older ones are not used
const DIRECT_LINK_MS = 50 * 60 * 1000;

// The short price form the design uses: "LKR 1.64 Cr", "LKR 45 L". Cut to two decimals, never rounded up, so a
// "starting at" price is never shown higher than it is (99,99,999 is "99.99 L", not "100 L").
function formatPrice(value) {
    const amount = Number(value);
    const code = CURRENCY || '';
    if (amount >= 1e7) {
        return `${code} ${Math.floor(amount / 1e5) / 100} Cr`.trim();
    }
    if (amount >= 1e5) {
        return `${code} ${Math.floor(amount / 1e3) / 100} L`.trim();
    }
    return `${code} ${amount.toLocaleString(LOCALE)}`.trim();
}

function formatArea(value) {
    return `${Number(value).toLocaleString(LOCALE)} sq.ft`;
}

// Possession is a date ("Jul 2026"); plain text is shown as it is
function formatPossession(value) {
    if (isBlank(value)) {
        return '';
    }
    const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(value));
    if (!match) {
        return String(value);
    }
    const date = new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])));
    try {
        return new Intl.DateTimeFormat(LOCALE, { month: 'short', year: 'numeric', timeZone: 'UTC' }).format(date);
    } catch (e) {
        return String(value);
    }
}

export default class PartnerWebPortalProjectDetail extends LightningElement {

    // { id, name, location, image, initial } from the project list
    @api project = {};
    // 'partner' (the default) or 'customer': the portal showing the page, which decides where the details are read
    @api portal = 'partner';

    // Everything below comes from getProjectDetails of that portal's controller
    detail;
    isLoading = true;
    loadError;
    view = 'detail';
    slideIndex = 0;
    // Hovering or keyboard focus on the photo pauses the slideshow
    heroPaused = false;
    heroFocused = false;
    autoSlideTimer;
    // When the details (and their direct OneDrive links) were loaded
    loadedAt;
    // The file open in the viewer, and the button that opened it (focus returns there)
    viewerFile = null;
    viewerOpener;

    connectedCallback() {
        this.loadDetails();
        // Started here, not after the load, so leaving before the details arrive leaves no timer running
        this.startAutoSlide();
    }

    disconnectedCallback() {
        clearInterval(this.autoSlideTimer);
        this.autoSlideTimer = undefined;
    }

    async loadDetails() {
        if (!this.project || !this.project.id) {
            this.isLoading = false;
            return;
        }
        this.isLoading = true;
        this.loadError = undefined;
        try {
            const load = this.portal === 'customer' ? getCustomerProjectDetails : getProjectDetails;
            this.detail = await load({ projectId: this.project.id });
            this.loadedAt = Date.now();
            this.slideIndex = 0;
        } catch (error) {
            this.loadError = error && error.body && error.body.message ? error.body.message : 'The project details could not be loaded.';
        } finally {
            this.isLoading = false;
        }
    }

    // ---------- header ----------
    get name() {
        return (this.detail && this.detail.name) || this.project.name;
    }

    get location() {
        return (this.detail && this.detail.location) || this.project.location;
    }

    get statusBadge() {
        return this.detail ? this.detail.status : undefined;
    }

    // Photos from the project's Project Images folder; the list's photo is shown until they arrive
    get slides() {
        const photos = this.detail ? this.detail.images.filter((image) => image.mediaUrl) : [];
        let slides = photos.map((image) => ({ key: image.id, url: image.mediaUrl }));
        if (!slides.length && !this.detail && this.project.image) {
            slides = [{ key: 'list-photo', url: this.project.image }];
        }
        const active = slides.length ? this.slideIndex % slides.length : 0;
        return slides.map((slide, index) => ({
            ...slide,
            slideClass: index === active ? 'hero-slide hero-slide_active' : 'hero-slide',
            dotClass: index === active ? 'hero-dot hero-dot_active' : 'hero-dot',
            dotKey: `dot-${slide.key}`,
            index,
            dotLabel: `Photo ${index + 1} of ${slides.length}`
        }));
    }

    get hasSlides() {
        return this.slides.length > 0;
    }

    get hasMultipleSlides() {
        return this.slides.length > 1;
    }

    get isLocationView() {
        return this.view === 'location';
    }

    get hasAddress() {
        return Boolean(this.location);
    }

    get mapMarkers() {
        return [{
            location: { Street: this.location },
            title: this.name,
            description: this.location
        }];
    }

    // ---------- facts and amenities ----------
    get possessionText() {
        if (!this.detail) {
            return this.isLoading ? '…' : '—';
        }
        return formatPossession(this.detail.possession) || '—';
    }

    get landParcelText() {
        if (!this.detail) {
            return this.isLoading ? '…' : '—';
        }
        return this.detail.landParcel || '—';
    }

    get amenities() {
        return (this.detail ? this.detail.amenities : []).map((amenity) => ({
            key: amenity.id,
            label: amenity.label,
            icon: amenityIconPath(amenity.icon)
        }));
    }

    get hasAmenities() {
        return this.amenities.length > 0;
    }

    // ---------- configurations and documents ----------
    get configurations() {
        return (this.detail ? this.detail.configurations : []).map((config) => {
            const type = config.unitType || 'Configuration';
            return {
                key: config.id,
                type,
                area: isBlank(config.squareFt) ? '' : formatArea(config.squareFt),
                hasArea: !isBlank(config.squareFt),
                price: isBlank(config.startingPrice) ? 'On request' : formatPrice(config.startingPrice),
                priceSheetId: config.priceSheet ? config.priceSheet.id : undefined,
                hasPriceSheet: !!config.priceSheet,
                viewLabel: `View the ${type} price sheet`,
                downloadLabel: `Download the ${type} price sheet`
            };
        });
    }

    get hasConfigurations() {
        return this.configurations.length > 0;
    }

    get showNoConfigurations() {
        return !this.isLoading && !this.hasConfigurations;
    }

    get documents() {
        return (this.detail ? this.detail.documents : []).map((doc) => ({
            key: doc.id,
            id: doc.id,
            label: doc.name,
            icon: DOC_ICONS[doc.fileType] || DOC_ICONS.file,
            viewLabel: `View ${doc.name}`,
            downloadLabel: `Download ${doc.name}`
        }));
    }

    get hasDocuments() {
        return this.documents.length > 0;
    }

    get showNoDocuments() {
        return !this.isLoading && !this.hasDocuments;
    }

    get showSkeleton() {
        return this.isLoading && !this.detail;
    }

    // ---------- hero slideshow ----------
    startAutoSlide() {
        const reduceMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
        if (this.autoSlideTimer || reduceMotion) {
            return;
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.autoSlideTimer = setInterval(() => {
            if (!this.heroPaused && !this.heroFocused && !this.viewerFile && this.view === 'detail' && this.hasMultipleSlides) {
                this.slideIndex = (this.slideIndex + 1) % this.slides.length;
            }
        }, AUTO_SLIDE_MS);
    }

    // Hovering the photo pauses it so the user can look at it
    handleHeroEnter() {
        this.heroPaused = true;
    }

    handleHeroLeave() {
        this.heroPaused = false;
    }

    handleHeroFocusIn() {
        this.heroFocused = true;
    }

    handleHeroFocusOut(event) {
        if (!event.currentTarget.contains(event.relatedTarget)) {
            this.heroFocused = false;
        }
    }

    handlePrevSlide() {
        const count = this.slides.length;
        this.slideIndex = (this.slideIndex - 1 + count) % count;
    }

    handleNextSlide() {
        this.slideIndex = (this.slideIndex + 1) % this.slides.length;
    }

    handleDotClick(event) {
        this.slideIndex = Number(event.currentTarget.dataset.index);
    }

    // ---------- files ----------
    findFile(id) {
        if (!this.detail || !id) {
            return null;
        }
        const priceSheets = this.detail.configurations.map((config) => config.priceSheet).filter(Boolean);
        return [...this.detail.documents, ...priceSheets].find((file) => file.id === id) || null;
    }

    get linksFresh() {
        return !!this.loadedAt && Date.now() - this.loadedAt < DIRECT_LINK_MS;
    }

    // Without a fresh direct link the viewer shows OneDrive's preview instead
    handleViewFile(event) {
        const file = this.findFile(event.currentTarget.dataset.id);
        if (file) {
            this.viewerOpener = event.currentTarget;
            this.viewerFile = this.linksFresh ? file : { ...file, mediaUrl: null };
        }
    }

    // A fresh direct link downloads the file; otherwise the OneDrive page offers the download
    handleDownloadFile(event) {
        const file = this.findFile(event.currentTarget.dataset.id);
        const url = file && ((this.linksFresh && file.mediaUrl) || file.previewUrl);
        if (url) {
            window.open(url, '_blank', 'noopener');
        }
    }

    handleCloseViewer() {
        this.viewerFile = null;
        if (this.viewerOpener) {
            this.viewerOpener.focus();
            this.viewerOpener = undefined;
        }
    }

    // ---------- navigation ----------
    handleBack() {
        this.dispatchEvent(new CustomEvent('back'));
    }

    handleViewLocation() {
        this.view = 'location';
    }

    handleBackToDetail() {
        this.view = 'detail';
    }

    handleOpenMaps() {
        const query = encodeURIComponent(this.location);
        window.open('https://www.google.com/maps/search/?api=1&query=' + query, '_blank', 'noopener');
    }
}