import { LightningElement, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import CP_ASSETS from '@salesforce/resourceUrl/customerPortalAssets';
import getMyVisitsPageData from '@salesforce/apex/CustomerPortalController.getMyVisitsPageData';
import scheduleVisit from '@salesforce/apex/CustomerPortalController.scheduleVisit';
import rescheduleVisit from '@salesforce/apex/CustomerPortalController.rescheduleVisit';
import cancelVisit from '@salesforce/apex/CustomerPortalController.cancelVisit';
import submitVisitFeedback from '@salesforce/apex/CustomerPortalController.submitVisitFeedback';
import { FOLLOW_UP_ART, FOLLOW_UP_ART_VIEWBOX } from './followUpArt';

// Visible text (Figma "Customer Portal" pages 29-46). Plain constants, no Custom Labels.
const LABELS = {
    pageTitle: 'Visits for Handover',
    loading: 'Loading your visits...',
    loadError: 'Something went wrong while loading your visits. Please try again later.',
    retry: 'Retry',
    scheduleVisit: 'Schedule Visit',
    tabsLabel: 'Site visits',
    tabUpcoming: 'Upcoming Site Visits',
    tabCompleted: 'Completed Site Visits',
    tabIncomplete: 'Cancelled Site Visits',
    emptyUpcoming: 'You have no upcoming site visits.',
    emptyCompleted: 'You have no completed site visits.',
    emptyIncomplete: 'You have no cancelled site visits.',
    factVisitDate: 'Visit Date:',
    factCompletedDate: 'Visit Completed Date:',
    factCancelledDate: 'Visit Cancelled Date:',
    factVisitTime: 'Visit Time:',
    factCompletedTime: 'Visit Completed Time:',
    factCancelledTime: 'Visit Cancelled Time:',
    factSalesOrder: 'Sales Order No.:',
    factUnitNumber: 'Unit Number:',
    factCustomerId: 'Customer ID:',
    factHandoverPerson: 'CRM/Handover Person:',
    factComments: 'Comments:',
    cancelVisit: 'Cancel Visit',
    reschedule: 'Reschedule',
    giveFeedback: 'Give Feedback',
    followUpVisit: 'Follow Up Visit',
    previousImage: 'Previous image',
    nextImage: 'Next image',
    showImage: 'Show image',
    close: 'Close',
    propertyDetails: 'Property Details',
    dateOfVisit: 'Date Of Visit',
    timeOfVisit: 'Time Of Visit',
    selectDate: 'Select Date Of Visit',
    selectTime: 'Select Time Of Visit',
    visitDetails: 'Visit Details',
    scheduleTitle: 'Schedule a Visit',
    scheduleText: 'Please select a appointment time that works better for you.',
    selectProperty: 'Select Property',
    selectUnit: 'Select Unit',
    visitType: 'Visit Type',
    selectVisitType: 'Select Visit Type',
    visitDetailsPlaceholder: 'Write the Purpose of rescheduling your visit',
    scheduleNow: 'Schedule Now',
    rescheduleTitle: 'Reschedule Visit',
    rescheduleText: 'Please select a new appointment time that works better for you.',
    rescheduleReason: 'Reason for Reschedule',
    selectRescheduleReason: 'Select Reason for reschedule',
    confirmReschedule: 'Confirm Reschedule',
    cancelTitle: 'Cancel Visit',
    cancelText:
        'If you have any questions or need further assistance, please feel free to reach out to us. We apologize for any inconvenience caused!',
    cancelReason: 'Reason for Cancellation',
    cancelReasonPlaceholder:
        'Understanding the reason helps us to improve services and may offer insights into customer needs.',
    feedbackTitle: 'Feedback Form',
    feedbackText:
        'Your feedback is essential to help us continually improve our services. Please take a moment to share your thoughts with us.',
    feedbackCancel: 'Cancel',
    feedbackSubmit: 'Submit your experience',
    starOutOf: 'out of 5',
    followUpTitle: 'Follow Up Visit',
    followUpText:
        'We understand you would like to visit the property again with John Keels Properties . Please select your preferred date and time for the visit, and we will arrange it accordingly. We look forward to showing you the property once more.',
    infoProperty: 'Property:',
    infoType: 'Type:',
    infoAddress: 'Address:',
    infoLocation: 'Location:',
    purposeOfVisit: 'Purpose Of Visit',
    selectPurpose: 'Select Purpose of Visit',
    purposePlaceholder: 'Write the Purpose of visit',
    cancelSuccessTitle: 'Your upcoming visit has been cancelled successfully!',
    followUpSuccessTitle: 'Your Follow Up Visit has been Scheduled!',
    followUpSuccessMessage:
        'Your Follow up visit to {project} has been Scheduled on {date} at {time}. If you have any questions or need further assistance, please don’t hesitate to contact us.',
    toastLoadTitle: 'Unable to load visits',
    toastRequestFailed: 'Request failed',
    toastTryAgain: 'Something went wrong. Please try again.',
    toastSchedule: 'Unable to schedule visit',
    toastReschedule: 'Unable to reschedule visit',
    toastCancel: 'Unable to cancel visit',
    toastFeedback: 'Unable to submit feedback',
    toastFollowUp: 'Unable to schedule the follow up visit',
    unknownError: 'An unknown error occurred.'
};

const TABS = [
    { value: 'upcoming', labelKey: 'tabUpcoming' },
    { value: 'completed', labelKey: 'tabCompleted' },
    { value: 'incomplete', labelKey: 'tabIncomplete' }
];

// Card detail lines per tab: [Visit field, label key] (Figma p29 / p30 / p31)
const FACTS = {
    upcoming: [
        ['visitDate', 'factVisitDate'],
        ['visitTime', 'factVisitTime'],
        ['bookingId', 'factSalesOrder'],
        ['unitNumber', 'factUnitNumber'],
        ['customerId', 'factCustomerId'],
        ['crmHandoverPerson', 'factHandoverPerson']
    ],
    completed: [
        ['visitDate', 'factVisitDate'],
        ['completedDate', 'factCompletedDate'],
        ['visitTime', 'factVisitTime'],
        ['completedTime', 'factCompletedTime'],
        ['bookingId', 'factSalesOrder'],
        ['unitNumber', 'factUnitNumber'],
        ['customerId', 'factCustomerId'],
        ['crmHandoverPerson', 'factHandoverPerson'],
        ['comments', 'factComments']
    ],
    incomplete: [
        ['visitDate', 'factVisitDate'],
        ['cancelledDate', 'factCancelledDate'],
        ['visitTime', 'factVisitTime'],
        ['cancelledTime', 'factCancelledTime'],
        ['bookingId', 'factSalesOrder'],
        ['unitNumber', 'factUnitNumber'],
        ['customerId', 'factCustomerId'],
        ['crmHandoverPerson', 'factHandoverPerson'],
        ['comments', 'factComments']
    ]
};

// Icons traced from the Figma PDF (pdf2svg), drawn with fill="currentColor"
const ICONS = {
    close: 'M14 1.41L12.59 0L7 5.59L1.41 0L0 1.41L5.59 7L0 12.59L1.41 14L7 8.41L12.59 14L14 12.59L8.41 7L14 1.41Z',
    calendar:
        'M14.75 0C16.54 0 18 1.46 18 3.25L18 14.75C18 16.54 16.54 18 14.75 18L3.25 18C1.46 18 0 16.54 0 14.75L0 3.25C0 1.46 1.46 0 3.25 0L14.75 0ZM16.5 5.5L1.5 5.5L1.5 14.75C1.5 15.72 2.28 16.5 3.25 16.5L14.75 16.5C15.72 16.5 16.5 15.72 16.5 14.75L16.5 5.5ZM4.75 11.5C5.44 11.5 6 12.06 6 12.75C6 13.44 5.44 14 4.75 14C4.06 14 3.5 13.44 3.5 12.75C3.5 12.06 4.06 11.5 4.75 11.5ZM9 11.5C9.69 11.5 10.25 12.06 10.25 12.75C10.25 13.44 9.69 14 9 14C8.31 14 7.75 13.44 7.75 12.75C7.75 12.06 8.31 11.5 9 11.5ZM4.75 7.5C5.44 7.5 6 8.06 6 8.75C6 9.44 5.44 10 4.75 10C4.06 10 3.5 9.44 3.5 8.75C3.5 8.06 4.06 7.5 4.75 7.5ZM9 7.5C9.69 7.5 10.25 8.06 10.25 8.75C10.25 9.44 9.69 10 9 10C8.31 10 7.75 9.44 7.75 8.75C7.75 8.06 8.31 7.5 9 7.5ZM13.25 7.5C13.94 7.5 14.5 8.06 14.5 8.75C14.5 9.44 13.94 10 13.25 10C12.56 10 12 9.44 12 8.75C12 8.06 12.56 7.5 13.25 7.5ZM14.75 1.5L3.25 1.5C2.28 1.5 1.5 2.28 1.5 3.25L1.5 4L16.5 4L16.5 3.25C16.5 2.28 15.72 1.5 14.75 1.5Z',
    clock:
        'M1.5 10C1.5 5.31 5.31 1.5 10 1.5C14.69 1.5 18.5 5.31 18.5 10C18.5 14.69 14.69 18.5 10 18.5C5.31 18.5 1.5 14.69 1.5 10ZM10 0C4.48 0 0 4.48 0 10C0 15.52 4.48 20 10 20C15.52 20 20 15.52 20 10C20 4.48 15.52 0 10 0ZM9.99 4.65C9.94 4.28 9.63 4 9.25 4C8.84 4 8.5 4.34 8.5 4.75L8.5 10.75L8.51 10.85C8.56 11.22 8.87 11.5 9.25 11.5L13.25 11.5L13.35 11.49C13.72 11.44 14 11.13 14 10.75C14 10.34 13.66 10 13.25 10L10 10L10 4.75L9.99 4.65Z',
    starOutline:
        'M11.86 1.23C12.46 0 14.22 0 14.83 1.23L17.9 7.46L24.78 8.46C26.14 8.65 26.68 10.33 25.7 11.28L20.72 16.13L21.9 22.98C22.13 24.34 20.71 25.37 19.49 24.73L13.34 21.5L7.19 24.73C5.97 25.37 4.55 24.34 4.79 22.98L5.96 16.13L0.98 11.28C0 10.33 0.54 8.65 1.9 8.46L8.78 7.46L11.86 1.23ZM13.34 2.09L10.3 8.24C10.06 8.73 9.6 9.07 9.06 9.15L2.26 10.14L7.18 14.93C7.57 15.31 7.75 15.86 7.66 16.39L6.5 23.16L12.57 19.97C13.05 19.71 13.63 19.71 14.11 19.97L20.19 23.16L19.03 16.39C18.94 15.86 19.11 15.31 19.5 14.93L24.42 10.14L17.63 9.15C17.09 9.07 16.62 8.73 16.38 8.24L13.34 2.09Z',
    starFilled:
        'M11.86 1.23C12.46 0 14.22 0 14.83 1.23L17.9 7.46L24.78 8.46C26.14 8.65 26.68 10.33 25.7 11.28L20.72 16.13L21.9 22.98C22.13 24.34 20.71 25.37 19.49 24.73L13.34 21.5L7.19 24.73C5.97 25.37 4.55 24.34 4.79 22.98L5.96 16.13L0.98 11.28C0 10.33 0.54 8.65 1.9 8.46L8.78 7.46L11.86 1.23Z'
};

const EMPTY_SCHEDULE_FORM = { project: '', unit: '', visitDate: '', visitTime: '', visitType: '', visitDetails: '' };
const EMPTY_RESCHEDULE_FORM = { visitDate: '', visitTime: '', reason: '', visitDetails: '' };
const EMPTY_FOLLOW_UP_FORM = { visitDate: '', visitTime: '', purpose: '', visitDetails: '' };

// 'YYYY-MM-DD' (date input value) -> 'DD/MM/YYYY' as in Figma
function formatDate(value) {
    const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value || '');
    return match ? match[3] + '/' + match[2] + '/' + match[1] : value || '';
}

