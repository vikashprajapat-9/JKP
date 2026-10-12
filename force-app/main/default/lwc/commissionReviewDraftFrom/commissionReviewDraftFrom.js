import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import CANCEL from '@salesforce/label/c.Commission_Common_Cancel';
import HINT from '@salesforce/label/c.Commission_Review_Draft_Hint';
import CHOICES_LABEL from '@salesforce/label/c.Commission_Review_Draft_Choices_Label';
import PROJECT from '@salesforce/label/c.Commission_Review_Draft_Project';
import PROJECT_PLACEHOLDER from '@salesforce/label/c.Commission_Review_Draft_Project_Placeholder';
import NO_PROJECT from '@salesforce/label/c.Commission_Review_Draft_No_Project';
import CHOICE_REQUIRED from '@salesforce/label/c.Commission_Review_Draft_Choice_Required';
import PROJECT_REQUIRED from '@salesforce/label/c.Commission_Review_Draft_Project_Required';
import CREATE from '@salesforce/label/c.Commission_Review_Draft_Create';

// "New draft from this": asks what the new draft of an approved configuration is for. Opened by commissionReview:
// const result = await CommissionReviewDraftFrom.open({ size: 'small', label, heading, choices: [{ value, title, text, needsProject }], projects: [{ value, label }] });
// Closes with { choice, targetProjectId }, or with nothing when the user cancels.
export default class CommissionReviewDraftFrom extends LightningModal {
    labels = {
        cancel: CANCEL,
        hint: HINT,
        choicesLabel: CHOICES_LABEL,
        project: PROJECT,
        projectPlaceholder: PROJECT_PLACEHOLDER,
        noProject: NO_PROJECT,
        create: CREATE
    };

    // The title of the dialog (label, which open() also takes, belongs to the base class)
    @api heading;
    // What can be chosen: { value, title, text, needsProject }
    @api choices;
    // The projects a copy can go to: { value: project id, label: project name }
    @api projects;

    choice = '';
    projectId = null;
    error = '';

    get projectOptions() {
        return Array.isArray(this.projects) ? this.projects : [];
    }

    get hasProjects() {
        return this.projectOptions.length > 0;
    }

    // The radio cards, each with its ready-made classes. A choice that needs another project is off when there is none.
    get cards() {
        return (Array.isArray(this.choices) ? this.choices : []).map((entry) => {
            const selected = entry.value === this.choice;
            const disabled = entry.needsProject === true && !this.hasProjects;
            return {
                value: entry.value,
                title: entry.title,
                text: entry.text,
                selected,
                disabled,
                cardClass: `radio-card choice${selected ? ' on' : ''}${disabled ? ' off' : ''}`,
                radioClass: selected ? 'radio on' : 'radio',
                showProject: selected && entry.needsProject === true,
                showNoProject: disabled
            };
        });
    }

    get hasError() {
        return this.error !== '';
    }

    handleChoice(event) {
        this.choice = event.target.value;
        this.error = '';
    }

    handleProject(event) {
        this.projectId = event.detail.value;
        this.error = '';
    }

    handleCancel() {
        this.close();
    }

    handleCreate() {
        const chosen = (Array.isArray(this.choices) ? this.choices : []).find((entry) => entry.value === this.choice);
        if (!chosen) {
            this.error = CHOICE_REQUIRED;
            return;
        }
        if (chosen.needsProject === true && !this.projectId) {
            this.error = PROJECT_REQUIRED;
            return;
        }
        this.close({ choice: chosen.value, targetProjectId: chosen.needsProject === true ? this.projectId : null });
    }
}