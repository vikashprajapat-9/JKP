import { LightningElement, api } from 'lwc';
// Same project cards as the Marketing screen: active projects with their "Project Images" folder photos
import getMarketingProjects from '@salesforce/apex/partnerWebPortalMarketingController.getMarketingProjects';
// The Customer Portal shows this page too, for every active project
import getCustomerProjects from '@salesforce/apex/CustomerPortalController.getProjects';

// Card photos move to the next image on their own every few seconds
const AUTO_SLIDE_MS = 2500;

// Customer Portal (portal="customer"): its own markup and text, Figma p16-p17
const CUSTOMER_TEXT = {
    title: 'Projects',
    tabsLabel: 'Projects',
    currentTab: 'Current Projects',
    upcomingTab: 'Upcoming Projects',
    viewDetails: 'View Details',
    type: 'Type',
    previousPhoto: 'Previous photo',
    nextPhoto: 'Next photo',
    loading: 'Loading projects',
    empty: 'No projects available right now.',
    emptyCurrent: 'No current projects right now.',
    emptyUpcoming: 'No upcoming projects right now.'
};
const TAB_CURRENT = 'current';
const TAB_UPCOMING = 'upcoming';
// Project_Status__c value of the projects the Upcoming Projects tab lists
const UPCOMING_STATUS = 'Upcoming';

function projectInitial(name) {
    return name ? name.trim().charAt(0).toUpperCase() : '';
}

// "2 BR", "3 BR", "4 BR" -> "2, 3 & 4 BR" (the design's "3 & 4 BHK"); other names are listed as they are
function joinUnitTypes(types) {
    const names = [...new Set((types || []).filter(Boolean).map((t) => String(t).trim()))];
    if (names.length < 2) {
        return names.join('');
    }
    const parts = names.map((n) => /^(\S+)\s+(.+)$/.exec(n));
    const suffix = parts[0] && parts[0][2];
    const list = parts.every((p) => p && p[2] === suffix) ? parts.map((p) => p[1]) : names;
    const text = list.slice(0, -1).join(', ') + ' & ' + list[list.length - 1];
    return list === names ? text : `${text} ${suffix}`;
}

export default class PartnerWebPortalProject extends LightningElement {

    // Which portal shows the page: 'partner' (the default) or 'customer'. It decides whose projects and files are read,
    // and the customer gets the Customer Portal's own markup and look (the partner markup is left as it is).
    @api portal = 'partner';
    // Text under the title; the Partner Portal's own text when none is given
    @api subtitle;
    // Customer Portal only: picture shown with an empty list
    @api emptyImage;

    projects = [];
    error;
    isLoaded = false;
    // Customer Portal tabs (shown when the projects carry their status)
    activeTab = TAB_CURRENT;
    customerText = CUSTOMER_TEXT;

    get isCustomer() {
        return this.portal === 'customer';
    }

    get hasProjects() {
        return this.projects.length > 0;
    }

    get showEmpty() {
        return this.isLoaded && !this.error && this.projects.length === 0;
    }

    // Project shown on the detail page; null shows the list
    selectedProject = null;
    autoSlideTimer = null;
    pausedProjectId = null;
    // Counts the auto slides; each card shows photo slideTick % its photo count, which keeps them in step
    slideTick = 0;

    // Not wired: every visit reads the projects again, so newly uploaded photos show at once
    connectedCallback() {
        this.loadProjects();
        // Started here, not after the load, so leaving before the projects arrive leaves no timer running
        this.startAutoSlide();
    }

