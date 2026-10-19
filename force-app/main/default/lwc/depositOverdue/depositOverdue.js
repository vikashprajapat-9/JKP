import { LightningElement,api,wire} from 'lwc';
import revokeOfferLetter from '@salesforce/apex/DepositOverdueController.revokeOfferLetter';
import requestTimeExtension from '@salesforce/apex/DepositOverdueController.requestTimeExtension';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import createReceipt from '@salesforce/apex/DepositOverdueController.createReceipt';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { getPicklistValues } from 'lightning/uiObjectInfoApi';
import RECEIPT_OBJECT from '@salesforce/schema/Receipt_Log__c';
import TYPE_FIELD from '@salesforce/schema/Receipt_Log__c.Type__c';
import LogoWhite from '@salesforce/resourceUrl/Logo_White';

export default class DepositOverdue extends NavigationMixin(LightningElement) {
    logoUrl = LogoWhite;
    @api recordId;
    showDepositScreen = true;
    showReceiptScreen = false;
    receiptAmount;
    receiptType;
    receiptTypeOptions = [];
    isSaving = false;
    recordTypeId;

    @wire(getObjectInfo, {
        objectApiName: RECEIPT_OBJECT
        })
        objectInfo({ data, error }) {

        if (data) {
            this.recordTypeId =
                data.defaultRecordTypeId;
        }
    }
    @wire(getPicklistValues, {
        recordTypeId: '$recordTypeId',
        fieldApiName: TYPE_FIELD
    })
    typePicklist({ data, error }) {
        if (data) {
            this.receiptTypeOptions =
                data.values.map(item => ({label: item.label,value: item.value }));
        }
    }

    async handleBack() {
        debugger;
        try {
            await revokeOfferLetter({opportunityId: this.recordId});
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'Offer letter revoked successfully. Unit is now Available and Escrow Account is Inactive.',
                    variant: 'success'
                })
            );
            this.dispatchEvent(new CustomEvent('close'));
            } catch (error) {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: error?.body?.message || 'Unable to revoke offer letter.',
                        variant: 'error'
                    })
                );
            }
    }
    async handleApproval() {
        debugger;
        try {
            await requestTimeExtension({opportunityId: this.recordId});
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'Time extension requested successfully.',
                    variant: 'success'
                })
            );
            this.dispatchEvent(new CustomEvent('close'));

        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    //message: error?.body?.message || 'Unable to request time extension.',
                    message: this.getErrorMessage(error),
                    variant: 'error'
                })
            );
        }
    }
    getErrorMessage(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (error?.body?.pageErrors?.length) {
            return error.body.pageErrors
                .map(e => e.message)
                .join(', ');
        }
        if (error?.message) {
            return error.message;
        }
        return 'Unable to request time extension.';
    }

    handleReceipt() {
        this.receiptAmount = null;
        this.receiptType = null;
        this.showDepositScreen = false;
        this.showReceiptScreen = true;
    }
    handleReceiptBack() {
        this.showReceiptScreen = false;
        this.showDepositScreen = true;
    }
    handleAmountChange(event) {
        this.receiptAmount = event.target.value;
    }
    handleTypeChange(event) {
        this.receiptType =
            event.detail.value;
    }

    async handleSaveReceipt() {
        if (!this.receiptAmount) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'Please enter Amount.',
                    variant: 'error'
                })
            );
            return;
        }
        if (!this.receiptType) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'Please select Type.',
                    variant: 'error'
                })
            );
            return;
        }
        this.isSaving = true;
        try {
            await createReceipt({ opportunityId: this.recordId,amount: Number(this.receiptAmount),
                receiptType: this.receiptType });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'Receipt created successfully.',
                    variant: 'success'
                })
            );
            this.dispatchEvent(new CustomEvent('close'));
            this.showReceiptScreen = false;
            this.showDepositScreen = true;

        } catch (error) {
            console.error( 'Create Receipt Error:',error );
            this.dispatchEvent(
                new ShowToastEvent({ title: 'Error',
                    message:error?.body?.message || 'Unable to create receipt.', variant: 'error' })
            );
        } finally {
            this.isSaving = false;
        }
    }
}