import { LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import CP_ASSETS from '@salesforce/resourceUrl/customerPortalAssets';
import getEvents from '@salesforce/apex/CustomerPortalController.getEvents';
import registerForEvent from '@salesforce/apex/CustomerPortalController.registerForEvent';

// Visible text (Figma pages 85-87). Events and the registration text come from Apex.
const LABELS = {
    title: 'Events', // read by screen readers only: Figma p85 shows the cards without a page title
    loading: 'Loading events...',
    loadError: 'Something went wrong while loading events. Please try again.',
    retry: 'Retry',
    empty: 'No upcoming events available.',
    register: 'Register Now',
    registering: 'Registering...',
    registered: 'Registered',
    close: 'Close',
    // used only when Apex returns no title / message (Figma p86 wording)
    successTitle: 'Registration Complete',
    successMessage:
        'Congratulations! You are registered for the event. Please find the event details on your registered email ID.',
    errorTitle: 'Error',
    errorMessage: 'Unable to register for the event. Please try again.'
};

// Traced from the Figma PDF (p85): calendar and location pin of the card; close X as in the shared modal
const ICONS = {
    calendar:
        'M4.5 8.5C5.05 8.5 5.5 8.05 5.5 7.5C5.5 6.95 5.05 6.5 4.5 6.5C3.95 6.5 3.5 6.95 3.5 7.5C3.5 8.05 3.95 8.5 4.5 8.5Z' +
        'M5.5 10.5C5.5 11.05 5.05 11.5 4.5 11.5C3.95 11.5 3.5 11.05 3.5 10.5C3.5 9.95 3.95 9.5 4.5 9.5C5.05 9.5 5.5 9.95 5.5 10.5Z' +
        'M7.5 8.5C8.05 8.5 8.5 8.05 8.5 7.5C8.5 6.95 8.05 6.5 7.5 6.5C6.95 6.5 6.5 6.95 6.5 7.5C6.5 8.05 6.95 8.5 7.5 8.5Z' +
        'M8.5 10.5C8.5 11.05 8.05 11.5 7.5 11.5C6.95 11.5 6.5 11.05 6.5 10.5C6.5 9.95 6.95 9.5 7.5 9.5C8.05 9.5 8.5 9.95 8.5 10.5Z' +
        'M10.5 8.5C11.05 8.5 11.5 8.05 11.5 7.5C11.5 6.95 11.05 6.5 10.5 6.5C9.95 6.5 9.5 6.95 9.5 7.5C9.5 8.05 9.95 8.5 10.5 8.5Z' +
        'M14.5 3C14.5 1.62 13.38 0.5 12 0.5L3 0.5C1.62 0.5 0.5 1.62 0.5 3L0.5 12C0.5 13.38 1.62 14.5 3 14.5L12 14.5C13.38 14.5 ' +
        '14.5 13.38 14.5 12L14.5 3ZM1.5 4.5L13.5 4.5L13.5 12C13.5 12.83 12.83 13.5 12 13.5L3 13.5C2.17 13.5 1.5 12.83 1.5 12' +
        'L1.5 4.5ZM3 1.5L12 1.5C12.83 1.5 13.5 2.17 13.5 3L13.5 3.5L1.5 3.5L1.5 3C1.5 2.17 2.17 1.5 3 1.5Z',
    pin:
        'M11.2 8.2C11.2 9.86 9.86 11.2 8.2 11.2C6.54 11.2 5.2 9.86 5.2 8.2C5.2 6.54 6.54 5.2 8.2 5.2C9.86 5.2 11.2 6.54 11.2 8.2Z' +
        'M10.2 8.2C10.2 7.1 9.3 6.2 8.2 6.2C7.1 6.2 6.2 7.1 6.2 8.2C6.2 9.3 7.1 10.2 8.2 10.2C9.3 10.2 10.2 9.3 10.2 8.2Z' +
        'M13.15 13.15C15.88 10.42 15.88 5.99 13.15 3.25C10.42 0.52 5.98 0.52 3.25 3.25C0.52 5.99 0.52 10.42 3.25 13.15' +
        'L4.77 14.65L6.81 16.64L6.95 16.76C7.72 17.38 8.86 17.35 9.59 16.64L12.02 14.27L13.15 13.15Z' +
        'M3.96 3.96C6.3 1.61 10.1 1.61 12.44 3.96C14.73 6.24 14.79 9.91 12.62 12.27L12.44 12.45L11.12 13.75L8.89 15.92' +
        'L8.8 16C8.45 16.27 7.95 16.27 7.6 16L7.51 15.92L4.53 13.02L3.96 12.45L3.78 12.27C1.61 9.91 1.67 6.24 3.96 3.96Z',
    close: 'M14 1.41L12.59 0L7 5.59L1.41 0L0 1.41L5.59 7L0 12.59L1.41 14L7 8.41L12.59 14L14 12.59L8.41 7L14 1.41Z'
};

export default class CustomerPortal_Events extends LightningElement {
    labels = LABELS;
    icons = ICONS;
    emptyImageUrl = CP_ASSETS + '/empty-state.svg';
    successImageUrl = CP_ASSETS + '/success-calendar.png';

    isLoading = true;
    hasError = false;
    events = [];
    registeringId = null;

    isSuccessModalOpen = false;
    successTitle = '';
    successMessage = '';

    // move focus into the popup once it has rendered
    focusModalPending = false;
    overlayPointerDown = false;

    wiredResult;

    @wire(getEvents)
    wiredEvents(result) {
        this.wiredResult = result;
        const { data, error } = result;
        if (data) {
            this.isLoading = false;
            this.hasError = false;
            this.events = data;
        } else if (error) {
            this.isLoading = false;
            this.hasError = true;
            console.error('Error loading events', error);
        }
    }

    renderedCallback() {
        if (this.focusModalPending) {
            const panel = this.template.querySelector('.cp-modal');
            if (panel) {
                this.focusModalPending = false;
                panel.focus();
            }
        }
    }

    handleRetry() {
        this.hasError = false;
        this.isLoading = true;
        refreshApex(this.wiredResult).catch((error) => {
            this.isLoading = false;
            this.hasError = true;
            console.error('Retry failed', error);
        });
    }

    get showContent() {
        return !this.isLoading && !this.hasError;
    }

    get hasNoEvents() {
        return this.events.length === 0;
    }

    // Figma p85 (Register Now) / p87 (Registered, grey)
    get eventCards() {
        return this.events.map((e) => {
            const isRegistering = this.registeringId === e.id;
            let buttonLabel = LABELS.register;
            if (e.isRegistered) {
                buttonLabel = LABELS.registered;
            } else if (isRegistering) {
                buttonLabel = LABELS.registering;
            }
            return {
                ...e,
                timeRange: [e.startTime, e.endTime].filter(Boolean).join(' - '),
                buttonLabel,
                isDisabled: !!e.isRegistered || !!this.registeringId,
                buttonClass: e.isRegistered
                    ? 'cp-btn cp-btn_block ev-register ev-register_done'
                    : 'cp-btn cp-btn_block ev-register'
            };
        });
    }

    async handleRegister(event) {
        if (this.registeringId) return;

        const eventId = event.currentTarget.dataset.eventId;
        const selected = this.events.find((e) => e.id === eventId);
        if (!selected || selected.isRegistered) return;

        this.registeringId = eventId;
        try {
            const response = await registerForEvent({
                eventId: selected.id,
                eventTitle: selected.title,
                eventDate: selected.eventDate,
                startTime: selected.startTime,
                endTime: selected.endTime,
                eventLocation: selected.location
            });

            if (response && response.success === false) {
                this.showErrorToast();
                return;
            }

            this.events = this.events.map((e) =>
                (e.id === eventId ? { ...e, isRegistered: !!(response && response.isRegistered) } : e)
            );

            // Figma p86: "Registration Complete" popup
            this.successTitle = (response && response.title) || LABELS.successTitle;
            this.successMessage = (response && response.message) || LABELS.successMessage;
            this.isSuccessModalOpen = true;
            this.focusModalPending = true;
        } catch (error) {
            console.error('Error registering for event', error);
            this.showErrorToast();
        } finally {
            this.registeringId = null;
        }
    }

    handleCloseSuccessModal() {
        this.isSuccessModalOpen = false;
    }

    // close on a click on the dimmed overlay only
    handleOverlayMouseDown(event) {
        this.overlayPointerDown = event.target === event.currentTarget;
    }

    handleOverlayClick(event) {
        const onOverlay = event.target === event.currentTarget && this.overlayPointerDown;
        this.overlayPointerDown = false;
        if (onOverlay) {
            this.handleCloseSuccessModal();
        }
    }

    handleModalKeydown(event) {
        if (event.key === 'Escape' || event.key === 'Esc') {
            event.stopPropagation();
            this.handleCloseSuccessModal();
        }
    }

    showErrorToast() {
        this.dispatchEvent(
            new ShowToastEvent({
                title: LABELS.errorTitle,
                message: LABELS.errorMessage,
                variant: 'error'
            })
        );
    }
}