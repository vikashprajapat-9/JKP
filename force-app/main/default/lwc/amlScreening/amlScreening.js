import { LightningElement, api } from 'lwc';
import submitScreening from '@salesforce/apex/AMLScreeningController.submitScreening';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';

export default class AmlScreeningRunner extends LightningElement {
    _recordId;
    _objectApiName;
    hasStarted = false;

    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        this._recordId = value;
        this.tryStartScreening();
    }

    @api
    get objectApiName() {
        return this._objectApiName;
    }

    set objectApiName(value) {
        this._objectApiName = value;
        this.tryStartScreening();
    }

    tryStartScreening() {
        if (this.hasStarted || !this._recordId || !this._objectApiName) {
            return;
        }

        this.hasStarted = true;
        this.runScreening();
    }

    async runScreening() {
        try {
            const searchId = await submitScreening({
                recordId: this._recordId,
                objectType: this._objectApiName
            });

            if (
                typeof searchId === 'string' &&
                searchId.startsWith('AML API error (')
            ) {
                throw new Error(searchId);
            }

            await notifyRecordUpdateAvailable([
                { recordId: this._recordId }
            ]);

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'AML Screening Submitted',
                    message: 'Search ID: ' + searchId,
                    variant: 'success'
                })
            );
        } catch (error) {
            const message =
                error?.body?.message || error?.message || 'AML screening failed.';

            if (message.includes('ALREADY_SUBMITTED:')) {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Already Submitted',
                        message: 'User has already submitted for AML screening.',
                        variant: 'warning'
                    })
                );
            } else {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'AML Screening Failed',
                        message,
                        variant: 'error'
                    })
                );
            }

        } finally {
            this.dispatchEvent(new CloseActionScreenEvent());
        }
    }
}