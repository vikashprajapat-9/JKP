import { LightningElement, api } from 'lwc';

// SAMPLE DATA from the Figma (p73). No marketing files are stored against
// projects yet. Replace with Apex data (e.g. ContentDocuments) later; keep the shape.
const SAMPLE_RESOURCES = [
    { id: 'r1', title: 'Real Estate Marketing Strategies', kind: 'video', fileName: 'Real_Estate_Marketing_Strategies.mp4', pages: 1, theme: 'thumb thumb-blueprint' },
    { id: 'r2', title: 'Marketing Documentary', kind: 'pdf', fileName: 'Marketing_Documentary.pdf', pages: 2, theme: 'thumb thumb-blueprint' },
    { id: 'r3', title: 'Eco-Friendly Home', kind: 'pdf', fileName: 'Eco_Friendly_Home.pdf', pages: 2, theme: 'thumb thumb-green' }
];

const MIN_ZOOM = 50;
const MAX_ZOOM = 200;
const ZOOM_STEP = 25;

export default class PartnerWebPortalMarketingDetail extends LightningElement {

    // { id, name }
    @api project = {};

    resources = SAMPLE_RESOURCES.map(r => ({
        ...r,
        isVideo: r.kind === 'video',
        viewLabel: 'View ' + r.title
    }));

    openResource = null;
    zoom = 100;

    get hasResources() {
        return this.resources.length > 0;
    }

    get isViewerOpen() {
        return this.openResource !== null;
    }

    get viewerIsVideo() {
        return this.openResource && this.openResource.isVideo;
    }

    get showDocTools() {
        return this.openResource && !this.openResource.isVideo;
    }

    get pageList() {
        if (!this.openResource) return [];
        const pages = [];
        for (let i = 1; i <= this.openResource.pages; i++) {
            pages.push({ key: 'p' + i, number: i, isFirst: i === 1 });
        }
        return pages;
    }

    get pageCounter() {
        return this.openResource ? `1/${this.openResource.pages}` : '';
    }

    get pageStyle() {
        return `width: ${Math.round(420 * this.zoom / 100)}px; height: ${Math.round(594 * this.zoom / 100)}px;`;
    }

    get isZoomOutDisabled() {
        return this.zoom <= MIN_ZOOM;
    }

    get isZoomInDisabled() {
        return this.zoom >= MAX_ZOOM;
    }

    connectedCallback() {
        this._onKeyDown = this.handleKeyDown.bind(this);
        window.addEventListener('keydown', this._onKeyDown);
    }

    disconnectedCallback() {
        window.removeEventListener('keydown', this._onKeyDown);
    }

    handleBack() {
        this.dispatchEvent(new CustomEvent('back'));
    }

    handleView(event) {
        const id = event.currentTarget.dataset.id;
        this.openResource = this.resources.find(r => r.id === id) || null;
        this.zoom = 100;
    }

    handleCloseViewer() {
        this.openResource = null;
    }

    handleZoomIn() {
        this.zoom = Math.min(MAX_ZOOM, this.zoom + ZOOM_STEP);
    }

    handleZoomOut() {
        this.zoom = Math.max(MIN_ZOOM, this.zoom - ZOOM_STEP);
    }

    handleKeyDown(event) {
        if (event.key === 'Escape' && this.isViewerOpen) this.handleCloseViewer();
    }
}