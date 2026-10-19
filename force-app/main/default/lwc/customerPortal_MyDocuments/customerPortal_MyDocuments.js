import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getMyDocumentsPageData from '@salesforce/apex/CustomerPortalController.getMyDocumentsPageData';
import CP_ASSETS from '@salesforce/resourceUrl/customerPortalAssets';
import { ICONS } from './icons';

const VIEW_LIST = 'LIST';
const VIEW_DETAIL = 'DETAIL';
const DEFAULT_CATEGORY_KEY = 'myDocuments';

// Viewer (Figma p65): the page is 418px wide at 100%; the zoom buttons step its width.
const ZOOM_STEPS = [0.75, 1, 1.25, 1.5, 1.75, 2, 2.5];
const ZOOM_DEFAULT_INDEX = 1;
const PAGE_WIDTH_PX = 418;
const IMAGE_PATH = /\.(png|jpe?g|gif|webp|bmp|svg)$/i;
const PDF_PATH = /\.pdf$/i;
// Hides the browser's own PDF toolbar (the viewer bar replaces it) and fits the page to the width.
const PDF_VIEW_PARAMS = '#toolbar=0&navpanes=0&view=FitH';

// Visible text (plain constants, no Custom Labels)
const LABELS = {
    loading: 'Loading documents',
    loadError: "We couldn't load your documents right now. Please try again in a moment.",
    toastTitle: 'Error',
    loadErrorToast: 'Unable to load documents. Please try again.',
    openErrorToast: 'Unable to open this document.',
    downloadErrorToast: 'Unable to download this document. Please try again.',
    noProjects: 'No documents available yet.',
    noDocuments: 'No documents available in this category yet.',
    viewDetails: 'View Details',
    previousImage: 'Previous image',
    nextImage: 'Next image',
    back: 'Back',
    backToList: 'Back to documents',
    categories: 'Document categories',
    preview: 'Preview',
    download: 'Download',
    zoomOut: 'Zoom out',
    zoomIn: 'Zoom in',
    documentPreview: 'Document preview'
};

export default class CustomerPortal_MyDocuments extends LightningElement {
    labels = LABELS;
    icons = ICONS;
    emptyImageUrl = CP_ASSETS + '/empty-state.svg';

    pageData;
    isLoading = true;
    hasError = false;

    view = VIEW_LIST;
    selectedProjectId;
    activeCategoryKey = DEFAULT_CATEGORY_KEY;

    imageIndexById = {};

    isPreviewOpen = false;
    previewDocUrl;
    previewDocName;
    zoomIndex = ZOOM_DEFAULT_INDEX;
    focusViewerOnRender = false;
    previewOpenerId;
    focusOpenerOnRender = false;

    connectedCallback() {
        this.loadDocuments();
    }

    disconnectedCallback() {
        this.removeViewerKeyListener();
    }

    // Focus moves into the viewer when it opens and back to the eye button when it closes
    renderedCallback() {
        if (this.focusViewerOnRender && this.isPreviewOpen) {
            this.focusViewerOnRender = false;
            const back = this.template.querySelector('.docs-viewer__back');
            if (back) {
                back.focus();
            }
        } else if (this.focusOpenerOnRender && !this.isPreviewOpen) {
            this.focusOpenerOnRender = false;
            const opener = this.template.querySelector('.docs-action[data-id="' + this.previewOpenerId + '"]');
            if (opener) {
                opener.focus();
            }
        }
    }

