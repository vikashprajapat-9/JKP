import { LightningElement } from 'lwc';
import getMarketingProjects from '@salesforce/apex/partnerWebPortalMarketingController.getMarketingProjects';

// Card photos move to the next image on their own every few seconds
const AUTO_SLIDE_MS = 2500;

function projectInitial(name) {
    return name ? name.trim().charAt(0).toUpperCase() : '';
}

export default class PartnerWebPortalMarketing extends LightningElement {

    projects = [];
    error;
    isLoaded = false;

    get hasProjects() {
        return this.projects.length > 0;
    }

    get showEmpty() {
        return this.isLoaded && !this.error && this.projects.length === 0;
    }

    // Project shown on the marketing detail page; null shows the list
    selectedProject = null;
    autoSlideTimer = null;
    pausedProjectId = null;
    // Counts the auto slides; each card shows photo slideTick % its photo count, which keeps them in step
    slideTick = 0;

    // Not wired: the OneDrive image links are short-lived, so every visit loads fresh ones
    connectedCallback() {
        this.loadProjects();
        // Started here, not after the load, so leaving before the projects arrive leaves no timer running
        this.startAutoSlide();
    }

    async loadProjects() {
        try {
            const data = await getMarketingProjects();
            this.projects = data.map(p => {
                // Images uploaded to the project's "Project Images" folder
                const images = (p.images || []).filter(img => img.mediaUrl);
                const slideImages = images.map((img, i) => ({
                    url: img.mediaUrl,
                    key: p.id + '-slide-' + i,
                    slideClass: i === 0 ? 'carousel-slide active' : 'carousel-slide'
                }));

                const dots = images.map((img, i) => ({
                    key: p.id + '-dot-' + i,
                    index: i,
                    dotClass: i === 0 ? 'dot active' : 'dot'
                }));

                return {
                    id: p.id,
                    name: p.name,
                    location: p.location,
                    initial: projectInitial(p.name),
                    activeIndex: 0,
                    carouselImages: slideImages,
                    dots,
                    hasImages: slideImages.length > 0,
                    hasMultipleImages: slideImages.length > 1
                };
            });
        } catch (error) {
            this.error = error && error.body ? error.body.message : 'Failed to load marketing projects';
        } finally {
            this.isLoaded = true;
        }
    }

    disconnectedCallback() {
        clearInterval(this.autoSlideTimer);
        this.autoSlideTimer = null;
    }

    startAutoSlide() {
        const reduceMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
        if (this.autoSlideTimer || reduceMotion) {
            return;
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.autoSlideTimer = setInterval(() => this.advanceSlides(), AUTO_SLIDE_MS);
    }

    advanceSlides() {
        if (this.selectedProject || !this.projects.length) {
            return;
        }
        // One shared count for every card, so all of them change photo at the same moment
        this.slideTick++;
        this.projects = this.projects.map((p) =>
            p.hasMultipleImages && p.id !== this.pausedProjectId
                ? this.withSlide(p, this.slideTick % p.carouselImages.length)
                : p
        );
    }

    // Hovering a card pauses its slideshow so the user can look at a photo
    handleCardEnter(event) {
        this.pausedProjectId = event.currentTarget.dataset.id;
    }

    handleCardLeave(event) {
        this.pausedProjectId = null;
        // Rejoin the other cards, also after this card's arrows or dots were used
        const project = this.projects.find((p) => p.id === event.currentTarget.dataset.id);
        if (project && project.hasMultipleImages) {
            this.setSlide(project.id, this.slideTick % project.carouselImages.length);
        }
    }

    // ---------- CAROUSEL ----------
    handlePrev(event) {
        event.stopPropagation();
        this.moveSlide(event.currentTarget.dataset.id, -1);
    }

    handleNext(event) {
        event.stopPropagation();
        this.moveSlide(event.currentTarget.dataset.id, 1);
    }

    handleDotClick(event) {
        event.stopPropagation();
        this.setSlide(
            event.currentTarget.dataset.id,
            Number(event.currentTarget.dataset.index)
        );
    }

    moveSlide(projectId, direction) {
        const project = this.projects.find(p => p.id === projectId);
        if (!project) return;

        const total = project.carouselImages.length;
        if (total <= 1) return;

        let newIndex = project.activeIndex + direction;
        if (newIndex < 0) newIndex = total - 1;
        if (newIndex >= total) newIndex = 0;

        this.setSlide(projectId, newIndex);
    }

    setSlide(projectId, newIndex) {
        this.projects = this.projects.map((p) => (p.id === projectId ? this.withSlide(p, newIndex) : p));
    }

    withSlide(p, newIndex) {
        const carouselImages = p.carouselImages.map((img, i) => ({
            ...img,
            slideClass: i === newIndex ? 'carousel-slide active' : 'carousel-slide'
        }));
        const dots = p.dots.map((dot, i) => ({
            ...dot,
            dotClass: i === newIndex ? 'dot active' : 'dot'
        }));
        return { ...p, activeIndex: newIndex, carouselImages, dots };
    }

    // ---------- VIEW DETAILS ----------
    handleViewDetails(event) {
        const projectId = event.currentTarget.dataset.id;
        const project = this.projects.find(p => p.id === projectId);
        if (!project) return;
        // The card leaves the page without a mouseleave, so its hover pause would otherwise stay after Back
        this.pausedProjectId = null;

        this.selectedProject = { id: project.id, name: project.name };
    }

    handleBackToList() {
        this.selectedProject = null;
    }
}