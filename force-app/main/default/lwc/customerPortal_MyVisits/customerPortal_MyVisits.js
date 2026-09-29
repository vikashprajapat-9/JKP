import { LightningElement, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import SUCCESS_ILLUSTRATION from '@salesforce/resourceUrl/SuccessReferralImage';
import getMyVisitsPageData from '@salesforce/apex/CustomerPortalController.getMyVisitsPageData';
import scheduleVisit from '@salesforce/apex/CustomerPortalController.scheduleVisit';
import rescheduleVisit from '@salesforce/apex/CustomerPortalController.rescheduleVisit';
import cancelVisit from '@salesforce/apex/CustomerPortalController.cancelVisit';
import submitVisitFeedback from '@salesforce/apex/CustomerPortalController.submitVisitFeedback';

export default class CustomerPortal_MyVisits extends LightningElement {
    @track isLoading = true;
    @track hasError = false;
    @track pageDescription = '';
    @track rawUpcoming = [];
    @track rawCompleted = [];
    @track rawIncomplete = [];
    @track scheduleProjectOptions = [];
    @track scheduleUnitOptions = [];
    @track visitTypeOptions = [];
    @track rescheduleReasonOptions = [];
    @track feedbackQuestionDefs = [];

    activeTab = 'upcoming';
    successType = 'generic'; // 'generic' | 'cancel'
    successImageUrl = SUCCESS_ILLUSTRATION;

    isScheduleModalOpen = false;
    isRescheduleModalOpen = false;
    isCancelModalOpen = false;
    isFeedbackModalOpen = false;
    isSuccessModalOpen = false;
    successTitle = '';
    successMessage = '';
    @track selectedVisit;

    // ---- form state ----
    @track scheduleForm = { project: '', unit: '', visitDate: '', visitTime: '', visitType: '', visitDetails: '' };
    @track rescheduleForm = { visitDate: '', visitTime: '', reason: '', visitDetails: '' };
    @track cancelForm = { reason: '' };
    @track feedbackRatings = { q1: 0, q2: 0, q3: 0, q4: 0, q5: 0 };

    isSubmitting = false;

    @wire(getMyVisitsPageData)
    wiredPageData({ data, error }) {
        if (data) {
            this.isLoading = false;
            this.hasError = false;
            this.applyPageData(data);
        } else if (error) {
            this.isLoading = false;
            this.hasError = true;
            console.error('Error loading My Visits page data', error);
            this.showErrorToast('Unable to load visits', error);
        }
    }

    applyPageData(data) {
        this.pageDescription = data.description;
        this.rawUpcoming = (data.upcomingVisits || []).map((v) => this.initializeVisit(v));
        this.rawCompleted = (data.completedVisits || []).map((v) => this.initializeVisit(v));
        this.rawIncomplete = (data.incompleteVisits || []).map((v) => this.initializeVisit(v));
        this.scheduleProjectOptions = data.scheduleVisitOptions || [];
        this.scheduleUnitOptions = data.scheduleUnitOptions || [];
        this.visitTypeOptions = data.visitTypeOptions || [];
        this.rescheduleReasonOptions = data.rescheduleReasons || [];
        this.feedbackQuestionDefs = data.feedbackQuestions || [];
    }

    initializeVisit(v) {
        const images = (v.images || []).map((img, index) => ({
            key: v.id + '-img-' + index,
            url: img.url,
            index
        }));
        return { ...v, images, currentIndex: 0 };
    }

    extractErrorMessage(error) {
        if (!error) {
            return 'An unknown error occurred.';
        }
        if (typeof error === 'string') {
            return error;
        }
        if (error.body) {
            if (Array.isArray(error.body)) {
                return error.body.map((e) => e.message).filter(Boolean).join(', ');
            }
            if (typeof error.body.message === 'string') {
                return error.body.message;
            }
            if (error.body.pageErrors && error.body.pageErrors.length) {
                return error.body.pageErrors.map((e) => e.message).join(', ');
            }
            if (error.body.fieldErrors) {
                const msgs = [];
                Object.values(error.body.fieldErrors).forEach((list) => {
                    list.forEach((e) => msgs.push(e.message));
                });
                if (msgs.length) {
                    return msgs.join(', ');
                }
            }
        }
        if (typeof error.message === 'string') {
            return error.message;
        }
        return 'An unknown error occurred.';
    }

    showErrorToast(title, error) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message: this.extractErrorMessage(error),
                variant: 'error',
                mode: 'dismissible'
            })
        );
    }

    get showContent() {
        return !this.isLoading && !this.hasError;
    }

    get showScheduleButton() {
        return this.isUpcomingTab;
    }

    get isUpcomingTab() {
        return this.activeTab === 'upcoming';
    }

    get isCompletedTab() {
        return this.activeTab === 'completed';
    }

    get isIncompleteTab() {
        return this.activeTab === 'incomplete';
    }

    get upcomingTabClass() {
        return this.isUpcomingTab ? 'tab-btn tab-btn-active' : 'tab-btn';
    }

    get completedTabClass() {
        return this.isCompletedTab ? 'tab-btn tab-btn-active' : 'tab-btn';
    }

    get incompleteTabClass() {
        return this.isIncompleteTab ? 'tab-btn tab-btn-active' : 'tab-btn';
    }

    handleShowUpcoming() {
        this.activeTab = 'upcoming';
    }

    handleShowCompleted() {
        this.activeTab = 'completed';
    }

    handleShowIncomplete() {
        this.activeTab = 'incomplete';
    }

    get displayedUpcomingVisits() {
        return this.rawUpcoming.map((v) => this.decorateVisitForRender(v));
    }

    get displayedCompletedVisits() {
        return this.rawCompleted.map((v) => this.decorateVisitForRender(v));
    }

    get displayedIncompleteVisits() {
        return this.rawIncomplete.map((v) => this.decorateVisitForRender(v));
    }

    get hasNoUpcoming() {
        return this.rawUpcoming.length === 0;
    }

    get hasNoCompleted() {
        return this.rawCompleted.length === 0;
    }

    get hasNoIncomplete() {
        return this.rawIncomplete.length === 0;
    }