// 'HH:mm' / 'HH:mm:ss' (time input value) -> 'hh:mm AM' as in Figma
function formatTime(value) {
    const match = /^(\d{1,2}):(\d{2})/.exec(value || '');
    if (!match) {
        return value || '';
    }
    const hours = parseInt(match[1], 10);
    const shown = hours % 12 || 12;
    return (shown < 10 ? '0' : '') + shown + ':' + match[2] + ' ' + (hours >= 12 ? 'PM' : 'AM');
}

function pickerView(value, formatter, placeholder) {
    return {
        text: value ? formatter(value) : placeholder,
        className: value ? 'visit-picker visit-picker_filled' : 'visit-picker'
    };
}

function selectClass(value) {
    return value ? 'cp-select visit-select' : 'cp-select visit-select visit-select_empty';
}

export default class CustomerPortal_MyVisits extends LightningElement {
    @track isLoading = true;
    @track hasError = false;
    @track pageTitle = LABELS.pageTitle;
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
    successType = 'generic'; // 'generic' | 'schedule' | 'reschedule' | 'cancel' | 'feedback' | 'followUp'

    isScheduleModalOpen = false;
    isRescheduleModalOpen = false;
    isCancelModalOpen = false;
    isFeedbackModalOpen = false;
    isFollowUpModalOpen = false;
    isSuccessModalOpen = false;
    successTitle = '';
    successMessage = '';
    @track selectedVisit;

