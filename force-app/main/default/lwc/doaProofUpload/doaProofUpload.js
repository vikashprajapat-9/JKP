import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import LOGO_WHITE from '@salesforce/resourceUrl/Logo_White';
import updateTask from '@salesforce/apex/DoaProofUploadController.updateTask';

export default class DoaProofUpload extends LightningElement {
    @api recordId; // Receives Task ID or Case ID
    logoWhite = LOGO_WHITE;
    pageTitle = 'Upload Payment Proof Communication';

    get acceptedFormats() {
        return ['.pdf', '.png', '.jpg', '.jpeg'];
    }

    // Handles the file upload completion
    async handleUploadFinished(event) {
        try {
            // 1. Call Apex to close the task and trigger approval
            await updateTask({ recordId: this.recordId });

            // 2. Notify Salesforce to refresh UI record data instantly
            await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);

            // 3. Show Success Toast
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success!',
                    message: 'Payment proof uploaded and Task marked as Closed. Submitted for Financial Approval.',
                    variant: 'success'
                })
            );

            // 4. Automatically close the modal
            this.dispatchEvent(new CloseActionScreenEvent());

        } catch (error) {
            console.error('Error updating task:', error);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error updating task',
                    message: error?.body?.message || error?.message || 'Unknown error occurred.',
                    variant: 'error'
                })
            );
        }
    }

    // Closes the modal on Cancel click
    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}