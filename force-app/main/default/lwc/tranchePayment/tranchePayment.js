import { LightningElement, wire } from 'lwc';
import getPaymentSchedules from '@salesforce/apex/TranchePaymentController.getPaymentSchedules';
import generateDemandLetters from '@salesforce/apex/TranchePaymentController.generateDemandLetters';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

export default class TranchePayment extends LightningElement {
    paymentSchedules = [];
    selectAll = false;

    wiredPaymentScheduleResult;
    isLoading = true;
    @wire(getPaymentSchedules)
    wiredPaymentSchedules(result) {
        this.wiredPaymentScheduleResult = result;
        const { data, error } = result;
        this.isLoading = false;
        if (data) {
            console.log('Payment Schedule Data:', data);
            this.paymentSchedules = data;
        } else if (error) {
            console.error('Error fetching Payment Schedule:', error);
            this.showToast(
                'Error',
                this.getErrorMessage(error),
                'error'
            );
        }
    }
    get selectedPaymentSchedules() {
        return this.paymentSchedules.filter(
            row => row.selected
        );
    }
    get isGenerateDisabled() {
        return this.selectedPaymentSchedules.length === 0;
    }
    get noRecords() {
        return !this.isLoading &&
            (!this.paymentSchedules || this.paymentSchedules.length === 0);
    }
      handleSelectAll(event) {
        this.selectAll = event.target.checked;
        this.paymentSchedules = this.paymentSchedules.map(row => {
            return {
                ...row,
                selected: this.selectAll
            };
        });
    }
    handleRowSelection(event) {
        const selectedId = event.target.dataset.id;
        const isSelected = event.target.checked;
        this.paymentSchedules = this.paymentSchedules.map(row => {
            if (row.id === selectedId) {
                return {
                    ...row,
                    selected: isSelected
                };
            }
            return row;
        });
        this.selectAll = this.paymentSchedules.length > 0 && this.paymentSchedules.every(row => row.selected);
    }

    async handleGenerateDemandLetter() {
            const selectedRecords = this.selectedPaymentSchedules;
            if (selectedRecords.length === 0) {
                this.showToast(
                    'Warning',
                    'Please select at least one Payment Schedule.',
                    'warning'
                );
                return;
            }
            const paymentScheduleIds = selectedRecords.map(row => row.id);
            console.log('Selected Payment Schedule IDs:', paymentScheduleIds);
            this.isLoading = true;
            try {
                await generateDemandLetters({paymentScheduleIds: paymentScheduleIds });
                this.showToast(
                    'Success',
                    'Demand Letter generated successfully.',
                    'success'
                );
                await refreshApex(this.wiredPaymentScheduleResult);
                this.selectAll = false;
            } catch (error) {
                console.error('Demand Letter Error:', error );
                this.showToast(
                    'Error',
                    this.getErrorMessage(error),
                    'error'
                );
            } finally {
                this.isLoading = false;
            }
        }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant
            })
        );
    }
    getErrorMessage(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (error?.message) {
            return error.message;
        }
        return 'Something went wrong.';
    }
}