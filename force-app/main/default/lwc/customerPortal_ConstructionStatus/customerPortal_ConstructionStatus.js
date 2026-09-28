import { LightningElement } from 'lwc';
import getConstructionStatus from '@salesforce/apex/customerPortalController.getConstructionStatus';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const VIEW_LIST = 'LIST_VIEW';
const VIEW_DETAIL = 'DETAIL_VIEW';

const VISIBLE_IMAGE_COUNT = 5;
const SWIPE_THRESHOLD_PX = 50;

export default class CustomerPortal_ConstructionStatus extends LightningElement {

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

    // Not rendered, so no need to be reactive
    touchStartX = null;

    connectedCallback() {
        this.loadConstructionStatus();
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
                    title: 'Error',
                    message: 'Unable to load construction status. Please try again.',
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

    get decoratedProjects() {
        if (!this.pageData || !this.pageData.projects) {
            return [];
        }
        return this.pageData.projects.map((project) => {
            const images = project.images || [];
            const rawIndex = this.projectImageIndex[project.id] || 0;
            const safeIndex = images.length ? rawIndex % images.length : 0;
            const currentImage = images.length ? images[safeIndex] : null;

            const dots = images.map((img, idx) => {
                return {
                    key: img.id,
                    dotClass:
                        idx === safeIndex
                            ? 'cs-image-dot cs-image-dot_active'
                            : 'cs-image-dot'
                };
            });

            return {
                ...project,
                progressBarStyle: 'width: ' + project.progress + '%;',
                currentImageUrl: currentImage ? currentImage.imageUrl : '',
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

        this.activeUpdateId =
            project && project.updates && project.updates.length
                ? project.updates[0].id
                : null;
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

    get selectedProject() {
        const project = this.findProject(this.selectedProjectId);
        if (!project) {
            return null;
        }
        return {
            ...project,
            progressBarStyle: 'width: ' + project.progress + '%;'
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

            const visibleImages = allImages.slice(0, VISIBLE_IMAGE_COUNT).map((img) => {
                return { ...img, showOverlay: false, overlayLabel: '' };
            });

            let displayImages = visibleImages;
            if (allImages.length > VISIBLE_IMAGE_COUNT) {
                const moreTileSource = allImages[VISIBLE_IMAGE_COUNT];
                const remainingCount = allImages.length - VISIBLE_IMAGE_COUNT;
                const moreTile = {
                    ...moreTileSource,
                    showOverlay: true,
                    overlayLabel: remainingCount + '+'
                };
                displayImages = [...visibleImages, moreTile];
            }

            return {
                ...update,
                isActive,
                headerClass: isActive
                    ? 'cs-accordion-header cs-accordion-header_active'
                    : 'cs-accordion-header',
                arrowIcon: isActive ? 'utility:chevronup' : 'utility:chevrondown',
                displayImages,
                hasImages: allImages.length > 0,
                hasVideos: !!(update.videos && update.videos.length > 0)
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
        this.isImageModalOpen = true;
    }

    get currentModalImage() {
        return this.modalImages[this.selectedImageIndex] || {};
    }

    get decoratedModalDots() {
        return this.modalImages.map((img, idx) => {
            return {
                key: img.id,
                dotClass:
                    idx === this.selectedImageIndex
                        ? 'cs-modal-dot cs-modal-dot_active'
                        : 'cs-modal-dot'
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
        this.isVideoModalOpen = true;
    }

    handleCloseVideoModal() {
        this.isVideoModalOpen = false;
        this.selectedVideo = null;
    }

    stopPropagation(event) {
        event.stopPropagation();
    }

    /* ---------- Additive: mobile / keyboard support ---------- */

    // Thumbnails are role="button" divs, so make Enter / Space activate them
    handleThumbKeydown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            event.currentTarget.click();
        }
    }

    // Swipe left/right inside the image viewer to change image
    handleModalTouchStart(event) {
        this.touchStartX =
            event.changedTouches && event.changedTouches.length
                ? event.changedTouches[0].clientX
                : null;
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