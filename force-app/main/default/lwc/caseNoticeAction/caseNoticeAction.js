import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import checkNoticeStatus from '@salesforce/apex/Case_DeedOfCancellation.checkNoticeStatus';
import handleTerminationAction from '@salesforce/apex/Case_DeedOfCancellation.handleTerminationAction';

export default class CaseNoticeAction extends LightningElement {
    _recordId;
    @track isEligible = false;
    @track isLoading = true;
    @track selectedAction = 'HOLD';
    @track holdReason = '';

    // Fix: Automatically runs when Salesforce injects the Case recordId
    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        if (value) {
            this.checkEligibility();
        }
    }

    actionOptions = [
        { label: 'Hold Notice (Grant 30 Days Extension)', value: 'HOLD' },
        { label: 'Send Letter of Termination (Send Termination Email to Customer & Owner, Alert Legal)', value: 'SEND' }
    ];

    get isHoldSelected() {
        return this.selectedAction === 'HOLD';
    }

    async checkEligibility() {
        if (!this._recordId) return;

        this.isLoading = true;
        try {
            this.isEligible = await checkNoticeStatus({ caseId: this._recordId });
        } catch (error) {
            console.error('Error checking notice status:', error);
            this.isEligible = false;
        } finally {
            this.isLoading = false;
        }
    }

    handleActionChange(event) {
        this.selectedAction = event.detail.value;
    }

    handleReasonChange(event) {
        this.holdReason = event.detail.value;
    }

    async handleConfirm() {
        if (this.selectedAction === 'HOLD' && !this.holdReason) {
            this.showToast('Error', 'Please provide a reason for placing on hold.', 'error');
            return;
        }

        this.isLoading = true;
        try {
            const result = await handleTerminationAction({
                caseId: this._recordId,
                actionType: this.selectedAction,
                holdReason: this.holdReason
            });

            this.showToast('Success', result, 'success');
            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (error) {
            this.showToast('Error', error?.body?.message || error?.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}