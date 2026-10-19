import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import { labels } from './labels';

// Asks who should approve a configuration when several people can. Opened by commissionEditor:
// const approverId = await CommissionEditorSubmit.open({ size: 'small', label, approvers: [{ value, label }], selected });
// Closes with the chosen user id, or with nothing when the user cancels.
export default class CommissionEditorSubmit extends LightningModal {
    labels = labels;

    approverId = null;
    error = '';

    _approvers = [];

    // Options of the combobox: { value: user id, label: name }
    @api
    get approvers() {
        return this._approvers;
    }
    set approvers(value) {
        this._approvers = Array.isArray(value) ? value : [];
        this.preselect();
    }

    _selected = null;

    // The approver chosen the last time, when still possible
    @api
    get selected() {
        return this._selected;
    }
    set selected(value) {
        this._selected = value || null;
        this.preselect();
    }

    preselect() {
        if (!this.approverId && this._selected && this._approvers.some((option) => option.value === this._selected)) {
            this.approverId = this._selected;
        }
    }

    handleApprover(event) {
        this.approverId = event.detail.value || null;
        this.error = '';
    }

    handleCancel() {
        this.close();
    }

    handleSubmit() {
        if (!this.approverId) {
            this.error = labels.approverRequired;
            return;
        }
        this.close(this.approverId);
    }
}