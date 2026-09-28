import { LightningElement } from 'lwc';
import getProjects from '@salesforce/apex/customerPortalController.getProjects';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
const VIEW_LIST = 'PROJECT_LIST';
const VIEW_DETAILS = 'PROJECT_DETAILS';

export default class CustomerPortal_Project extends LightningElement {

    rawProjects = [];

    isLoading = true;
    hasError = false;

    view = VIEW_LIST;
    activeTab = 'current'; 

    selectedProjectId;

    imageIndexById = {};

    introText =
        'Explore our extensive property Projects and take the first step towards finding your ' +
        'dream home with John Keels Properties . Our curated selection offers a variety of ' +
        'options to suit your needs and preferences. Start your journey with us today and ' +
        'discover the perfect place to call home.';

    connectedCallback() {
        this.loadProjects();
    }

    async loadProjects() {
        this.isLoading = true;
        this.hasError = false;

        try {
            const result = await getProjects();
            this.rawProjects = result || [];
            const indexMap = {};
            this.rawProjects.forEach((p) => {
                indexMap[p.id] = 0;
            });
            this.imageIndexById = indexMap;
        } catch (error) {
            this.hasError = true;
            console.error('customerPortal_Project: failed to load projects', error);
             this.showErrorToast('Failed to load projects.');
        } finally {
            this.isLoading = false;
        }
    }


    decorateProject(project) {
        const images = project.images || [];
        const activeIndex = this.imageIndexById[project.id] || 0;
        const activeImageUrl = images.length
            ? images[activeIndex % images.length].url
            : '';

        const dots = images.map((img, idx) => {
            return {
                key: project.id + '-dot-' + idx,
                dotClass: idx === activeIndex ? 'dot dot_active' : 'dot'
            };
        });

        const specs = (project.specs || []).map((spec, idx) => {
            return {
                ...spec,
                key: project.id + '-spec-' + idx
            };
        });

        const amenities = (project.amenities || []).map((amenity, idx) => {
            const isWater = amenity.icon === 'water';
            const isGarbage = amenity.icon === 'garbage';
            const isPark = amenity.icon === 'park';
            const isPool = amenity.icon === 'pool';
            let colorClass = '';
            if (isWater) {
                colorClass = 'amenity-icon_water';
            } else if (isGarbage) {
                colorClass = 'amenity-icon_garbage';
            } else if (isPark) {
                colorClass = 'amenity-icon_park';
            } else if (isPool) {
                colorClass = 'amenity-icon_pool';
            }
            return {
                ...amenity,
                key: project.id + '-amenity-' + idx,
                isWater,
                isGarbage,
                isPark,
                isPool,
                iconWrapClass: 'amenity-icon ' + colorClass
            };
        });

        return {
            ...project,
            activeImageUrl,
            hasMultipleImages: images.length > 1,
            dots,
            specs,
            amenities
        };
    }

    get visibleProjects() {
        return this.rawProjects
            .filter((p) => p.status === this.activeTab)
            .map((p) => this.decorateProject(p));
    }

    get hasVisibleProjects() {
        return this.visibleProjects.length > 0;
    }

    get selectedProject() {
        const found = this.rawProjects.find((p) => p.id === this.selectedProjectId);
        return found ? this.decorateProject(found) : null;
    }

    get showListView() {
        return !this.isLoading && !this.hasError && this.view === VIEW_LIST;
    }

    get showDetailsView() {
        return !this.isLoading && !this.hasError && this.view === VIEW_DETAILS && this.selectedProject;
    }

    get currentTabClass() {
        return this.activeTab === 'current' ? 'tab tab_active' : 'tab';
    }

    get upcomingTabClass() {
        return this.activeTab === 'upcoming' ? 'tab tab_active' : 'tab';
    }

    handleShowCurrent() {
        this.activeTab = 'current';
    }

    handleShowUpcoming() {
        this.activeTab = 'upcoming';
    }

    handleViewDetails(event) {
        this.selectedProjectId = event.currentTarget.dataset.id;
        this.view = VIEW_DETAILS;
    }

    handleBack() {
        this.view = VIEW_LIST;
        this.selectedProjectId = undefined;
    }

    handleScheduleVisit() {
        // Hook point reserved for a future "schedule a visit" flow.
    }

    handleDownloadBrochure() {
        const project = this.selectedProject;
        if (project && project.brochureUrl) {
            window.open(project.brochureUrl, '_blank', 'noopener,noreferrer');
        }
    }

    handleCardPrevImage(event) {
        event.stopPropagation();
        const id = event.currentTarget.dataset.id;
        this.stepImage(id, -1);
    }

    handleCardNextImage(event) {
        event.stopPropagation();
        const id = event.currentTarget.dataset.id;
        this.stepImage(id, 1);
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

    handleDetailsPrevImage() {
        if (this.selectedProjectId) {
            this.stepImage(this.selectedProjectId, -1);
        }
    }

    handleDetailsNextImage() {
        if (this.selectedProjectId) {
            this.stepImage(this.selectedProjectId, 1);
        }
    }

    showErrorToast(message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Something went wrong',
                message,
                variant: 'error',
                mode: 'dismissable'
            })
        );
    }
}