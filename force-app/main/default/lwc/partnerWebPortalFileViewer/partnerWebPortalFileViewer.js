import { LightningElement, api } from 'lwc';

const MIN_ZOOM = 50;
const MAX_ZOOM = 200;
const ZOOM_STEP = 25;
// Customer Portal: width of a photo at 100% (the Figma p20 frame)
const CUSTOMER_PHOTO_WIDTH = 960;

// Full-screen viewer for one portal file. Photos and videos show from their direct link (mediaUrl). PDFs and other
// documents show as a card: Open shows the SharePoint link (previewUrl) in a new tab, Download saves the direct link.
// Both links come with the file (from its Sub Document), so the viewer calls no Apex. Fires "close" on Back or Escape.
export default class PartnerWebPortalFileViewer extends LightningElement {
    _file;
    zoom = 100;
    // The photo or video could not be shown from its direct link (not shared with this user, or a format the browser
    // cannot play): the viewer then shows the document card, so the file can still be opened or downloaded
    mediaFailed = false;
    hasFocused = false;

    // 'partner' (the default) or 'customer': the Customer Portal gets its own sizes (Figma p19), the partner look stays
    @api portal = 'partner';

    get viewerClass() {
        return this.portal === 'customer' ? 'viewer viewer_customer' : 'viewer';
    }

    // { id, name, fileType: image | video | pdf | file, mediaUrl (direct link), previewUrl (SharePoint link) }
    @api
    get file() {
        return this._file;
    }
    set file(value) {
        const changed = !this._file || !value || this._file.id !== value.id;
        this._file = value;
        if (changed) {
            this.zoom = 100;
            this.mediaFailed = false;
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
        return !!file && !!file.mediaUrl && !this.mediaFailed && (file.fileType === 'image' || file.fileType === 'video');
    }

    get isImage() {
        return this.playsInline && this._file.fileType === 'image';
    }

    get isVideo() {
        return this.playsInline && this._file.fileType === 'video';
    }

    get imageStyle() {
        // Customer Portal: at 100% the photo is Figma p20's 960px wide (never wider than the screen), so it shows whole
        if (this.portal === 'customer') {
            return `width: min(${this.zoom}%, ${this.zoom * CUSTOMER_PHOTO_WIDTH / 100}px);`;
        }
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
        return (this._file && this._file.name) || '';
    }

    // ---------- document card ----------
    // The file's extension on the card's icon ("PDF", "DOCX"); "FILE" when the name has none
    get typeTag() {
        const match = /\.([a-z0-9]{1,5})$/i.exec(this.fileName);
        return match ? match[1].toUpperCase() : 'FILE';
    }

    get openUrl() {
        return this._file ? this._file.previewUrl : undefined;
    }

    // The direct link downloads the file; without it the SharePoint page offers the download
    get downloadUrl() {
        return this._file ? this._file.mediaUrl || this._file.previewUrl : undefined;
    }

    get isOpenDisabled() {
        return !this.openUrl;
    }

    get isDownloadDisabled() {
        return !this.downloadUrl;
    }

    get docNote() {
        if (this.isOpenDisabled && this.isDownloadDisabled) {
            return 'This file is not available right now.';
        }
        return this.mediaFailed ? 'This file cannot be shown here.' : '';
    }

    // ---------- actions ----------
    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleZoomIn() {
        this.zoom = Math.min(MAX_ZOOM, this.zoom + ZOOM_STEP);
    }

    handleZoomOut() {
        this.zoom = Math.max(MIN_ZOOM, this.zoom - ZOOM_STEP);
    }

    handleMediaError() {
        this.mediaFailed = true;
    }

    handleDownload() {
        if (this.downloadUrl) {
            window.open(this.downloadUrl, '_blank', 'noopener');
        }
    }

    handleOpenInSharePoint() {
        if (this.openUrl) {
            window.open(this.openUrl, '_blank', 'noopener');
        }
    }
}