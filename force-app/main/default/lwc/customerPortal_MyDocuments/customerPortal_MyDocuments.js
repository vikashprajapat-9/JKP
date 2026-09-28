import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getMyDocumentsPageData from '@salesforce/apex/customerPortalController.getMyDocumentsPageData';

const VIEW_LIST = 'LIST';
const VIEW_DETAIL = 'DETAIL';

export default class CustomerPortal_MyDocuments extends LightningElement {

    pageData;
    isLoading = true;
    hasError = false;

    view = VIEW_LIST;
    selectedProjectId;
    activeCategoryKey = 'myDocuments';

    imageIndexById = {};

    isPreviewOpen = false;
    previewDocUrl;
    previewDocName;

    connectedCallback() {
        this.loadDocuments();
    }

    async loadDocuments() {
        this.isLoading = true;
        this.hasError = false;

        try {
            this.pageData = await getMyDocumentsPageData();
            const indexMap = {};
            (this.pageData.projects || []).forEach((p) => {
                indexMap[p.id] = 0;
            });
            this.imageIndexById = indexMap;
        } catch (error) {
            this.hasError = true;
            console.error('customerPortal_MyDocuments: failed to load documents', error);
            this.showErrorToast('Unable to load documents. Please try again.');
        } finally {
            this.isLoading = false;
        }
    }

    showErrorToast(message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error',
                message,
                variant: 'error',
                mode: 'dismissable'
            })
        );
    }

    get pageTitle() {
        return this.pageData ? this.pageData.title : '';
    }

    get pageDescription() {
        return this.pageData ? this.pageData.description : '';
    }

    get showListView() {
        return !this.isLoading && !this.hasError && this.view === VIEW_LIST;
    }

    get showDetailView() {
        return !this.isLoading && !this.hasError && this.view === VIEW_DETAIL && this.selectedProject;
    }

    get rawProjects() {
        return this.pageData ? this.pageData.projects || [] : [];
    }

    get selectedProject() {
        return this.rawProjects.find((p) => p.id === this.selectedProjectId) || null;
    }

    get displayedProjects() {
        return this.rawProjects.map((project) => this.decorateProjectCard(project));
    }

    decorateProjectCard(project) {
        const images = project.images || [];
        const activeIndex = this.imageIndexById[project.id] || 0;
        const activeImageUrl = images.length ? images[activeIndex % images.length].url : '';

        const dots = images.map((img, idx) => {
            return {
                key: project.id + '-dot-' + idx,
                dotClass: idx === activeIndex ? 'dot dot_active' : 'dot'
            };
        });

        return {
            id: project.id,
            name: project.name,
            shortAddress: project.address,
            activeImageUrl,
            showArrows: images.length > 1,
            showDots: images.length > 1,
            dots
        };
    }

    handleCardPrevImage(event) {
        this.stepImage(event.currentTarget.dataset.id, -1);
    }

    handleCardNextImage(event) {
        this.stepImage(event.currentTarget.dataset.id, 1);
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

    handleViewDetails(event) {
        this.selectedProjectId = event.currentTarget.dataset.id;
        this.activeCategoryKey = 'myDocuments';
        this.view = VIEW_DETAIL;
    }

    handleBack() {
        this.view = VIEW_LIST;
        this.selectedProjectId = undefined;
    }

    get categoryTabs() {
        const project = this.selectedProject;
        if (!project || !project.documentCategories) {
            return [];
        }
        return project.documentCategories.map((cat) => {
            return {
                key: cat.key,
                label: cat.label,
                tabClass:
                    cat.key === this.activeCategoryKey
                        ? 'tab-btn tab-btn_active'
                        : 'tab-btn'
            };
        });
    }

    get activeCategoryRaw() {
        const project = this.selectedProject;
        if (!project || !project.documentCategories) {
            return null;
        }
        return project.documentCategories.find((c) => c.key === this.activeCategoryKey) || null;
    }

    get activeDocuments() {
        const category = this.activeCategoryRaw;
        return category ? category.documents || [] : [];
    }

    get hasActiveDocuments() {
        return this.activeDocuments.length > 0;
    }

    handleTabClick(event) {
        this.activeCategoryKey = event.currentTarget.dataset.key;
    }

    findDocumentById(docId) {
        return this.activeDocuments.find((d) => d.id === docId) || null;
    }

    handlePreview(event) {
        const docId = event.currentTarget.dataset.id;
        const doc = this.findDocumentById(docId);

        if (!doc || !doc.documentUrl) {
            this.showErrorToast('Unable to open this document.');
            return;
        }

        this.previewDocUrl = doc.documentUrl;
        this.previewDocName = doc.name;
        this.isPreviewOpen = true;
    }

    handleClosePreview() {
        this.isPreviewOpen = false;
        this.previewDocUrl = undefined;
        this.previewDocName = undefined;
    }

    stopPropagation(event) {
        event.stopPropagation();
    }

   async handleDownload(event) {
        const docId = event.currentTarget.dataset.id;
        const doc = this.findDocumentById(docId);

        if (!doc || !doc.documentUrl) {
            this.showErrorToast('Unable to open this document.');
            return;
        }

        try {
            const response = await fetch(doc.documentUrl);
            if (!response.ok) {
                throw new Error('Request failed with status ' + response.status);
            }
            const blob = await response.blob();
            const blobUrl = window.URL.createObjectURL(blob);

            const link = document.createElement('a');
            link.href = blobUrl;
            link.download = this.buildDownloadFileName(doc);
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);

            window.URL.revokeObjectURL(blobUrl);
        } catch (error) {
            console.error('customerPortal_MyDocuments: failed to download document', error);
            this.showErrorToast('Unable to download this document. Please try again.');
        }
    }

    buildDownloadFileName(doc) {
        const urlParts = (doc.documentUrl || '').split('?')[0].split('/');
        const lastSegment = urlParts[urlParts.length - 1];
        const hasExtension = lastSegment && lastSegment.includes('.');
        return hasExtension ? lastSegment : (doc.name || 'document') + '.pdf';
    }
}