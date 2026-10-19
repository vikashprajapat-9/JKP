import { LightningElement } from 'lwc';
import getConstructionStatus from '@salesforce/apex/CustomerPortalController.getConstructionStatus';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import CP_ASSETS from '@salesforce/resourceUrl/customerPortalAssets';
import {
    BACK_ARROW,
    CARD_PREV,
    CARD_NEXT,
    CHEVRON_UP,
    CHEVRON_DOWN,
    PLAY,
    VIEWER_PREV,
    VIEWER_NEXT,
    CLOSE
} from './icons';

const VIEW_LIST = 'LIST_VIEW';
const VIEW_DETAIL = 'DETAIL_VIEW';

const VISIBLE_IMAGE_COUNT = 5;
const SWIPE_THRESHOLD_PX = 50;

// Visible text (Figma pages 26-28). Plain constants: the portal does not use Custom Labels.
const TEXT = {
    loading: 'Loading construction status',
    loadError: "We couldn't load Construction Status right now. Please try again in a moment.",
    toastTitle: 'Error',
    toastLoadError: 'Unable to load construction status. Please try again.',
    empty: 'No construction updates yet.',
    noUpdates: 'No project updates yet.',
    noMedia: 'No images or videos for this month yet.',
    progress: 'Construction Progress',
    viewUpdates: 'View Project Updates',
    unitNumberPrefix: 'Unit Number: ',
    back: 'Back',
    images: 'Images',
    videos: 'Videos',
    previousImage: 'Previous image',
    nextImage: 'Next image',
    openImage: 'Open image',
    playVideo: 'Play video',
    imageAlt: 'Construction update',
    imageViewer: 'Image viewer',
    videoPlayer: 'Video player',
    close: 'Close',
    previous: 'Previous',
    next: 'Next'
};

const ICONS = {
    back: BACK_ARROW,
    cardPrev: CARD_PREV,
    cardNext: CARD_NEXT,
    play: PLAY,
    viewerPrev: VIEWER_PREV,
    viewerNext: VIEWER_NEXT,
    close: CLOSE
};

function clampProgress(value) {
    const n = Number(value);
    return Number.isFinite(n) ? Math.max(0, Math.min(100, Math.round(n))) : 0;
}

export default class CustomerPortal_ConstructionStatus extends LightningElement {
    text = TEXT;
    icons = ICONS;
    emptyImageUrl = CP_ASSETS + '/empty-state.svg';

    pageData;
    isLoading = true;
    hasError = false;

    currentView = VIEW_LIST;

    selectedProjectId;
    activeUpdateId;

    projectImageIndex = {};

    isImageModalOpen = false;
    modalImages = [];
    selectedImageIndex = 0;

    isVideoModalOpen = false;
    selectedVideo;

    // Photos that failed to load (the grey placeholder shows instead of a broken image)
    brokenImages = {};

    // Not rendered, so no need to be reactive
    touchStartX = null;
    focusViewer = false;
    returnFocusTo = null;
    restoreFocus = false;

    connectedCallback() {
        this.loadConstructionStatus();
    }

    renderedCallback() {
        if (this.focusViewer) {
            const closeButton = this.template.querySelector('.cs-viewer__close');
            if (closeButton) {
                this.focusViewer = false;
                closeButton.focus();
            }
        } else if (this.restoreFocus) {
            // back to the tile that opened the viewer / player
            this.restoreFocus = false;
            if (this.returnFocusTo && this.returnFocusTo.isConnected) {
                this.returnFocusTo.focus();
            }
            this.returnFocusTo = null;
        }
    }