get isAnimatedSuccess() {
    return this.successType === 'cancel'
        || this.successType === 'schedule'
        || this.successType === 'reschedule'
         || this.successType === 'feedback';
}

get isFeedbackSuccess() {
    return this.successType === 'feedback';
}

    decorateVisitForRender(visit) {
        const total = visit.images.length;
        const decoratedImages = visit.images.map((img) => ({
            key: img.key,
            index: img.index,
            dotClass: img.index === visit.currentIndex ? 'carousel-dot carousel-dot-active' : 'carousel-dot'
        }));
        const activeImage = visit.images[visit.currentIndex] || visit.images[0];

        return {
            ...visit,
            images: decoratedImages,
            activeImageUrl: activeImage ? activeImage.url : '',
            showDots: total > 1,
            showArrows: total > 1
        };
    }

    getListArray(listName) {
        if (listName === 'upcoming') return this.rawUpcoming;
        if (listName === 'completed') return this.rawCompleted;
        return this.rawIncomplete;
    }

    setListArray(listName, updated) {
        if (listName === 'upcoming') {
            this.rawUpcoming = updated;
        } else if (listName === 'completed') {
            this.rawCompleted = updated;
        } else {
            this.rawIncomplete = updated;
        }
    }

    setVisitImageIndex(listName, visitId, newIndex) {
        const list = this.getListArray(listName);
        const updated = list.map((v) => (v.id === visitId ? { ...v, currentIndex: newIndex } : v));
        this.setListArray(listName, updated);
    }

    handleDotClick(event) {
        const { visitId, list, index } = event.currentTarget.dataset;
        this.setVisitImageIndex(list, visitId, parseInt(index, 10));
    }

    handlePrevImage(event) {
        const { visitId, list } = event.currentTarget.dataset;
        const visit = this.getListArray(list).find((v) => v.id === visitId);
        if (!visit) return;
        const total = visit.images.length;
        const newIndex = (visit.currentIndex - 1 + total) % total;
        this.setVisitImageIndex(list, visitId, newIndex);
    }

    handleNextImage(event) {
        const { visitId, list } = event.currentTarget.dataset;
        const visit = this.getListArray(list).find((v) => v.id === visitId);
        if (!visit) return;
        const total = visit.images.length;
        const newIndex = (visit.currentIndex + 1) % total;
        this.setVisitImageIndex(list, visitId, newIndex);
    }

    // ---------------------------------------------------------------
    // Property-details card used inside Cancel / Reschedule modals
    // ---------------------------------------------------------------

    get selectedVisitImageUrl() {
        return this.selectedVisit && this.selectedVisit.images && this.selectedVisit.images.length
            ? this.selectedVisit.images[0].url
            : '';
    }

    handleOpenScheduleModal() {
        this.scheduleForm = { project: '', unit: '', visitDate: '', visitTime: '', visitType: '', visitDetails: '' };
        this.isScheduleModalOpen = true;
    }

    handleOpenRescheduleModal(event) {
        const visitId = event.currentTarget.dataset.visitId;
        this.selectedVisit = this.rawUpcoming.find((v) => v.id === visitId);
        this.rescheduleForm = { visitDate: '', visitTime: '', reason: '', visitDetails: '' };
        this.isRescheduleModalOpen = true;
    }

    handleOpenCancelModal(event) {
        const visitId = event.currentTarget.dataset.visitId;
        this.selectedVisit = this.rawUpcoming.find((v) => v.id === visitId);
        this.cancelForm = { reason: '' };
        this.isCancelModalOpen = true;
    }

    handleOpenFeedbackModal(event) {
        const visitId = event.currentTarget.dataset.visitId;
        this.selectedVisit = this.rawCompleted.find((v) => v.id === visitId);
        this.feedbackRatings = { q1: 0, q2: 0, q3: 0, q4: 0, q5: 0 };
        this.isFeedbackModalOpen = true;
    }

    handleCloseModals() {
        this.isScheduleModalOpen = false;
        this.isRescheduleModalOpen = false;
        this.isCancelModalOpen = false;
        this.isFeedbackModalOpen = false;
        this.selectedVisit = undefined;
    }

    handleActionResponse(response) {
        if (response && response.success === false) {
            this.showErrorToast('Request failed', response.message || 'Something went wrong. Please try again.');
            return;
        }
        this.showSuccess(response.title, response.message);
    }

    showSuccess(title, message, type) {
        this.handleCloseModals();
        this.successTitle = title;
        this.successMessage = message;
        this.successType = type || 'generic';
        this.isSuccessModalOpen = true;
    }

    handleCloseSuccessModal() {
    this.isSuccessModalOpen = false;
    this.successTitle = '';
    this.successMessage = '';
    this.successType = 'generic';
}

    handleOverlayClick() {
        if (this.isSuccessModalOpen) {
            this.handleCloseSuccessModal();
        } else {
            this.handleCloseModals();
        }
    }

    stopPropagation(event) {
        event.stopPropagation();
    }

    handleScheduleFieldChange(event) {
        const field = event.currentTarget.dataset.field;
        this.scheduleForm = { ...this.scheduleForm, [field]: event.currentTarget.value };
    }

    get isScheduleDisabled() {
        const f = this.scheduleForm;
        return this.isSubmitting || !f.project || !f.unit || !f.visitDate || !f.visitTime || !f.visitType;
    }

    async handleSubmitSchedule() {
    if (this.isScheduleDisabled) return;
    this.isSubmitting = true;
    try {
        const response = await scheduleVisit({
            projectName: this.scheduleForm.project,
            unitNumber: this.scheduleForm.unit,
            visitDate: this.scheduleForm.visitDate,
            visitTime: this.scheduleForm.visitTime,
            visitType: this.scheduleForm.visitType,
            visitDetails: this.scheduleForm.visitDetails
        });
        if (response && response.success === false) {
            this.showErrorToast('Request failed', response.message || 'Something went wrong. Please try again.');
        } else {
            this.showSuccess(response.title, response.message, 'schedule');
        }
    } catch (error) {
        console.error('Error scheduling visit', error);
        this.showErrorToast('Unable to schedule visit', error);
    } finally {
        this.isSubmitting = false;
    }
}

    handleRescheduleFieldChange(event) {
        const field = event.currentTarget.dataset.field;
        this.rescheduleForm = { ...this.rescheduleForm, [field]: event.currentTarget.value };
    }

    get isRescheduleDisabled() {
        const f = this.rescheduleForm;
        return this.isSubmitting || !f.visitDate || !f.visitTime || !f.reason;
    }

   async handleSubmitReschedule() {
    if (this.isRescheduleDisabled || !this.selectedVisit) return;
    this.isSubmitting = true;
    try {
        const response = await rescheduleVisit({
            visitId: this.selectedVisit.id,
            property: this.selectedVisit.projectName,
            visitDate: this.rescheduleForm.visitDate,
            visitTime: this.rescheduleForm.visitTime,
            reason: this.rescheduleForm.reason,
            visitDetails: this.rescheduleForm.visitDetails
        });
        if (response && response.success === false) {
            this.showErrorToast('Request failed', response.message || 'Something went wrong. Please try again.');
        } else {
            this.showSuccess(response.title, response.message, 'reschedule');
        }
    } catch (error) {
        console.error('Error rescheduling visit', error);
        this.showErrorToast('Unable to reschedule visit', error);
    } finally {
        this.isSubmitting = false;
    }
}

    handleCancelFieldChange(event) {
        const field = event.currentTarget.dataset.field;
        this.cancelForm = { ...this.cancelForm, [field]: event.currentTarget.value };
    }

    get isCancelDisabled() {
        return this.isSubmitting || !this.cancelForm.reason || !this.cancelForm.reason.trim();
    }

    async handleSubmitCancel() {
    if (this.isCancelDisabled || !this.selectedVisit) return;
    this.isSubmitting = true;
    try {
        const response = await cancelVisit({
            visitId: this.selectedVisit.id,
            projectName: this.selectedVisit.projectName,
            cancellationReason: this.cancelForm.reason
        });
        if (response && response.success === false) {
            this.showErrorToast('Request failed', response.message || 'Something went wrong. Please try again.');
        } else {
            this.showSuccess(
                'Your upcoming visit has been cancelled successfully!',
                response.message,
                'cancel'
            );
        }
    } catch (error) {
        console.error('Error cancelling visit', error);
        this.showErrorToast('Unable to cancel visit', error);
    } finally {
        this.isSubmitting = false;
    }
}

    get feedbackQuestions() {
        return this.feedbackQuestionDefs.map((def) => {
            const currentRating = this.feedbackRatings[def.id];
            const stars = [1, 2, 3, 4, 5].map((value) => ({
                value,
                starClass: value <= currentRating ? 'star star-filled' : 'star'
            }));
            return { ...def, stars };
        });
    }

    handleStarClick(event) {
        const questionId = event.currentTarget.dataset.questionId;
        const value = parseInt(event.currentTarget.dataset.value, 10);
        this.feedbackRatings = { ...this.feedbackRatings, [questionId]: value };
    }

    get isFeedbackDisabled() {
        const r = this.feedbackRatings;
        return this.isSubmitting || !r.q1 || !r.q2 || !r.q3 || !r.q4 || !r.q5;
    }

    async handleSubmitFeedback() {
    if (this.isFeedbackDisabled || !this.selectedVisit) return;
    this.isSubmitting = true;
    try {
        const response = await submitVisitFeedback({
            visitId: this.selectedVisit.id,
            rating1: this.feedbackRatings.q1,
            rating2: this.feedbackRatings.q2,
            rating3: this.feedbackRatings.q3,
            rating4: this.feedbackRatings.q4,
            rating5: this.feedbackRatings.q5
        });
        if (response && response.success === false) {
            this.showErrorToast('Request failed', response.message || 'Something went wrong. Please try again.');
        } else {
            this.showSuccess(response.title, response.message, 'feedback');
        }
    } catch (error) {
        console.error('Error submitting feedback', error);
        this.showErrorToast('Unable to submit feedback', error);
    } finally {
        this.isSubmitting = false;
    }
}

    handleRetry() {
        this.hasError = false;
        this.isLoading = true;
        getMyVisitsPageData()
            .then((data) => {
                this.isLoading = false;
                this.applyPageData(data);
            })
            .catch((error) => {
                this.isLoading = false;
                this.hasError = true;
                console.error('Retry failed', error);
                this.showErrorToast('Unable to load visits', error);
            });
    }
}