    async loadDocuments() {
        this.isLoading = true;
        this.hasError = false;

        try {
            this.pageData = await getMyDocumentsPageData();
            const indexMap = {};
            (this.pageData.projects || []).forEach((p) => {
                indexMap[p.id] = 0;
            });
            this.imageIndexById = indexMap;
        } catch (error) {
            this.hasError = true;
            console.error('customerPortal_MyDocuments: failed to load documents', error);
            this.showErrorToast(LABELS.loadErrorToast);
        } finally {
            this.isLoading = false;
        }
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

    // ---------- page ----------
    get pageTitle() {
        return this.pageData ? this.pageData.title : '';
    }

    get pageDescription() {
        return this.pageData ? this.pageData.description : '';
    }

    get showContent() {
        return !this.isLoading && !this.hasError;
    }

    get showListView() {
        return this.showContent && this.view === VIEW_LIST;
    }

    get showDetailView() {
        return this.showContent && this.view === VIEW_DETAIL && !!this.selectedProject;
    }

    get rawProjects() {
        return this.pageData ? this.pageData.projects || [] : [];
    }

    get hasProjects() {
        return this.rawProjects.length > 0;
    }

    get selectedProject() {
        return this.rawProjects.find((p) => p.id === this.selectedProjectId) || null;
    }

    // ---------- list view (Figma p49) ----------
    get displayedProjects() {
        return this.rawProjects.map((project) => this.decorateProjectCard(project));
    }

    decorateProjectCard(project) {
        const images = project.images || [];
        const activeIndex = this.imageIndexById[project.id] || 0;
        const activeImageUrl = images.length ? images[activeIndex % images.length].url : '';

        const dots = images.map((img, idx) => {
            return {
                key: project.id + '-dot-' + idx,
                dotClass: idx === activeIndex ? 'cp-dot cp-dot_active' : 'cp-dot'
            };
        });

        return {
            id: project.id,
            name: project.name,
            shortAddress: project.address,
            activeImageUrl,
            showArrows: images.length > 1,
            showDots: images.length > 1,
            dots
        };
    }

    handleCardPrevImage(event) {
        this.stepImage(event.currentTarget.dataset.id, -1);
    }

    handleCardNextImage(event) {
        this.stepImage(event.currentTarget.dataset.id, 1);
    }

    stepImage(projectId, direction) {
        const project = this.rawProjects.find((p) => p.id === projectId);
        if (!project || !project.images || project.images.length < 2) {
            return;
        }
        const count = project.images.length;
        const current = this.imageIndexById[projectId] || 0;
        const next = (current + direction + count) % count;
        this.imageIndexById = {
            ...this.imageIndexById,
            [projectId]: next
        };
    }

    handleViewDetails(event) {
        this.selectedProjectId = event.currentTarget.dataset.id;
        this.activeCategoryKey = this.initialCategoryKey(this.selectedProject);
        this.view = VIEW_DETAIL;
    }

    // 'My Documents' first, as before; falls back to the first category when a project has no such key
    initialCategoryKey(project) {
        const categories = project && project.documentCategories ? project.documentCategories : [];
        if (!categories.length || categories.some((c) => c.key === DEFAULT_CATEGORY_KEY)) {
            return DEFAULT_CATEGORY_KEY;
        }
        return categories[0].key;
    }

    handleBack() {
        this.view = VIEW_LIST;
        this.selectedProjectId = undefined;
    }

    // ---------- detail view (Figma p50-52) ----------
    get categoryTabs() {
        const project = this.selectedProject;
        if (!project || !project.documentCategories) {
            return [];
        }
        return project.documentCategories.map((cat) => {
            const isActive = cat.key === this.activeCategoryKey;
            return {
                key: cat.key,
                label: cat.label,
                tabClass: isActive ? 'cp-tab cp-tab_active' : 'cp-tab',
                ariaSelected: isActive ? 'true' : 'false',
                tabIndex: isActive ? '0' : '-1'
            };
        });
    }

    get activeCategoryRaw() {
        const project = this.selectedProject;
        if (!project || !project.documentCategories) {
            return null;
        }
        return project.documentCategories.find((c) => c.key === this.activeCategoryKey) || null;
    }

    get activeDocuments() {
        const category = this.activeCategoryRaw;
        return category ? category.documents || [] : [];
    }

    get hasActiveDocuments() {
        return this.activeDocuments.length > 0;
    }

    handleTabClick(event) {
        this.activeCategoryKey = event.currentTarget.dataset.key;
    }

    // Arrow keys move between the tabs (tablist pattern)
    handleTabKeydown(event) {
        const keys = { ArrowRight: 1, ArrowLeft: -1 };
        if (!(event.key in keys)) {
            return;
        }
        const tabs = this.categoryTabs;
        const current = tabs.findIndex((t) => t.key === this.activeCategoryKey);
        if (current < 0 || tabs.length < 2) {
            return;
        }
        event.preventDefault();
        const next = (current + keys[event.key] + tabs.length) % tabs.length;
        this.activeCategoryKey = tabs[next].key;
        const buttons = this.template.querySelectorAll('.docs-tabs .cp-tab');
        if (buttons[next]) {
            buttons[next].focus();
        }
    }

    findDocumentById(docId) {
        return this.activeDocuments.find((d) => d.id === docId) || null;
    }

    // ---------- preview (viewer, Figma p65 / p55) ----------
    handlePreview(event) {
        const docId = event.currentTarget.dataset.id;
        const doc = this.findDocumentById(docId);

        if (!doc || !doc.documentUrl) {
            this.showErrorToast(LABELS.openErrorToast);
            return;
        }

        this.previewDocUrl = doc.documentUrl;
        this.previewDocName = doc.name;
        this.previewOpenerId = docId;
        this.zoomIndex = ZOOM_DEFAULT_INDEX;
        this.isPreviewOpen = true;
        this.focusViewerOnRender = true;
        this.addViewerKeyListener();
    }

    handleClosePreview() {
        this.isPreviewOpen = false;
        this.previewDocUrl = undefined;
        this.previewDocName = undefined;
        this.focusOpenerOnRender = true;
        this.removeViewerKeyListener();
    }

    stopPropagation(event) {
        event.stopPropagation();
    }

    addViewerKeyListener() {
        if (!this.viewerKeyHandler) {
            this.viewerKeyHandler = (event) => {
                if (event.key === 'Escape' && this.isPreviewOpen) {
                    this.handleClosePreview();
                }
            };
            window.addEventListener('keydown', this.viewerKeyHandler);
        }
    }

    removeViewerKeyListener() {
        if (this.viewerKeyHandler) {
            window.removeEventListener('keydown', this.viewerKeyHandler);
            this.viewerKeyHandler = undefined;
        }
    }

    get previewPath() {
        return (this.previewDocUrl || '').split('#')[0].split('?')[0];
    }

    get previewIsImage() {
        return IMAGE_PATH.test(this.previewPath);
    }

    get previewFrameUrl() {
        const url = this.previewDocUrl || '';
        return PDF_PATH.test(this.previewPath) && url.indexOf('#') === -1 ? url + PDF_VIEW_PARAMS : url;
    }

    get zoomLevel() {
        return ZOOM_STEPS[this.zoomIndex];
    }

    get zoomLabel() {
        return Math.round(this.zoomLevel * 100) + '%';
    }

    get isZoomOutDisabled() {
        return this.zoomIndex <= 0;
    }

    get isZoomInDisabled() {
        return this.zoomIndex >= ZOOM_STEPS.length - 1;
    }

    get viewerPageClass() {
        return this.previewIsImage ? 'docs-viewer__page docs-viewer__page_image' : 'docs-viewer__page';
    }

    // 418px (or the screen width on phones) times the zoom
    get viewerPageStyle() {
        return '--docs-page-width: calc(min(' + PAGE_WIDTH_PX + 'px, 100vw - 32px) * ' + this.zoomLevel + ');';
    }

    handleZoomOut() {
        if (!this.isZoomOutDisabled) {
            this.zoomIndex -= 1;
        }
    }

    handleZoomIn() {
        if (!this.isZoomInDisabled) {
            this.zoomIndex += 1;
        }
    }

    // ---------- download (unchanged) ----------
    async handleDownload(event) {
        const docId = event.currentTarget.dataset.id;
        const doc = this.findDocumentById(docId);

        if (!doc || !doc.documentUrl) {
            this.showErrorToast(LABELS.openErrorToast);
            return;
        }

        try {
            const response = await fetch(doc.documentUrl);
            if (!response.ok) {
                throw new Error('Request failed with status ' + response.status);
            }
            const blob = await response.blob();
            const blobUrl = window.URL.createObjectURL(blob);

            const link = document.createElement('a');
            link.href = blobUrl;
            link.download = this.buildDownloadFileName(doc);
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);

            window.URL.revokeObjectURL(blobUrl);
        } catch (error) {
            console.error('customerPortal_MyDocuments: failed to download document', error);
            this.showErrorToast(LABELS.downloadErrorToast);
        }
    }

    buildDownloadFileName(doc) {
        const urlParts = (doc.documentUrl || '').split('?')[0].split('/');
        const lastSegment = urlParts[urlParts.length - 1];
        const hasExtension = lastSegment && lastSegment.includes('.');
        return hasExtension ? lastSegment : (doc.name || 'document') + '.pdf';
    }
}