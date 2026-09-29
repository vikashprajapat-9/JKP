import { LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getEvents from '@salesforce/apex/CustomerPortalController.getEvents';
import registerForEvent from '@salesforce/apex/CustomerPortalController.registerForEvent';

export default class CustomerPortal_Events extends LightningElement {
    isLoading = true;
    hasError = false;
    events = [];
    registeringId = null; 

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

    get eventCards() {
        return this.events.map((e) => {
            const isRegistering = this.registeringId === e.id;
            let buttonLabel = 'Register Now';
            if (e.isRegistered) {
                buttonLabel = 'Registered';
            } else if (isRegistering) {
                buttonLabel = 'Registering...';
            }
            return {
                ...e,
                timeRange: [e.startTime, e.endTime].filter(Boolean).join(' - '),
                buttonLabel,
                isDisabled: !!e.isRegistered || !!this.registeringId,
                buttonClass: e.isRegistered ? 'btn-register btn-registered' : 'btn-register'
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
                e.id === eventId ? { ...e, isRegistered: !!(response && response.isRegistered) } : e
            );

            this.dispatchEvent(
                new ShowToastEvent({
                    title: response.title,
                    message: response.message,
                    variant: 'success'
                })
            );
        } catch (error) {
            console.error('Error registering for event', error);
            this.showErrorToast();
        } finally {
            this.registeringId = null;
        }
    }

    showErrorToast() {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error',
                message: 'Unable to register for the event. Please try again.',
                variant: 'error'
            })
        );
    }
}