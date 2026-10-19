import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getApprovalState from '@salesforce/apex/ApprovalActionController.getApprovalState';
import ApprovalActionModal from 'c/approvalActionModal';

export default class ApprovalActionBar extends LightningElement {
    @api recordId;

    state = {};
    wiredResult;
    showAllSteps = false;

    @wire(getApprovalState, { recordId: '$recordId' })
    wiredState(result) {
        this.wiredResult = result;
        if (result.data) {
            this.state = result.data;
        } else if (result.error) {
            this.state = {};
        }
    }

    // ---- visibility -------------------------------------------------------
    // Nothing is rendered unless the record actually has an approval on it,
    // so the component is safe to leave on every record page.
    get showBar() {
        return this.state && this.state.hasApproval === true;
    }
    get canAct() {
        return this.state && this.state.canAct === true;
    }
    get isPending() {
        return this.state && this.state.isPending === true;
    }

    // ---- header ----------------------------------------------------------
    get statusLabel() {
        const s = this.state ? this.state.overallStatus : '';
        if (s === 'Pending') { return 'Pending Approval'; }
        if (s === 'Approved') { return 'Approved'; }
        if (s === 'Rejected') { return 'Rejected'; }
        if (s === 'Removed') { return 'Recalled'; }
        return s;
    }
    get statusClass() {
        const s = this.state ? this.state.overallStatus : '';
        if (s === 'Approved') { return 'aab-pill aab-pill-approved'; }
        if (s === 'Rejected') { return 'aab-pill aab-pill-rejected'; }
        if (s === 'Removed') { return 'aab-pill aab-pill-removed'; }
        return 'aab-pill aab-pill-pending';
    }
    get processText() {
        return this.state && this.state.processName ? this.state.processName : '';
    }

    get summaryText() {
        if (!this.state) { return ''; }
        if (this.state.isPending && this.state.currentApproverName) {
            return `Waiting on ${this.state.currentApproverName}`;
        }
        if (this.state.overallStatus === 'Approved') {
            return 'All approvals completed';
        }
        if (this.state.overallStatus === 'Rejected') {
            return 'Request was rejected';
        }
        return '';
    }
    get submittedText() {
        if (!this.state || !this.state.submittedByName) { return ''; }
        return `Submitted by ${this.state.submittedByName}`;
    }

    // ---- steps -----------------------------------------------------------
    get allSteps() {
        const steps = (this.state && this.state.steps) || [];
        return steps.map((s, i) => {
            let cls = 'aab-chip';
            let icon = 'utility:clock';
            let variant = '';
            if (s.isApproved) {
                cls += ' aab-chip-approved'; icon = 'utility:check'; variant = 'success';
            } else if (s.isRejected) {
                cls += ' aab-chip-rejected'; icon = 'utility:close'; variant = 'error';
            } else if (s.isPending) {
                cls += ' aab-chip-pending'; icon = 'utility:clock';
            }
            const dateText = s.actionDate && !s.isPending ? this.formatDate(s.actionDate) : '';
            return {
                key: `step-${i}`,
                ...s,
                cls,
                icon,
                variant,
                dateText,
                hasComment: !!s.comments,
                // full detail sits in the tooltip so the chip stays one line
                tooltip: `${s.actorName || ''}${dateText ? ' · ' + dateText : ''}${s.comments ? ' — ' + s.comments : ''}`
            };
        });
    }

    // Keep the bar short on records with long approval chains.
    get COLLAPSED_COUNT() { return 4; }

    get stepItems() {
        const all = this.allSteps;
        if (this.showAllSteps || all.length <= this.COLLAPSED_COUNT) { return all; }
        // always keep the pending step visible - it is the one that matters
        const pendingIdx = all.findIndex((s) => s.isPending);
        if (pendingIdx >= this.COLLAPSED_COUNT) {
            return all.slice(0, this.COLLAPSED_COUNT - 1).concat([all[pendingIdx]]);
        }
        return all.slice(0, this.COLLAPSED_COUNT);
    }

    get hasSteps() {
        return this.allSteps.length > 0;
    }
    get hiddenCount() {
        return Math.max(0, this.allSteps.length - this.stepItems.length);
    }
    // any approver left a comment?
    get hasComments() {
        return this.allSteps.some((s) => !!s.comments);
    }
    // expanded view lists every step in full, with its comment
    get showDetail() {
        return this.showAllSteps;
    }
    get hasMore() {
        return this.hiddenCount > 0 || this.hasComments || this.showAllSteps;
    }
    get moreLabel() {
        if (this.showAllSteps) { return 'Show less'; }
        if (this.hiddenCount > 0) { return `+${this.hiddenCount} more`; }
        return 'Show comments';
    }
    toggleSteps() {
        this.showAllSteps = !this.showAllSteps;
    }

    formatDate(value) {
        try {
            return new Intl.DateTimeFormat('en-GB', {
                day: '2-digit', month: 'short', year: 'numeric'
            }).format(new Date(value));
        } catch (e) {
            return '';
        }
    }

    // ---- modal -----------------------------------------------------------
    // lightning/modal renders in the framework's own overlay, so the dialog is
    // centred in the viewport on desktop and in the mobile app - the user never
    // has to scroll up to find it.
    async openModal() {
        const result = await ApprovalActionModal.open({
            size: 'small',
            label: 'Approve or Reject Request',
            workItemId: this.state.workItemId,
            processName: this.state.processName
        });
        if (result && result.outcome) {
            this.toast('Success', `Approval request ${result.outcome.toLowerCase()}.`, 'success');
            // Refresh this component and the rest of the record page so the
            // standard Approval History and any field updates show at once.
            await refreshApex(this.wiredResult);
            getRecordNotifyChange([{ recordId: this.recordId }]);
        }
    }

    reduceError(error) {
        if (error && error.body && error.body.message) { return error.body.message; }
        if (error && error.message) { return error.message; }
        return 'Something went wrong. Please try again.';
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}