import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import CANCEL from '@salesforce/label/c.Commission_Common_Cancel';
import HEADING from '@salesforce/label/c.Commission_Change_New';
import PROJECT from '@salesforce/label/c.Commission_Setup_Picker_Project';
import PLACEHOLDER from '@salesforce/label/c.Commission_Setup_Picker_Placeholder';
import HINT from '@salesforce/label/c.Commission_Setup_Picker_Hint';
import CONTINUE from '@salesforce/label/c.Commission_Setup_Picker_Continue';
import REQUIRED from '@salesforce/label/c.Commission_Setup_Picker_Required';
import NO_PROJECTS from '@salesforce/label/c.Commission_Setup_Picker_No_Projects';

// Asks for the project of a new configuration. Opened by commissionSetup:
// const projectId = await CommissionSetupProjectPicker.open({ size: 'small', label, projects: [{ value, label }] });
// Closes with the chosen project id, or with nothing when the user cancels.
export default class CommissionSetupProjectPicker extends LightningModal {
    labels = {
        cancel: CANCEL,
        heading: HEADING,
        project: PROJECT,
        placeholder: PLACEHOLDER,
        hint: HINT,
        continueLabel: CONTINUE,
        noProjects: NO_PROJECTS
    };

    projectId = null;
    error = '';

    _projects = [];

    // Options of the combobox: { value: project id, label: project name }
    @api
    get projects() {
        return this._projects;
    }
    set projects(value) {
        this._projects = Array.isArray(value) ? value : [];
        // With a single project there is nothing to choose
        if (this._projects.length === 1) {
            this.projectId = this._projects[0].value;
        }
    }

    get hasProjects() {
        return this._projects.length > 0;
    }

    get continueDisabled() {
        return !this.hasProjects;
    }

    handleProject(event) {
        this.projectId = event.detail.value;
        this.error = '';
    }

    handleCancel() {
        this.close();
    }

    handleContinue() {
        if (!this.projectId) {
            this.error = REQUIRED;
            return;
        }
        this.close(this.projectId);
    }
}