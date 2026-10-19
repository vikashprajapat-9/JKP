import { LightningElement, api } from 'lwc';
import getMarketingFiles from '@salesforce/apex/partnerWebPortalMarketingController.getMarketingFiles';

// A project's Marketing folder as cards. A card opens the portal's file viewer (c-partner-web-portal-file-viewer):
// photos and videos from their direct link, documents as a card to open in a new tab or download.
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
    // The file open in the viewer, and the card that opened it (focus returns there)
    openResource = null;
    viewerOpener;

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

    handleBack() {
        this.dispatchEvent(new CustomEvent('back'));
    }

    handleView(event) {
        const resource = this.resources.find((r) => r.id === event.currentTarget.dataset.id);
        if (resource) {
            this.viewerOpener = event.currentTarget;
            this.openResource = resource;
        }
    }

    handleCardKey(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleView(event);
        }
    }

    // The viewer closes with its Back button or Escape
    handleCloseViewer() {
        this.openResource = null;
        if (this.viewerOpener) {
            this.viewerOpener.focus();
            this.viewerOpener = undefined;
        }
    }
}