    // ---- form state ----
    @track scheduleForm = { ...EMPTY_SCHEDULE_FORM };
    @track rescheduleForm = { ...EMPTY_RESCHEDULE_FORM };
    @track cancelForm = { reason: '' };
    @track feedbackRatings = { q1: 0, q2: 0, q3: 0, q4: 0, q5: 0 };
    @track followUpForm = { ...EMPTY_FOLLOW_UP_FORM };

    isSubmitting = false;

    // photo urls that failed to load (the card then shows the grey photo area instead of a broken image)
    brokenImages = {};

    labels = LABELS;
    icons = ICONS;
    emptyImageUrl = CP_ASSETS + '/empty-state.svg';
    followUpArt = FOLLOW_UP_ART;
    followUpArtViewBox = FOLLOW_UP_ART_VIEWBOX;

    focusModalPending = false;
    lastTrigger;

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
            this.showErrorToast(LABELS.toastLoadTitle, error);
        }
    }

    applyPageData(data) {
        this.pageTitle = data.pageTitle || LABELS.pageTitle;
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
            return LABELS.unknownError;
        }
        if (typeof error === 'string') {
            return error;
        }
        if (error.body) {
            if (Array.isArray(error.body)) {
                return error.body
                    .map((e) => e.message)
                    .filter(Boolean)
                    .join(', ');
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
        return LABELS.unknownError;
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

    renderedCallback() {
        if (this.focusModalPending) {
            const dialog = this.template.querySelector('.cp-modal');
            if (dialog) {
                this.focusModalPending = false;
                dialog.focus();
            }
        }
    }

    get showContent() {
        return !this.isLoading && !this.hasError;
    }

    get showScheduleButton() {
        return this.isUpcomingTab;
    }

    // ---------------------------------------------------------------
    // Tabs
    // ---------------------------------------------------------------

    get isUpcomingTab() {
        return this.activeTab === 'upcoming';
    }

    get isCompletedTab() {
        return this.activeTab === 'completed';
    }

    get isIncompleteTab() {
        return this.activeTab === 'incomplete';
    }

    get tabs() {
        return TABS.map((tab) => {
            const active = tab.value === this.activeTab;
            return {
                value: tab.value,
                label: LABELS[tab.labelKey],
                className: active ? 'cp-tab cp-tab_active visit-tab' : 'cp-tab visit-tab',
                ariaSelected: active ? 'true' : 'false',
                tabIndex: active ? '0' : '-1'
            };
        });
    }

    handleTabClick(event) {
        this.activeTab = event.currentTarget.dataset.tab;
    }

    handleTabKeydown(event) {
        const keys = ['ArrowLeft', 'ArrowRight', 'Home', 'End'];
        if (!keys.includes(event.key)) {
            return;
        }
        event.preventDefault();
        const current = TABS.findIndex((tab) => tab.value === this.activeTab);
        let next = current;
        if (event.key === 'ArrowLeft') {
            next = (current - 1 + TABS.length) % TABS.length;
        } else if (event.key === 'ArrowRight') {
            next = (current + 1) % TABS.length;
        } else if (event.key === 'Home') {
            next = 0;
        } else {
            next = TABS.length - 1;
        }
        this.activeTab = TABS[next].value;
        // move focus with the selection (roving tab index)
        Promise.resolve().then(() => {
            const button = this.template.querySelector('[data-tab="' + this.activeTab + '"]');
            if (button) {
                button.focus();
            }
        });
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

    // ---------------------------------------------------------------
    // Visit cards
    // ---------------------------------------------------------------

    get displayedUpcomingVisits() {
        return this.rawUpcoming.map((v) => this.decorateVisitForRender(v, 'upcoming'));
    }

    get displayedCompletedVisits() {
        return this.rawCompleted.map((v) => this.decorateVisitForRender(v, 'completed'));
    }

    get displayedIncompleteVisits() {
        return this.rawIncomplete.map((v) => this.decorateVisitForRender(v, 'incomplete'));
    }

    get visibleVisits() {
        if (this.isCompletedTab) {
            return this.displayedCompletedVisits;
        }
        if (this.isIncompleteTab) {
            return this.displayedIncompleteVisits;
        }
        return this.displayedUpcomingVisits;
    }

    get hasVisibleVisits() {
        return this.getListArray(this.activeTab).length > 0;
    }

    get emptyText() {
        if (this.isCompletedTab) {
            return LABELS.emptyCompleted;
        }
        if (this.isIncompleteTab) {
            return LABELS.emptyIncomplete;
        }
        return LABELS.emptyUpcoming;
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

    decorateVisitForRender(visit, listName) {
        const total = visit.images.length;
        const decoratedImages = visit.images.map((img) => {
            const active = img.index === visit.currentIndex;
            return {
                key: img.key,
                index: img.index,
                dotClass: active ? 'cp-dot cp-dot_active' : 'cp-dot',
                ariaCurrent: active ? 'true' : 'false',
                ariaLabel: LABELS.showImage + ' ' + (img.index + 1)
            };
        });
        const activeImage = visit.images[visit.currentIndex] || visit.images[0];
        const activeImageUrl = activeImage ? activeImage.url : '';
        const facts = (FACTS[listName] || FACTS.upcoming).map(([field, labelKey]) => ({
            key: field,
            label: LABELS[labelKey],
            value: visit[field]
        }));

        return {
            ...visit,
            images: decoratedImages,
            activeImageUrl,
            hasPhoto: Boolean(activeImageUrl) && !this.brokenImages[activeImageUrl],
            showDots: total > 1,
            showArrows: total > 1,
            facts,
            list: listName
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

    handleImageError(event) {
        const url = event.currentTarget.dataset.url;
        if (url && !this.brokenImages[url]) {
            this.brokenImages = { ...this.brokenImages, [url]: true };
        }
    }

    // ---------------------------------------------------------------
    // Property-details card used inside Cancel / Reschedule modals
    // ---------------------------------------------------------------

    get selectedVisitImageUrl() {
        return this.selectedVisit && this.selectedVisit.images && this.selectedVisit.images.length
            ? this.selectedVisit.images[0].url
            : '';
    }

    get selectedVisitHasPhoto() {
        const url = this.selectedVisitImageUrl;
        return Boolean(url) && !this.brokenImages[url];
    }

    get selectedVisitAddress() {
        if (!this.selectedVisit) {
            return '';
        }
        return this.selectedVisit.correspondenceAddress || this.selectedVisit.address;
    }

    // ---------------------------------------------------------------
    // Modals: open / close
    // ---------------------------------------------------------------

    rememberTrigger(event) {
        this.lastTrigger = event && event.currentTarget ? event.currentTarget : undefined;
        this.focusModalPending = true;
    }

    restoreFocus() {
        const trigger = this.lastTrigger;
        if (trigger && trigger.isConnected && typeof trigger.focus === 'function') {
            trigger.focus();
        }
    }

    handleOpenScheduleModal(event) {
        this.rememberTrigger(event);
        this.scheduleForm = { ...EMPTY_SCHEDULE_FORM };
        this.isScheduleModalOpen = true;
    }

    handleOpenRescheduleModal(event) {
        const visitId = event.currentTarget.dataset.visitId;
        this.rememberTrigger(event);
        this.selectedVisit = this.rawUpcoming.find((v) => v.id === visitId);
        this.rescheduleForm = { ...EMPTY_RESCHEDULE_FORM };
        this.isRescheduleModalOpen = true;
    }

    handleOpenCancelModal(event) {
        const visitId = event.currentTarget.dataset.visitId;
        this.rememberTrigger(event);
        this.selectedVisit = this.rawUpcoming.find((v) => v.id === visitId);
        this.cancelForm = { reason: '' };
        this.isCancelModalOpen = true;
    }

    handleOpenFeedbackModal(event) {
        const visitId = event.currentTarget.dataset.visitId;
        this.rememberTrigger(event);
        this.selectedVisit = this.rawCompleted.find((v) => v.id === visitId);
        this.feedbackRatings = { q1: 0, q2: 0, q3: 0, q4: 0, q5: 0 };
        this.isFeedbackModalOpen = true;
    }

    handleOpenFollowUpModal(event) {
        const visitId = event.currentTarget.dataset.visitId;
        this.rememberTrigger(event);
        this.selectedVisit = this.rawCompleted.find((v) => v.id === visitId);
        this.followUpForm = { ...EMPTY_FOLLOW_UP_FORM };
        this.isFollowUpModalOpen = true;
    }

    closeModalsOnly() {
        this.isScheduleModalOpen = false;
        this.isRescheduleModalOpen = false;
        this.isCancelModalOpen = false;
        this.isFeedbackModalOpen = false;
        this.isFollowUpModalOpen = false;
        this.selectedVisit = undefined;
    }

    handleCloseModals() {
        this.closeModalsOnly();
        this.restoreFocus();
    }

    handleActionResponse(response) {
        if (response && response.success === false) {
            this.showErrorToast(LABELS.toastRequestFailed, response.message || LABELS.toastTryAgain);
            return;
        }
        this.showSuccess(response.title, response.message);
    }

    showSuccess(title, message, type) {
        this.closeModalsOnly();
        this.successTitle = title;
        this.successMessage = message;
        this.successType = type || 'generic';
        this.isSuccessModalOpen = true;
        this.focusModalPending = true;
    }

    handleCloseSuccessModal() {
        this.isSuccessModalOpen = false;
        this.successTitle = '';
        this.successMessage = '';
        this.successType = 'generic';
        this.restoreFocus();
    }

    handleOverlayClick() {
        if (this.isSuccessModalOpen) {
            this.handleCloseSuccessModal();
        } else {
            this.handleCloseModals();
        }
    }

    handleModalKeydown(event) {
        if (event.key === 'Escape' || event.key === 'Esc') {
            event.preventDefault();
            event.stopPropagation();
            this.handleOverlayClick();
        }
    }

    stopPropagation(event) {
        event.stopPropagation();
    }

    // ---------------------------------------------------------------
    // Success screen
    // ---------------------------------------------------------------

    get isFollowUpSuccess() {
        return this.successType === 'followUp';
    }

    get successImageUrl() {
        return CP_ASSETS + (this.successType === 'feedback' ? '/success-feedback.png' : '/success-calendar.png');
    }

    get successModalClass() {
        return this.isFollowUpSuccess
            ? 'cp-modal cp-modal_lg visit-modal visit-modal_success visit-modal_success-art'
            : 'cp-modal cp-modal_lg visit-modal visit-modal_success';
    }

    // ---------------------------------------------------------------
    // Date / time pickers and selects (Figma placeholders and formats)
    // ---------------------------------------------------------------

    get pickers() {
        return {
            scheduleDate: pickerView(this.scheduleForm.visitDate, formatDate, LABELS.selectDate),
            scheduleTime: pickerView(this.scheduleForm.visitTime, formatTime, LABELS.selectTime),
            rescheduleDate: pickerView(this.rescheduleForm.visitDate, formatDate, LABELS.selectDate),
            rescheduleTime: pickerView(this.rescheduleForm.visitTime, formatTime, LABELS.selectTime),
            followUpDate: pickerView(this.followUpForm.visitDate, formatDate, LABELS.selectDate),
            followUpTime: pickerView(this.followUpForm.visitTime, formatTime, LABELS.selectTime)
        };
    }

    get selectClasses() {
        return {
            scheduleProject: selectClass(this.scheduleForm.project),
            scheduleUnit: selectClass(this.scheduleForm.unit),
            scheduleType: selectClass(this.scheduleForm.visitType),
            rescheduleReason: selectClass(this.rescheduleForm.reason),
            followUpPurpose: selectClass(this.followUpForm.purpose)
        };
    }

    handleOpenPicker(event) {
        const input = event.currentTarget;
        if (input && typeof input.showPicker === 'function') {
            try {
                input.showPicker();
            } catch (e) {
                // the browser does not allow it here; the field still opens or takes typing as usual
            }
        }
    }

    // ---------------------------------------------------------------
    // Schedule
    // ---------------------------------------------------------------

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
                this.showErrorToast(LABELS.toastRequestFailed, response.message || LABELS.toastTryAgain);
            } else {
                this.showSuccess(response.title, response.message, 'schedule');
            }
        } catch (error) {
            console.error('Error scheduling visit', error);
            this.showErrorToast(LABELS.toastSchedule, error);
        } finally {
            this.isSubmitting = false;
        }
    }

    // ---------------------------------------------------------------
    // Reschedule
    // ---------------------------------------------------------------

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
                this.showErrorToast(LABELS.toastRequestFailed, response.message || LABELS.toastTryAgain);
            } else {
                this.showSuccess(response.title, response.message, 'reschedule');
            }
        } catch (error) {
            console.error('Error rescheduling visit', error);
            this.showErrorToast(LABELS.toastReschedule, error);
        } finally {
            this.isSubmitting = false;
        }
    }

    // ---------------------------------------------------------------
    // Cancel
    // ---------------------------------------------------------------

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
                this.showErrorToast(LABELS.toastRequestFailed, response.message || LABELS.toastTryAgain);
            } else {
                this.showSuccess(LABELS.cancelSuccessTitle, response.message, 'cancel');
            }
        } catch (error) {
            console.error('Error cancelling visit', error);
            this.showErrorToast(LABELS.toastCancel, error);
        } finally {
            this.isSubmitting = false;
        }
    }

    // ---------------------------------------------------------------
    // Feedback
    // ---------------------------------------------------------------

    get feedbackQuestions() {
        return this.feedbackQuestionDefs.map((def) => {
            const currentRating = this.feedbackRatings[def.id];
            const stars = [1, 2, 3, 4, 5].map((value) => ({
                value,
                key: def.id + '-' + value,
                filled: value <= currentRating,
                starClass: value <= currentRating ? 'visit-star visit-star_filled' : 'visit-star',
                ariaPressed: value === currentRating ? 'true' : 'false',
                ariaLabel: value + ' ' + LABELS.starOutOf
            }));
            return { ...def, stars, prompt: def.questionNumber + '. ' + def.text };
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
                this.showErrorToast(LABELS.toastRequestFailed, response.message || LABELS.toastTryAgain);
            } else {
                this.showSuccess(response.title, response.message, 'feedback');
            }
        } catch (error) {
            console.error('Error submitting feedback', error);
            this.showErrorToast(LABELS.toastFeedback, error);
        } finally {
            this.isSubmitting = false;
        }
    }

    // ---------------------------------------------------------------
    // Follow up visit (Figma p43-46): a new visit to the same property and unit,
    // sent through the existing scheduleVisit action.
    // ---------------------------------------------------------------

    handleFollowUpFieldChange(event) {
        const field = event.currentTarget.dataset.field;
        this.followUpForm = { ...this.followUpForm, [field]: event.currentTarget.value };
    }

    get isFollowUpDisabled() {
        const f = this.followUpForm;
        return this.isSubmitting || !f.visitDate || !f.visitTime || !f.purpose;
    }

    async handleSubmitFollowUp() {
        if (this.isFollowUpDisabled || !this.selectedVisit) return;
        const visit = this.selectedVisit;
        const form = this.followUpForm;
        this.isSubmitting = true;
        try {
            const response = await scheduleVisit({
                projectName: visit.projectName,
                unitNumber: visit.unitNumber,
                visitDate: form.visitDate,
                visitTime: form.visitTime,
                visitType: form.purpose,
                visitDetails: form.visitDetails
            });
            if (response && response.success === false) {
                this.showErrorToast(LABELS.toastRequestFailed, response.message || LABELS.toastTryAgain);
            } else {
                const message = LABELS.followUpSuccessMessage
                    .replace('{project}', visit.projectName || '')
                    .replace('{date}', formatDate(form.visitDate))
                    .replace('{time}', formatTime(form.visitTime));
                this.showSuccess(LABELS.followUpSuccessTitle, message, 'followUp');
            }
        } catch (error) {
            console.error('Error scheduling follow up visit', error);
            this.showErrorToast(LABELS.toastFollowUp, error);
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
                this.showErrorToast(LABELS.toastLoadTitle, error);
            });
    }
}