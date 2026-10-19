import { LightningElement, api, track } from 'lwc';
import updateSignedDates from '@salesforce/apex/SignedSpaEscrowController.updateSignedDates';
import LogoWhite from '@salesforce/resourceUrl/Logo_White';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class SignedSpaEscrow extends LightningElement {
    logoUrl = LogoWhite;
    spaFile;
    spaFileName;
    escrowFile;
    escrowFileName;
    @api recordId;
    @track spaSignedDate;
    @track escrowSignedDate;
    isSaving = false;
    
    handleSpaDateChange(event) {
        this.spaSignedDate = event.target.value;
    }
    handleEscrowDateChange(event) {
        this.escrowSignedDate = event.target.value;
    }
    handleSpaUpload() {
        const fileInput = this.template.querySelector('.spa-file-input');
        if (fileInput) {
            fileInput.click();
        }
    }
    handleEscrowUpload() {
        const fileInput = this.template.querySelector('.escrow-file-input' );
        if (fileInput) {
            fileInput.click();
        }
    }
    handleSpaFileSelected(event) {
        const file = event.target.files[0];
        if (!file) {
            return;
        }
        this.spaFile = file;
        this.spaFileName = file.name;
        console.log('SPA file selected:', file.name);
    }
    handleEscrowFileSelected(event) {
        const file = event.target.files[0];
        if (!file) {
            return;
        }
        this.escrowFile = file;
        this.escrowFileName = file.name;
        console.log('Escrow file selected:', file.name);
    }
    removeSpaFile() {
        this.spaFile = null;
        this.spaFileName = null;
        const input = this.template.querySelector('.spa-file-input');
        if (input) {
            input.value = '';
        }
    }
    removeEscrowFile() {
        this.escrowFile = null;
        this.escrowFileName = null;
        const input = this.template.querySelector('.escrow-file-input');
        if (input) {
            input.value = '';
        }
    }
    async handleComplete() {
        if (!this.spaSignedDate) {
            this.showToast(
                'Missing Date',
                'Please enter the SPA Signed Date.',
                'error'
            );
            return;
        }
        this.isSaving = true;
        try {
            await updateSignedDates({
                opportunityId: this.recordId,
                spaSignedDate: this.spaSignedDate,
                escrowSignedDate: this.escrowSignedDate
            });

            this.showToast(
                'Success',
                'SPA / Escrow details completed successfully.',
                'success'
            );

            this.dispatchEvent(
                new CustomEvent('completed', {
                    detail: {
                        spaSignedDate: this.spaSignedDate,
                        escrowSignedDate: this.escrowSignedDate
                    }
                })
            );
            this.dispatchEvent(new CustomEvent('close'));
        } catch (error) {
            console.error( 'Error updating SPA / Escrow:',  error);
            this.showToast('Error',this.getErrorMessage(error),'error' );
        } finally {
            this.isSaving = false;
        }
    }
    handleCancel() {
        this.dispatchEvent(new CustomEvent('close'));
    }
    getErrorMessage(error) {
        return error?.body?.message ||
            error?.message ||
            'Something went wrong.';
    }
    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}