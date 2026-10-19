import { LightningElement, api } from 'lwc';
import LOCALE from '@salesforce/i18n/locale';
import LANG from '@salesforce/i18n/lang';
import CURRENCY from '@salesforce/i18n/currency';
import getProjectDetails from '@salesforce/apex/partnerWebPortalMarketingController.getProjectDetails';
import getCustomerProjectDetails from '@salesforce/apex/CustomerPortalController.getProjectDetails';
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

// Customer Portal (portal="customer"): its own markup and text, Figma p18 (and the viewer of p19)
const CUSTOMER_TEXT = {
    back: 'Back to projects',
    backToProject: 'Back to the project',
    brochure: 'Download Brochure',
    viewLocation: 'View Location',
    openMaps: 'Open in Google Maps',
    noAddress: 'No address is available for this project yet.',
    price: 'Price',
    onwards: 'Onwards',
    onRequest: 'On request',
    possession: 'Possession Date',
    landParcel: 'Land Parcel',
    type: 'Type',
    availability: 'Availability',
    area: 'Area',
    amenities: 'Amenities',
    configurations: 'Configurations',
    documents: 'Project Documents',
    startingPrice: 'Starting Price',
    priceSheet: 'Price Sheet',
    serial: 'Sr.',
    document: 'Document',
    action: 'Action',
    view: 'View',
    download: 'Download',
    sheetSoon: 'Coming soon',
    noConfigurations: 'Configurations will be listed here soon.',
    noDocuments: 'No project documents have been shared yet.',
    previousPhoto: 'Previous photo',
    nextPhoto: 'Next photo',
    viewPhoto: 'View photo'
};
// View and download buttons of the Customer Portal's tables (Figma p47 action icons, 24px, white on a 24px square)
const ACTION_ICONS = {
    view: 'M19.95 11.28C19.93 11.22 19.37 9.93 18.11 8.64C16.44 6.91 14.33 6 12 6C9.67 6 7.56 6.91 5.89 8.64C4.63 9.93 4.07 11.23 4.05 11.28C4.02 11.35 4 11.42 4 11.5C4 11.58 4.02 11.65 4.05 11.72C4.07 11.78 4.63 13.07 5.89 14.36C7.56 16.09 9.67 17 12 17C14.33 17 16.44 16.09 18.11 14.36C19.37 13.07 19.93 11.78 19.95 11.72C19.98 11.65 20 11.58 20 11.5C20 11.42 19.98 11.35 19.95 11.28ZM12 15.9C9.95 15.9 8.16 15.13 6.67 13.61C6.06 12.99 5.54 12.28 5.13 11.5C5.54 10.72 6.06 10.01 6.67 9.39C8.16 7.87 9.95 7.1 12 7.1C14.05 7.1 15.84 7.87 17.33 9.39C17.94 10.01 18.46 10.72 18.87 11.5C18.39 12.43 16.3 15.9 12 15.9ZM12 8.2C11.37 8.2 10.75 8.39 10.22 8.76C9.7 9.12 9.29 9.63 9.04 10.24C8.8 10.84 8.74 11.5 8.86 12.14C8.98 12.78 9.29 13.37 9.74 13.83C10.18 14.29 10.76 14.61 11.38 14.74C12 14.86 12.64 14.8 13.22 14.55C13.81 14.3 14.31 13.88 14.66 13.33C15.01 12.79 15.2 12.15 15.2 11.5C15.2 10.63 14.86 9.79 14.26 9.17C13.66 8.55 12.85 8.2 12 8.2ZM12 13.7C11.58 13.7 11.17 13.57 10.81 13.33C10.46 13.09 10.19 12.74 10.03 12.34C9.87 11.94 9.83 11.5 9.91 11.07C9.99 10.64 10.19 10.25 10.49 9.94C10.79 9.64 11.17 9.43 11.58 9.34C12 9.26 12.43 9.3 12.82 9.47C13.21 9.63 13.54 9.92 13.77 10.28C14.01 10.64 14.13 11.06 14.13 11.5C14.13 12.08 13.91 12.64 13.51 13.06C13.11 13.47 12.57 13.7 12 13.7Z',
    download: 'M19 13.75L19 17.83C19 18.14 18.88 18.44 18.66 18.66C18.44 18.88 18.14 19 17.83 19L6.17 19C5.86 19 5.56 18.88 5.34 18.66C5.12 18.44 5 18.14 5 17.83L5 13.75C5 13.6 5.06 13.45 5.17 13.34C5.28 13.23 5.43 13.17 5.58 13.17C5.74 13.17 5.89 13.23 6 13.34C6.11 13.45 6.17 13.6 6.17 13.75L6.17 17.83L17.83 17.83L17.83 13.75C17.83 13.6 17.89 13.45 18 13.34C18.11 13.23 18.26 13.17 18.42 13.17C18.57 13.17 18.72 13.23 18.83 13.34C18.94 13.45 19 13.6 19 13.75ZM11.59 14.16C11.64 14.22 11.71 14.26 11.78 14.29C11.85 14.32 11.92 14.33 12 14.33C12.08 14.33 12.15 14.32 12.22 14.29C12.29 14.26 12.36 14.22 12.41 14.16L15.33 11.25C15.38 11.19 15.43 11.13 15.46 11.06C15.49 10.99 15.5 10.91 15.5 10.83C15.5 10.76 15.49 10.68 15.46 10.61C15.43 10.54 15.38 10.47 15.33 10.42C15.28 10.37 15.21 10.32 15.14 10.29C15.07 10.26 14.99 10.25 14.92 10.25C14.84 10.25 14.76 10.26 14.69 10.29C14.62 10.32 14.56 10.37 14.5 10.42L12.58 12.34L12.58 5.58C12.58 5.43 12.52 5.28 12.41 5.17C12.3 5.06 12.15 5 12 5C11.85 5 11.7 5.06 11.59 5.17C11.48 5.28 11.42 5.43 11.42 5.58L11.42 12.34L9.5 10.42C9.39 10.31 9.24 10.25 9.08 10.25C8.93 10.25 8.78 10.31 8.67 10.42C8.56 10.53 8.5 10.68 8.5 10.83C8.5 10.99 8.56 11.14 8.67 11.25L11.59 14.16Z'
};
// The file the "Download Brochure" button opens: the first project document with this in its name
const BROCHURE_NAME = /brochure/i;
// The Customer Portal writes its months and numbers in the user's language, like its English text ("July 2026"): the
// user's locale can be ta_LK (the customer login has it), which would print the month in Tamil
const CUSTOMER_LOCALE = LANG || 'en-US';
// Figma p18 lays the spec cells out four to a row
const SPEC_COLUMNS = 4;

