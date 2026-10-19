import { api } from 'lwc';
import LightningModal from 'lightning/modal';
const CANCEL = 'Cancel';
const HINT = 'Choose what the new draft is for. It goes through the same approval.';
const CHOICES_LABEL = 'What the new draft is for';
const PROJECT = 'Project to copy to';
const PROJECT_PLACEHOLDER = 'Select a project';
const NO_PROJECT = 'There is no other active project to copy to.';
const CHOICE_REQUIRED = 'Choose one of the options.';
const PROJECT_REQUIRED = 'Select the project to copy to.';
const CREATE = 'Create draft';

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