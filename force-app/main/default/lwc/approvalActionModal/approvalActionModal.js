import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import processAction from '@salesforce/apex/ApprovalActionController.processAction';

/**
 * Approve / Reject dialog. Built on lightning/modal so the framework renders it
 * in its own overlay - it stays centred in the viewport on desktop AND in the
 * Salesforce mobile app, instead of appearing at the component's position on the page.
 */
export default class ApprovalActionModal extends LightningModal {
    @api workItemId;
    @api processName;

    selectedAction = '';
    comments = '';
    commentError = '';
    isSaving = false;

    chooseApprove() { this.selectedAction = 'Approve'; this.commentError = ''; }
    chooseReject() { this.selectedAction = 'Reject'; this.commentError = ''; }

    handleComment(event) {
        this.comments = event.target.value;
        if (this.comments && this.comments.trim()) { this.commentError = ''; }
    }

    get isApproveChosen() { return this.selectedAction === 'Approve'; }
    get isRejectChosen() { return this.selectedAction === 'Reject'; }
    get approveBtnClass() {
        return this.isApproveChosen ? 'aab-choice aab-choice-approve aab-choice-on' : 'aab-choice aab-choice-approve';
    }
    get rejectBtnClass() {
        return this.isRejectChosen ? 'aab-choice aab-choice-reject aab-choice-on' : 'aab-choice aab-choice-reject';
    }
    get commentLabel() {
        if (this.isRejectChosen) { return 'Rejection comments'; }
        if (this.isApproveChosen) { return 'Approval comments'; }
        return 'Comments';
    }
    get submitDisabled() { return this.isSaving || !this.selectedAction; }
    get submitLabel() {
        if (this.isSaving) { return 'Submitting…'; }
        if (this.isRejectChosen) { return 'Reject'; }
        return 'Approve';
    }
    get submitVariant() { return this.isRejectChosen ? 'destructive' : 'success'; }

    handleCancel() {
        if (this.isSaving) { return; }
        this.close(null);
    }

    handleSubmit() {
        if (!this.selectedAction) {
            this.commentError = 'Please choose Approve or Reject.';
            return;
        }
        // Comment is mandatory for BOTH approve and reject.
        if (!this.comments || !this.comments.trim()) {
            this.commentError = `Please enter a comment before you ${this.selectedAction.toLowerCase()}.`;
            return;
        }
        this.isSaving = true;
        processAction({
            workItemId: this.workItemId,
            action: this.selectedAction,
            comments: this.comments
        })
            .then((res) => {
                this.isSaving = false;
                this.close({ outcome: res });
            })
            .catch((error) => {
                this.isSaving = false;
                this.commentError = this.reduceError(error);
            });
    }

    reduceError(error) {
        if (error && error.body && error.body.message) { return error.body.message; }
        if (error && error.message) { return error.message; }
        return 'Something went wrong. Please try again.';
    }
}