const isBlank = (value) => value === null || value === undefined || value === '';

// The short price form the design uses: "LKR 1.64 Cr", "LKR 45 L". Cut to two decimals, never rounded up, so a
// "starting at" price is never shown higher than it is (99,99,999 is "99.99 L", not "100 L").
function formatPrice(value, locale = LOCALE) {
    const amount = Number(value);
    const code = CURRENCY || '';
    if (amount >= 1e7) {
        return `${code} ${Math.floor(amount / 1e5) / 100} Cr`.trim();
    }
    if (amount >= 1e5) {
        return `${code} ${Math.floor(amount / 1e3) / 100} L`.trim();
    }
    return `${code} ${amount.toLocaleString(locale)}`.trim();
}

// The same amount without the currency, as the Customer Portal writes it under the currency label: "1.43 Cr."
function formatShortAmount(value) {
    const amount = Number(value);
    if (amount >= 1e7) {
        return `${Math.floor(amount / 1e5) / 100} Cr.`;
    }
    if (amount >= 1e5) {
        return `${Math.floor(amount / 1e3) / 100} L.`;
    }
    return amount.toLocaleString(CUSTOMER_LOCALE);
}

function formatArea(value) {
    return `${Number(value).toLocaleString(LOCALE)} sq.ft`;
}

// Customer Portal: "900 sq ft." (Figma p18)
function formatCustomerArea(value) {
    return `${Number(value).toLocaleString(CUSTOMER_LOCALE)} sq ft.`;
}

// Possession is a date ("Jul 2026"; the Customer Portal writes "July 2026"); plain text is shown as it is
function formatPossession(value, month = 'short', locale = LOCALE) {
    if (isBlank(value)) {
        return '';
    }
    const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(value));
    if (!match) {
        return String(value);
    }
    const date = new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])));
    try {
        return new Intl.DateTimeFormat(locale, { month, year: 'numeric', timeZone: 'UTC' }).format(date);
    } catch (e) {
        return String(value);
    }
}

// "2 BR", "3 BR", "4 BR" -> "2, 3 & 4 BR" (the design's "3 & 4 BHK"); other names are listed as they are
function joinUnitTypes(types) {
    const names = [...new Set((types || []).filter(Boolean).map((t) => String(t).trim()))];
    if (names.length < 2) {
        return names.join('');
    }
    const parts = names.map((n) => /^(\S+)\s+(.+)$/.exec(n));
    const suffix = parts[0] && parts[0][2];
    const list = parts.every((p) => p && p[2] === suffix) ? parts.map((p) => p[1]) : names;
    const text = list.slice(0, -1).join(', ') + ' & ' + list[list.length - 1];
    return list === names ? text : `${text} ${suffix}`;
}

export default class PartnerWebPortalProjectDetail extends LightningElement {

