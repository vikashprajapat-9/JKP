import { LightningElement, wire } from 'lwc';
import getMarketingProjects from '@salesforce/apex/PartnerWebPortalProjectController.getMarketingProjects';
import getProjects from '@salesforce/apex/PartnerWebPortalProjectController.getProjects';
export default class PartnerWebPortalMarketing extends LightningElement {

    projects = [];
    error;

    // ---------- MODAL STATE ----------
    isModalOpen = false;
    selectedProject = { name: '', location: '' };

    @wire(getMarketingProjects)
    wiredProjects({ data, error }) {
        if (data) {
            this.projects = data.map(p => {
                const slideImages = (p.imageUrls || []).map((url, i) => ({
                    url,
                    key: p.id + '-slide-' + i,
                    slideClass: i === 0 ? 'carousel-slide active' : 'carousel-slide'
                }));

                const dots = (p.imageUrls || []).map((url, i) => ({
                    url,
                    key: p.id + '-dot-' + i,
                    index: i,
                    dotClass: i === 0 ? 'dot active' : 'dot'
                }));

                return {
                    id: p.id,
                    name: p.name,
                    location: p.location,
                    activeIndex: 0,
                    carouselImages: slideImages,
                    dots,
                    hasMultipleImages: slideImages.length > 1
                };
            });
        } else if (error) {
            this.error = error.body ? error.body.message : 'Failed to load marketing projects';
            console.error('Marketing wire error:', error);
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

    // ---------- MODAL OPEN / CLOSE ----------
    handleViewDetails(event) {
        const projectId = event.currentTarget.dataset.id;
        const project = this.projects.find(p => p.id === projectId);
        if (!project) return;

        this.selectedProject = {
            name: project.name,
            location: project.location
        };
        this.isModalOpen = true;

        // Prevent background scroll
        document.body.style.overflow = 'hidden';
    }

    handleCloseModal() {
        this.isModalOpen = false;
        this.selectedProject = { name: '', location: '' };
        document.body.style.overflow = '';
    }

    // Close on backdrop click
    handleBackdropClick(event) {
        if (event.target.dataset.backdrop === 'true') {
            this.handleCloseModal();
        }
    }

    // Close on ESC
    handleKeyDown(event) {
        if (event.key === 'Escape' && this.isModalOpen) {
            this.handleCloseModal();
        }
    }

    connectedCallback() {
        window.addEventListener('keydown', this.handleKeyDown);
    }

    disconnectedCallback() {
        window.removeEventListener('keydown', this.handleKeyDown);
        document.body.style.overflow = '';
    }
}