    async loadConstructionStatus() {
        this.isLoading = true;
        this.hasError = false;

        try {
            this.pageData = await getConstructionStatus();
        } catch (error) {
            this.hasError = true;
            console.error('customerPortal_ConstructionStatus: failed to load data', error);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: TEXT.toastTitle,
                    message: TEXT.toastLoadError,
                    variant: 'error'
                })
            );
        } finally {
            this.isLoading = false;
        }
    }

    get showContent() {
        return !this.isLoading && !this.hasError && this.pageData;
    }

    get isListView() {
        return this.currentView === VIEW_LIST;
    }

    get isDetailView() {
        return this.currentView === VIEW_DETAIL;
    }

    isUsableImage(url) {
        return !!url && !this.brokenImages[url];
    }

    /* ---------- Project cards (Figma p26) ---------- */

    get hasProjects() {
        return this.decoratedProjects.length > 0;
    }

    get decoratedProjects() {
        if (!this.pageData || !this.pageData.projects) {
            return [];
        }
        return this.pageData.projects.map((project) => {
            const images = project.images || [];
            const rawIndex = this.projectImageIndex[project.id] || 0;
            const safeIndex = images.length ? rawIndex % images.length : 0;
            const currentImage = images.length ? images[safeIndex] : null;
            const currentImageUrl = currentImage ? currentImage.imageUrl : '';
            const progress = clampProgress(project.progress);

            const dots = images.map((img, idx) => {
                return {
                    key: img.id,
                    dotClass: idx === safeIndex ? 'cs-card__dot cs-card__dot_active' : 'cs-card__dot'
                };
            });

            return {
                ...project,
                progressValue: progress,
                progressLabel: progress + '%',
                progressBarStyle: 'width: ' + progress + '%;',
                currentImageUrl,
                showImage: this.isUsableImage(currentImageUrl),
                hasMultipleImages: images.length > 1,
                dots
            };
        });
    }

    handlePrevProjectImage(event) {
        event.stopPropagation();
        const id = event.currentTarget.dataset.id;
        const project = this.findProject(id);
        const images = project && project.images ? project.images : [];
        if (!images.length) {
            return;
        }
        const current = this.projectImageIndex[id] || 0;
        const nextIndex = (current - 1 + images.length) % images.length;
        this.projectImageIndex = { ...this.projectImageIndex, [id]: nextIndex };
    }

    handleNextProjectImage(event) {
        event.stopPropagation();
        const id = event.currentTarget.dataset.id;
        const project = this.findProject(id);
        const images = project && project.images ? project.images : [];
        if (!images.length) {
            return;
        }
        const current = this.projectImageIndex[id] || 0;
        const nextIndex = (current + 1) % images.length;
        this.projectImageIndex = { ...this.projectImageIndex, [id]: nextIndex };
    }

    handleOpenProject(event) {
        const id = event.currentTarget.dataset.id;
        const project = this.findProject(id);

        this.selectedProjectId = id;
        this.currentView = VIEW_DETAIL;

        this.activeUpdateId = project && project.updates && project.updates.length ? project.updates[0].id : null;
    }

    handleBack() {
        this.currentView = VIEW_LIST;
        this.selectedProjectId = null;
        this.activeUpdateId = null;
    }

    findProject(id) {
        if (!this.pageData || !this.pageData.projects) {
            return null;
        }
        return this.pageData.projects.find((p) => p.id === id);
    }

    /* ---------- Project updates (Figma p27) ---------- */

    get selectedProject() {
        const project = this.findProject(this.selectedProjectId);
        if (!project) {
            return null;
        }
        const progress = clampProgress(project.progress);
        return {
            ...project,
            progressValue: progress,
            progressLabel: progress + '%',
            progressBarStyle: 'width: ' + progress + '%;',
            unitLabel: project.unitNumber ? TEXT.unitNumberPrefix + project.unitNumber : ''
        };
    }

    get hasUpdates() {
        return this.decoratedUpdates.length > 0;
    }

    decorateTile(img, showOverlay, overlayLabel) {
        return {
            ...img,
            showOverlay,
            overlayLabel,
            showImage: this.isUsableImage(img.imageUrl),
            ariaLabel: showOverlay ? TEXT.openImage + ' (' + overlayLabel + ')' : TEXT.openImage
        };
    }

    get decoratedUpdates() {
        const project = this.selectedProject;
        if (!project || !project.updates) {
            return [];
        }

        return project.updates.map((update) => {
            const isActive = update.id === this.activeUpdateId;
            const allImages = update.images || [];

            const visibleImages = allImages.slice(0, VISIBLE_IMAGE_COUNT).map((img) => this.decorateTile(img, false, ''));

            let displayImages = visibleImages;
            if (allImages.length > VISIBLE_IMAGE_COUNT) {
                const moreTileSource = allImages[VISIBLE_IMAGE_COUNT];
                const remainingCount = allImages.length - VISIBLE_IMAGE_COUNT;
                displayImages = [...visibleImages, this.decorateTile(moreTileSource, true, remainingCount + '+')];
            }

            const videos = (update.videos || []).map((vid) => ({
                ...vid,
                showThumb: this.isUsableImage(vid.thumbnailUrl)
            }));

            return {
                ...update,
                isActive,
                ariaExpanded: isActive ? 'true' : 'false',
                headerClass: isActive ? 'cs-acc__head cs-acc__head_open' : 'cs-acc__head',
                chevronPath: isActive ? CHEVRON_UP : CHEVRON_DOWN,
                displayImages,
                videos,
                hasImages: allImages.length > 0,
                hasVideos: videos.length > 0,
                hasNoMedia: allImages.length === 0 && videos.length === 0
            };
        });
    }

    handleToggleUpdate(event) {
        const id = event.currentTarget.dataset.id;
        this.activeUpdateId = this.activeUpdateId === id ? null : id;
    }

    findUpdate(updateId) {
        const project = this.selectedProject;
        if (!project || !project.updates) {
            return null;
        }
        return project.updates.find((u) => u.id === updateId);
    }

    handleImageError(event) {
        const url = event.currentTarget.dataset.src;
        if (url && !this.brokenImages[url]) {
            this.brokenImages = { ...this.brokenImages, [url]: true };
        }
    }

    /* ---------- Image viewer (Figma p28) ---------- */

    handleImageClick(event) {
        const updateId = event.currentTarget.dataset.updateId;
        const imageId = event.currentTarget.dataset.imageId;

        const update = this.findUpdate(updateId);
        if (!update) {
            return;
        }

        const images = update.images || [];
        const index = images.findIndex((img) => img.id === imageId);

        this.modalImages = images;
        this.selectedImageIndex = index >= 0 ? index : 0;
        this.returnFocusTo = event.currentTarget;
        this.isImageModalOpen = true;
        this.focusViewer = true;
    }

    get currentModalImage() {
        return this.modalImages[this.selectedImageIndex] || {};
    }

    get showModalImage() {
        return this.isUsableImage(this.currentModalImage.imageUrl);
    }

    get hasMultipleModalImages() {
        return this.modalImages.length > 1;
    }

    get decoratedModalDots() {
        return this.modalImages.map((img, idx) => {
            return {
                key: img.id,
                dotClass: idx === this.selectedImageIndex ? 'cs-viewer__dot cs-viewer__dot_active' : 'cs-viewer__dot'
            };
        });
    }

    handlePrevImage() {
        const count = this.modalImages.length;
        if (!count) {
            return;
        }
        this.selectedImageIndex = (this.selectedImageIndex - 1 + count) % count;
    }

    handleNextImage() {
        const count = this.modalImages.length;
        if (!count) {
            return;
        }
        this.selectedImageIndex = (this.selectedImageIndex + 1) % count;
    }

    handleCloseImageModal() {
        this.isImageModalOpen = false;
        this.modalImages = [];
        this.selectedImageIndex = 0;
        this.touchStartX = null;
        this.restoreFocus = true;
    }

    handleVideoClick(event) {
        const updateId = event.currentTarget.dataset.updateId;
        const videoId = event.currentTarget.dataset.videoId;

        const update = this.findUpdate(updateId);
        if (!update) {
            return;
        }

        const video = (update.videos || []).find((v) => v.id === videoId);
        if (!video) {
            return;
        }

        this.selectedVideo = video;
        this.returnFocusTo = event.currentTarget;
        this.isVideoModalOpen = true;
        this.focusViewer = true;
    }

    handleCloseVideoModal() {
        this.isVideoModalOpen = false;
        this.selectedVideo = null;
        this.restoreFocus = true;
    }

    stopPropagation(event) {
        event.stopPropagation();
    }

    /* ---------- Additive: mobile / keyboard support ---------- */

    // Escape closes the viewer / player; the arrow keys change the image
    handleViewerKeydown(event) {
        if (event.key === 'Escape') {
            event.preventDefault();
            event.stopPropagation();
            if (this.isImageModalOpen) {
                this.handleCloseImageModal();
            } else if (this.isVideoModalOpen) {
                this.handleCloseVideoModal();
            }
        } else if (this.isImageModalOpen && event.key === 'ArrowLeft') {
            event.preventDefault();
            this.handlePrevImage();
        } else if (this.isImageModalOpen && event.key === 'ArrowRight') {
            event.preventDefault();
            this.handleNextImage();
        }
    }

    // Swipe left/right inside the image viewer to change image
    handleModalTouchStart(event) {
        this.touchStartX = event.changedTouches && event.changedTouches.length ? event.changedTouches[0].clientX : null;
    }

    handleModalTouchEnd(event) {
        if (this.touchStartX === null || !event.changedTouches || !event.changedTouches.length) {
            return;
        }
        const deltaX = event.changedTouches[0].clientX - this.touchStartX;
        this.touchStartX = null;

        if (Math.abs(deltaX) < SWIPE_THRESHOLD_PX) {
            return;
        }
        if (deltaX < 0) {
            this.handleNextImage();
        } else {
            this.handlePrevImage();
        }
    }
}