    // { id, name, location, image, initial } from the project list
    @api project = {};
    // 'partner' (the default) or 'customer': the portal showing the page, which decides where the details are read;
    // the customer gets the Customer Portal's own markup and look (the partner markup is left as it is)
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
    // The file open in the viewer, and the button that opened it (focus returns there)
    viewerFile = null;
    viewerOpener;
    customerText = CUSTOMER_TEXT;
    actionIcons = ACTION_ICONS;

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
            this.slideIndex = 0;
        } catch (error) {
            this.loadError = error && error.body && error.body.message ? error.body.message : 'The project details could not be loaded.';
        } finally {
            this.isLoading = false;
        }
    }

    get isCustomer() {
        return this.portal === 'customer';
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
            // The Customer Portal's own class names
            custSlideClass: index === active ? 'cpd-slide cpd-slide_active' : 'cpd-slide',
            custDotClass: index === active ? 'cpd-dot cpd-dot_active' : 'cpd-dot',
            // Customer Portal: a project photo opens at full size (Figma p20); only the photo on show takes focus
            canOpen: Boolean(this.detail),
            custTabIndex: index === active ? '0' : '-1',
            openLabel: `${CUSTOMER_TEXT.viewPhoto} ${index + 1} of ${slides.length}`,
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
                custArea: isBlank(config.squareFt) ? '—' : formatCustomerArea(config.squareFt),
                price: isBlank(config.startingPrice) ? 'On request' : formatPrice(config.startingPrice),
                custPrice: isBlank(config.startingPrice) ? CUSTOMER_TEXT.onRequest : formatPrice(config.startingPrice, CUSTOMER_LOCALE),
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
        return (this.detail ? this.detail.documents : []).map((doc, index) => ({
            key: doc.id,
            id: doc.id,
            serial: index + 1,
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

    // ---------- Customer Portal: facts row, spec cells, brochure (Figma p18) ----------
    // "LKR" over "1.43 Cr. Onwards": the lowest starting price of the configurations
    get custPriceLabel() {
        return CURRENCY || CUSTOMER_TEXT.price;
    }

    get custPriceText() {
        if (!this.detail) {
            return this.isLoading ? '…' : '—';
        }
        const prices = this.detail.configurations.map((c) => c.startingPrice).filter((p) => !isBlank(p)).map(Number);
        return prices.length ? `${formatShortAmount(Math.min(...prices))} ${CUSTOMER_TEXT.onwards}` : CUSTOMER_TEXT.onRequest;
    }

    get custPossessionText() {
        if (!this.detail) {
            return this.isLoading ? '…' : '—';
        }
        return formatPossession(this.detail.possession, 'long', CUSTOMER_LOCALE) || '—';
    }

    // The bordered cells under the facts: unit types, Project Status, area (a range over the configurations)
    get custSpecs() {
        if (!this.detail) {
            return [];
        }
        const configs = this.detail.configurations;
        const areas = configs.map((c) => c.squareFt).filter((v) => !isBlank(v)).map(Number);
        let area = '';
        if (areas.length) {
            const min = Math.min(...areas);
            const max = Math.max(...areas);
            area = min === max
                ? formatCustomerArea(min)
                : `${min.toLocaleString(CUSTOMER_LOCALE)} – ${formatCustomerArea(max)}`;
        }
        return [
            { key: 'type', label: CUSTOMER_TEXT.type, value: joinUnitTypes(configs.map((c) => c.unitType)) },
            { key: 'availability', label: CUSTOMER_TEXT.availability, value: this.detail.status },
            { key: 'area', label: CUSTOMER_TEXT.area, value: area }
        ].filter((spec) => !isBlank(spec.value));
    }

    get hasCustSpecs() {
        return this.custSpecs.length > 0;
    }

    // Cells keep Figma's width (a quarter of the page) and fill the row from the left, as Figma's second row does
    get custSpecsStyle() {
        return `--cpd-spec-cols: ${Math.min(this.custSpecs.length, SPEC_COLUMNS)};`;
    }

    get custBrochure() {
        const docs = this.detail ? this.detail.documents : [];
        return docs.find((doc) => BROCHURE_NAME.test(doc.name || '')) || null;
    }

    get hasBrochure() {
        return Boolean(this.custBrochure);
    }

    get hasTitleActions() {
        return this.hasAddress || this.hasBrochure;
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

    // Photos show in the viewer from their direct link; documents show there as a card to open or download
    handleViewFile(event) {
        const file = this.findFile(event.currentTarget.dataset.id);
        if (file) {
            this.viewerOpener = event.currentTarget;
            this.viewerFile = file;
        }
    }

    // Customer Portal: the photo on show opens in the viewer at full size (Figma p20), with its zoom and download
    handleOpenPhoto(event) {
        const photos = this.detail ? this.detail.images.filter((image) => image.mediaUrl) : [];
        const photo = photos[Number(event.currentTarget.dataset.index)];
        if (photo) {
            this.viewerOpener = event.currentTarget;
            this.viewerFile = photo;
        }
    }

    // Customer Portal: "Download Brochure" opens the brochure in the viewer (Figma p19), which also downloads it
    handleOpenBrochure(event) {
        const brochure = this.custBrochure;
        if (brochure) {
            this.viewerOpener = event.currentTarget;
            this.viewerFile = brochure;
        }
    }

    // The direct link downloads the file; without it the SharePoint page offers the download
    handleDownloadFile(event) {
        const file = this.findFile(event.currentTarget.dataset.id);
        const url = file && (file.mediaUrl || file.previewUrl);
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