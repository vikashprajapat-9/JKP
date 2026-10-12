import { LightningElement, api } from 'lwc';
import getFilePreviewUrl from '@salesforce/apex/partnerWebPortalMarketingController.getFilePreviewUrl';
import getCustomerFilePreviewUrl from '@salesforce/apex/CustomerPortalProjectController.getFilePreviewUrl';

const MIN_ZOOM = 50;
const MAX_ZOOM = 200;
const ZOOM_STEP = 25;

// Full-screen viewer for one portal file. Photos and videos play from their direct link; PDFs and other documents
// open in OneDrive's embedded preview. Fires "close" when the user goes back.
export default class PartnerWebPortalFileViewer extends LightningElement {
    _file;
    // 'partner' (the default) or 'customer': the portal showing the file, which decides where its preview is read
    @api portal = 'partner';
    zoom = 100;
    previewUrl;
    previewError;
    isPreviewLoading = false;
    hasFocused = false;

    // { id, name, fileType: image | video | pdf | file, mediaUrl (direct link), previewUrl (share link) }
    @api
    get file() {
        return this._file;
    }
    set file(value) {
        const changed = !this._file || !value || this._file.id !== value.id;
        this._file = value;
        if (changed) {
            this.zoom = 100;
            this.previewUrl = undefined;
            this.previewError = undefined;
            this.isPreviewLoading = false;
            if (value && !this.playsInline) {
                this.loadPreview();
            }
        }
    }

    connectedCallback() {
        this.onKeyDown = (event) => {
            if (event.key === 'Escape') {
                this.handleClose();
            }
        };
        window.addEventListener('keydown', this.onKeyDown);
    }

    disconnectedCallback() {
        window.removeEventListener('keydown', this.onKeyDown);
    }

    // Keyboard focus moves into the viewer when it opens, so it does not stay on the page behind it
    renderedCallback() {
        if (!this.hasFocused) {
            const back = this.template.querySelector('.viewer-back');
            if (back) {
                this.hasFocused = true;
                back.focus();
            }
        }
    }

    get playsInline() {
        const file = this._file;
        return !!file && !!file.mediaUrl && (file.fileType === 'image' || file.fileType === 'video');
    }

    get isImage() {
        return this.playsInline && this._file.fileType === 'image';
    }

    get isVideo() {
        return this.playsInline && this._file.fileType === 'video';
    }

    get imageStyle() {
        return `width: ${this.zoom}%;`;
    }

    get zoomLabel() {
        return `${this.zoom}%`;
    }

    get isZoomOutDisabled() {
        return this.zoom <= MIN_ZOOM;
    }

    get isZoomInDisabled() {
        return this.zoom >= MAX_ZOOM;
    }

    get fileName() {
        return this._file ? this._file.name : '';
    }

    async loadPreview() {
        const id = this._file.id;
        this.isPreviewLoading = true;
        try {
            // The file can be set before the portal is; by the next microtask both are
            await Promise.resolve();
            const load = this.portal === 'customer' ? getCustomerFilePreviewUrl : getFilePreviewUrl;
            const url = await load({ subDocumentId: id });
            if (this._file && this._file.id === id) {
                this.previewUrl = url;
            }
        } catch (error) {
            if (this._file && this._file.id === id) {
                this.previewError = error && error.body && error.body.message ? error.body.message : 'The preview could not be loaded.';
            }
        } finally {
            if (this._file && this._file.id === id) {
                this.isPreviewLoading = false;
            }
        }
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleZoomIn() {
        this.zoom = Math.min(MAX_ZOOM, this.zoom + ZOOM_STEP);
    }

    handleZoomOut() {
        this.zoom = Math.max(MIN_ZOOM, this.zoom - ZOOM_STEP);
    }

    // The direct link downloads the file; without it the OneDrive page offers the download
    handleDownload() {
        const url = this._file && (this._file.mediaUrl || this._file.previewUrl);
        if (url) {
            window.open(url, '_blank', 'noopener');
        }
    }

    handleOpenInOneDrive() {
        if (this._file && this._file.previewUrl) {
            window.open(this._file.previewUrl, '_blank', 'noopener');
        }
    }
}