    async loadProjects() {
        try {
            const data = await (this.portal === 'customer' ? getCustomerProjects() : getMarketingProjects());
            this.projects = data.map(p => {
                const images = (p.images || []).filter(img => img.mediaUrl);
                const slideImages = images.map((img, i) => ({
                    url: img.mediaUrl,
                    key: p.id + '-slide-' + i,
                    slideClass: this.slideClassFor(i === 0)
                }));

                const dots = images.map((img, i) => ({
                    key: p.id + '-dot-' + i,
                    index: i,
                    dotClass: this.dotClassFor(i === 0),
                    label: `Photo ${i + 1} of ${images.length}`
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
                    hasMultipleImages: slideImages.length > 1,
                    // Read when the project card carries them (the Customer Portal's tabs and "Type" line)
                    status: p.status,
                    typeText: joinUnitTypes(p.unitTypes)
                };
            });
        } catch (error) {
            this.error = error && error.body ? error.body.message : 'Failed to load projects';
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
            slideClass: this.slideClassFor(i === newIndex)
        }));
        const dots = p.dots.map((dot, i) => ({
            ...dot,
            dotClass: this.dotClassFor(i === newIndex)
        }));
        return { ...p, activeIndex: newIndex, carouselImages, dots };
    }

    // Each portal's own class names for a photo and its dot
    slideClassFor(active) {
        if (this.isCustomer) {
            return active ? 'cpp-slide cpp-slide_active' : 'cpp-slide';
        }
        return active ? 'carousel-slide active' : 'carousel-slide';
    }

    dotClassFor(active) {
        if (this.isCustomer) {
            return active ? 'cpp-dot cpp-dot_active' : 'cpp-dot';
        }
        return active ? 'dot active' : 'dot';
    }

    // ---------- CUSTOMER PORTAL: TABS AND STATES ----------
    // Current / Upcoming Projects (Figma p16-p17) need each project's status; without it the page lists every project
    get showTabs() {
        return this.isCustomer && this.projects.some((p) => p.status !== undefined && p.status !== null);
    }

    get tabs() {
        return [
            { value: TAB_CURRENT, label: CUSTOMER_TEXT.currentTab },
            { value: TAB_UPCOMING, label: CUSTOMER_TEXT.upcomingTab }
        ].map((tab) => {
            const selected = tab.value === this.activeTab;
            return {
                ...tab,
                selected: selected ? 'true' : 'false',
                tabIndex: selected ? '0' : '-1',
                className: selected ? 'cpp-tab cpp-tab_active' : 'cpp-tab'
            };
        });
    }

    get visibleProjects() {
        if (!this.showTabs) {
            return this.projects;
        }
        const upcoming = this.activeTab === TAB_UPCOMING;
        return this.projects.filter((p) => (p.status === UPCOMING_STATUS) === upcoming);
    }

    get hasVisibleProjects() {
        return this.visibleProjects.length > 0;
    }

    // The cards are the tab panel while the tabs show
    get contentRole() {
        return this.showTabs ? 'tabpanel' : undefined;
    }

    get showCustomerLoading() {
        return !this.isLoaded;
    }

    get showCustomerEmpty() {
        return this.isLoaded && !this.error && !this.hasVisibleProjects;
    }

    get customerEmptyText() {
        if (!this.showTabs) {
            return CUSTOMER_TEXT.empty;
        }
        return this.activeTab === TAB_UPCOMING ? CUSTOMER_TEXT.emptyUpcoming : CUSTOMER_TEXT.emptyCurrent;
    }

    handleTabClick(event) {
        this.activeTab = event.currentTarget.dataset.value;
    }

    // Left / right arrows move between the two tabs (tab pattern)
    handleTabKeyDown(event) {
        if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') {
            return;
        }
        event.preventDefault();
        this.activeTab = this.activeTab === TAB_CURRENT ? TAB_UPCOMING : TAB_CURRENT;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        requestAnimationFrame(() => {
            const tab = this.template.querySelector('.cpp-tab_active');
            if (tab) {
                tab.focus();
            }
        });
    }

    // ---------- DETAIL PAGE ----------
    handleViewDetails(event) {
        const projectId = event.currentTarget.dataset.id;
        const project = this.projects.find(p => p.id === projectId);
        if (!project) return;
        // The card leaves the page without a mouseleave, so its hover pause would otherwise stay after Back
        this.pausedProjectId = null;

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