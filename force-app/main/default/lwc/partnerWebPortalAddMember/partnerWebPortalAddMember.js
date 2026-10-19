import { LightningElement, wire } from 'lwc';
import getProjects from '@salesforce/apex/partnerWebPortalProjectController.getProjects';
import addExecutive from '@salesforce/apex/partnerWebPortalMyTeamController.addExecutive';

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const PHONE_PATTERN = /^\d{9,10}$/;
const COUNTRY_CODE = '+94';
const SAVE_ERROR = 'The team member could not be added. Please try again.';

// Every field is required; email and phone must also be in the right format
const REQUIRED_FIELDS = ['fullName', 'reportingTo', 'email', 'phone'];
const MISSING = {
    fullName: 'Enter the full name.',
    reportingTo: 'Enter who this team member reports to.',
    email: 'Enter the email ID.',
    phone: 'Enter the phone number.'
};
const FORMATS = { email: EMAIL_PATTERN, phone: PHONE_PATTERN };
const WRONG_FORMAT = {
    email: 'Enter a valid email address.',
    phone: 'Enter a valid 9 or 10 digit phone number.'
};
const NO_PROJECT = 'Select at least one project.';

export default class PartnerWebPortalAddMember extends LightningElement {

    form = { fullName: '', reportingTo: '', email: '', phone: '' };
    projects = [];
    selectedProjectIds = [];
    step = 'form';
    isSaving = false;
    errorMessage = '';
    touched = {};
    submitAttempted = false;

    @wire(getProjects)
    wiredProjects({ data, error }) {
        if (data) {
            this.projects = data.map(p => ({ id: p.id, name: p.name }));
        } else if (error) {
            this.projects = [];
        }
    }

    connectedCallback() {
        this._onKeyDown = this.handleKeyDown.bind(this);
        window.addEventListener('keydown', this._onKeyDown);
    }

    disconnectedCallback() {
        window.removeEventListener('keydown', this._onKeyDown);
    }

    get isFormStep() {
        return this.step === 'form';
    }

    get projectOptions() {
        return this.projects.map(p => {
            const selected = this.selectedProjectIds.includes(p.id);
            return {
                ...p,
                ariaPressed: String(selected),
                cardClass: selected ? 'project-card selected' : 'project-card'
            };
        });
    }

    get noProjects() {
        return this.projects.length === 0;
    }

    // ---------- REQUIRED FIELDS ----------
    isComplete(field) {
        const value = (this.form[field] || '').trim();
        return value !== '' && (!FORMATS[field] || FORMATS[field].test(value));
    }

    // A wrong format shows while typing; a missing value once the field is left or Add Team Member is pressed
    problemOf(field) {
        const value = (this.form[field] || '').trim();
        if (!value) {
            return this.touched[field] || this.submitAttempted ? MISSING[field] : '';
        }
        return this.isComplete(field) ? '' : WRONG_FORMAT[field];
    }

    get fullNameError() { return this.problemOf('fullName'); }
    get reportingToError() { return this.problemOf('reportingTo'); }
    get emailError() { return this.problemOf('email'); }
    get phoneError() { return this.problemOf('phone'); }

    get projectError() {
        return this.submitAttempted && this.selectedProjectIds.length === 0 ? NO_PROJECT : '';
    }

    get fullNameClass() { return this.fullNameError ? 'field-input invalid' : 'field-input'; }
    get reportingToClass() { return this.reportingToError ? 'field-input invalid' : 'field-input'; }
    get emailClass() { return this.emailError ? 'field-input invalid' : 'field-input'; }
    get phoneClass() { return this.phoneError ? 'phone-field invalid' : 'phone-field'; }

    get fullNameInvalid() { return String(Boolean(this.fullNameError)); }
    get reportingToInvalid() { return String(Boolean(this.reportingToError)); }
    get emailInvalid() { return String(Boolean(this.emailError)); }
    get phoneInvalid() { return String(Boolean(this.phoneError)); }

    get submitLabel() {
        return this.isSaving ? 'Adding…' : 'Add Team Member';
    }

    get isSubmitDisabled() {
        return this.isSaving;
    }

    handleInput(event) {
        const field = event.target.dataset.field;
        let value = event.target.value || '';
        if (field === 'phone') {
            value = value.replace(/\D/g, '');
            event.target.value = value;
        }
        this.form = { ...this.form, [field]: value };
        this.errorMessage = '';
    }

    handleBlur(event) {
        this.touched = { ...this.touched, [event.target.dataset.field]: true };
    }

    handleProjectToggle(event) {
        const id = event.currentTarget.dataset.id;
        this.selectedProjectIds = this.selectedProjectIds.includes(id)
            ? this.selectedProjectIds.filter(x => x !== id)
            : [...this.selectedProjectIds, id];
        this.errorMessage = '';
    }

    // Creates the executive's Account (reporting to the logged-in partner), Contact and Project Access records
    async handleSubmit() {
        if (this.isSaving) return;
        this.submitAttempted = true;
        const firstMissing = REQUIRED_FIELDS.find(field => !this.isComplete(field));
        if (firstMissing || this.selectedProjectIds.length === 0) {
            this.focusOn(firstMissing);
            return;
        }
        this.isSaving = true;
        this.errorMessage = '';
        try {
            const executiveId = await addExecutive({
                fullName: this.form.fullName.trim(),
                reportingTo: this.form.reportingTo.trim(),
                email: this.form.email.trim(),
                phone: COUNTRY_CODE + this.form.phone,
                projectIds: this.selectedProjectIds
            });
            this.dispatchEvent(new CustomEvent('memberadded', { detail: { executiveId } }));
            this.step = 'success';
        } catch (error) {
            this.errorMessage = (error && error.body && error.body.message) || SAVE_ERROR;
        } finally {
            this.isSaving = false;
        }
    }

    // The first field to fix, or the first project when only the projects are missing
    focusOn(field) {
        const target = field
            ? this.template.querySelector(`[data-field="${field}"]`)
            : this.template.querySelector('.project-card');
        if (target) target.focus();
    }

    // Keeps the cursor in the field while the button is pressed: leaving an empty field shows its message, which would
    // move the button away before the click lands
    keepFocus(event) {
        event.preventDefault();
    }

    handleKeyDown(event) {
        if (event.key === 'Escape') this.handleClose();
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }
}