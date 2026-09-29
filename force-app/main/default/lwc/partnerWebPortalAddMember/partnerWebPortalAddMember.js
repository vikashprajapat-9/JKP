import { LightningElement, wire } from 'lwc';
import getProjects from '@salesforce/apex/partnerWebPortalProjectController.getProjects';

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const PHONE_PATTERN = /^\d{9,10}$/;

export default class PartnerWebPortalAddMember extends LightningElement {

    form = { fullName: '', reportingTo: '', email: '', phone: '' };
    projects = [];
    selectedProjectIds = [];
    step = 'form';

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

    get isEmailValid() {
        return EMAIL_PATTERN.test(this.form.email.trim());
    }

    get isPhoneValid() {
        return PHONE_PATTERN.test(this.form.phone.trim());
    }

    get showEmailError() {
        return this.form.email.trim() !== '' && !this.isEmailValid;
    }

    get showPhoneError() {
        return this.form.phone.trim() !== '' && !this.isPhoneValid;
    }

    get emailClass() {
        return this.showEmailError ? 'field-input invalid' : 'field-input';
    }

    get phoneClass() {
        return this.showPhoneError ? 'phone-field invalid' : 'phone-field';
    }

    get isSubmitDisabled() {
        return !(
            this.form.fullName.trim() &&
            this.form.reportingTo.trim() &&
            this.isEmailValid &&
            this.isPhoneValid &&
            this.selectedProjectIds.length > 0
        );
    }

    handleInput(event) {
        const field = event.target.dataset.field;
        let value = event.target.value || '';
        if (field === 'phone') {
            value = value.replace(/\D/g, '');
            event.target.value = value;
        }
        this.form = { ...this.form, [field]: value };
    }

    handleProjectToggle(event) {
        const id = event.currentTarget.dataset.id;
        this.selectedProjectIds = this.selectedProjectIds.includes(id)
            ? this.selectedProjectIds.filter(x => x !== id)
            : [...this.selectedProjectIds, id];
    }

    handleSubmit() {
        if (this.isSubmitDisabled) return;
        // TODO: call Apex to create the executive (Contact + partner User) and assign
        // selectedProjectIds. UI only for now; the payload is ready below.
        const payload = {
            ...this.form,
            phone: '+94' + this.form.phone,
            projectIds: this.selectedProjectIds
        };
        this.dispatchEvent(new CustomEvent('memberadded', { detail: payload }));
        this.step = 'success';
    }

    handleKeyDown(event) {
        if (event.key === 'Escape') this.handleClose();
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }
}