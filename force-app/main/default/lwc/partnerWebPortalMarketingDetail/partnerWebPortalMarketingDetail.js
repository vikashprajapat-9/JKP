import { LightningElement, api } from 'lwc';
import getMarketingFiles from '@salesforce/apex/partnerWebPortalMarketingController.getMarketingFiles';
import getFilePreviewUrl from '@salesforce/apex/partnerWebPortalMarketingController.getFilePreviewUrl';

const MIN_ZOOM = 50;
const MAX_ZOOM = 200;
const ZOOM_STEP = 25;

export default class PartnerWebPortalMarketingDetail extends LightningElement {
    _project = {};

    // { id, name } of the project whose "Marketing" folder is shown
    @api
    get project() {
        return this._project;
    }
    set project(value) {
        const changed = (value && value.id) !== (this._project && this._project.id);
        this._project = value || {};
        if (changed && this._project.id) {
            this.loadFiles();
        }
    }

    resources = [];
    isLoading = true;
    error;
    openResource = null;
    zoom = 100;
    previewUrl;
    previewError;
    isPreviewLoading = false;

    async loadFiles() {
        this.isLoading = true;
        this.error = undefined;
        try {
            const files = await getMarketingFiles({ projectId: this._project.id });
            this.resources = files.map((file) => {
                const isImage = file.fileType === 'image';
                const isVideo = file.fileType === 'video';
                const isPdf = file.fileType === 'pdf';
                return {
                    ...file,
                    title: file.name,
                    isImage,
                    isVideo,
                    isPdf,
                    showImageThumb: isImage && !!file.mediaUrl,
                    showVideoThumb: isVideo && !!file.mediaUrl,
                    showArtwork: !((isImage || isVideo) && file.mediaUrl),
                    showFileBadge: !isImage && !isVideo,
                    badgeLabel: isPdf ? 'PDF' : (file.name.split('.').pop() || 'FILE').toUpperCase(),
                    theme: isImage ? 'thumb thumb-green' : 'thumb thumb-blueprint',
                    viewLabel: `View ${file.name}`
                };
            });
        } catch (error) {
            this.error = error && error.body && error.body.message ? error.body.message : 'Could not load the marketing files.';
            this.resources = [];
        } finally {
            this.isLoading = false;
        }
    }

    get hasResources() {
        return !this.isLoading && this.resources.length > 0;
    }

    get showEmpty() {
        return !this.isLoading && !this.error && this.resources.length === 0;
    }

    get isViewerOpen() {
        return this.openResource !== null;
    }

    get viewerIsVideo() {
        return this.openResource && this.openResource.isVideo;
    }

    get viewerIsImage() {
        return this.openResource && this.openResource.isImage;
    }

    get showZoomTools() {
        return this.openResource && this.openResource.isImage;
    }

    get zoomLabel() {
        return `${this.zoom}%`;
    }

    get imageStyle() {
        return `width: ${this.zoom}%;`;
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
        const resource = this.resources.find((r) => r.id === event.currentTarget.dataset.id);
        if (!resource) {
            return;
        }
        this.zoom = 100;
        if ((resource.isImage || resource.isVideo) && resource.mediaUrl) {
            this.openResource = resource;
        } else {
            // PDFs and other documents are shown in an embedded OneDrive preview inside the same popup
            this.openDocument(resource);
        }
    }

    handleCardKey(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleView(event);
        }
    }

    async openDocument(resource) {
        this.openResource = resource;
        this.previewUrl = undefined;
        this.previewError = undefined;
        this.isPreviewLoading = true;
        try {
            this.previewUrl = await getFilePreviewUrl({ subDocumentId: resource.id });
        } catch (error) {
            this.previewError = error && error.body && error.body.message ? error.body.message : 'The preview could not be loaded.';
        } finally {
            this.isPreviewLoading = false;
        }
    }

    handleOpenInOneDrive() {
        if (this.openResource) {
            window.open(this.openResource.previewUrl, '_blank', 'noopener');
        }
    }

    handleCloseViewer() {
        this.openResource = null;
        this.previewUrl = undefined;
        this.previewError = undefined;
    }

    handleZoomIn() {
        this.zoom = Math.min(MAX_ZOOM, this.zoom + ZOOM_STEP);
    }

    handleZoomOut() {
        this.zoom = Math.max(MIN_ZOOM, this.zoom - ZOOM_STEP);
    }

    handleKeyDown(event) {
        if (event.key === 'Escape' && this.isViewerOpen) {
            this.handleCloseViewer();
        }
    }
}