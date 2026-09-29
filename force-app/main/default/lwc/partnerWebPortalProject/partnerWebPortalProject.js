import { LightningElement, wire } from 'lwc';
import getMarketingProjects from '@salesforce/apex/partnerWebPortalProjectController.getMarketingProjects';
// Placeholder stock-photo URLs are not shown; the card falls back to a styled block.
const PLACEHOLDER_HOSTS = ['picsum.photos'];

function realImageUrls(urls) {
    return (urls || []).filter(
        url => url && !PLACEHOLDER_HOSTS.some(host => url.includes(host))
    );
}

function projectInitial(name) {
    return name ? name.trim().charAt(0).toUpperCase() : '';
}

export default class PartnerWebPortalProject extends LightningElement {

    projects = [];
    error;
    isLoaded = false;

    get hasProjects() {
        return this.projects.length > 0;
    }

    get showEmpty() {
        return this.isLoaded && !this.error && this.projects.length === 0;
    }

    // Project shown on the detail page; null shows the list
    selectedProject = null;

    @wire(getMarketingProjects)
    wiredProjects({ data, error }) {
        if (data) {
            this.isLoaded = true;
            this.projects = data.map(p => {
                const realImages = realImageUrls(p.imageUrls);
                const slideImages = realImages.map((url, i) => ({
                    url,
                    key: p.id + '-slide-' + i,
                    slideClass: i === 0 ? 'carousel-slide active' : 'carousel-slide'
                }));

                const dots = realImages.map((url, i) => ({
                    url,
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
        } else if (error) {
            this.isLoaded = true;
            this.error = error.body ? error.body.message : 'Failed to load projects';
            console.error('Projects wire error:', error);
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
        this.projects = this.projects.map(p => {
            if (p.id !== projectId) return p;
            const carouselImages = p.carouselImages.map((img, i) => ({
                ...img,
                slideClass: i === newIndex ? 'carousel-slide active' : 'carousel-slide'
            }));
            const dots = p.dots.map((dot, i) => ({
                ...dot,
                dotClass: i === newIndex ? 'dot active' : 'dot'
            }));
            return { ...p, activeIndex: newIndex, carouselImages, dots };
        });
    }

    // ---------- DETAIL PAGE ----------
    handleViewDetails(event) {
        const projectId = event.currentTarget.dataset.id;
        const project = this.projects.find(p => p.id === projectId);
        if (!project) return;

        this.selectedProject = {
            id: project.id,
            name: project.name,
            location: project.location,
            initial: project.initial,
            image: project.hasImages
                ? project.carouselImages[project.activeIndex || 0].url
                : null
        };
    }

    handleBackToList() {
        this.selectedProject = null;
    }
}