import { LightningElement, track, wire } from 'lwc';
import submitRegistration from '@salesforce/apex/PartnerOnboardingController.submitRegistration';
import getProjectOptions from '@salesforce/apex/PartnerOnboardingController.getProjectOptions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class PartnerRegistrationForm extends LightningElement {

    @track registrationType = 'Company';

    @track form = {
        businessName: '',
        vatNumber: '',
        nameAsPerNic: '',
        homeAddress: '',
        nicNumber: '',
        passport: '',
        tin: '',
        email: '',
        phone: '',
        projectId: ''
    };

    // Track field errors for visible on-screen display
    @track errors = {};
    @track errorMessage = '';

    @track agreedToTerms = false;
    @track isSaving = false;
    @track isSubmitted = false;
    @track submittedAccountId = '';
    projectOptions = [];

    fileName = '';
    fileBase64 = '';

    @wire(getProjectOptions)
    wiredProjects({ data, error }) {
        if (data) {
            this.projectOptions = data;
        } else if (error) {
            console.error('Project options error:', error);
        }
    }

    get isCompany() {
        return this.registrationType === 'Company';
    }

    get isIndividual() {
        return this.registrationType === 'Individual';
    }

    get hasErrorMessage() {
        return Boolean(this.errorMessage);
    }

    get companyTabClass() {
        return 'type-toggle-btn ' + (this.isCompany ? 'active' : '');
    }

    get individualTabClass() {
        return 'type-toggle-btn ' + (this.isIndividual ? 'active' : '');
    }

    get uploadHintText() {
        return this.isIndividual 
            ? 'Upload NIC, TIN and passport' 
            : 'PDF only — Max 10 MB';
    }

    get uploadDropzoneSubtext() {
        return this.isIndividual 
            ? 'Upload PDF documents only (Max file size: 10 MB per file)' 
            : 'PDF only — max 10 MB';
    }

    get submitLabel() {
        return this.isSaving ? 'Submitting...' : 'Submit For Approval';
    }

    get isSubmitDisabled() {
        return this.isSaving;
    }

    get showFileChip() {
        return this.fileName !== '';
    }

    handleTypeSelect(event) {
        const selectedType = event.currentTarget.dataset.type;
        if (this.registrationType !== selectedType) {
            this.registrationType = selectedType;
            this.clearErrors();
        }
    }

    handleChange(event) {
        const field = (event.target.dataset && event.target.dataset.field) ? event.target.dataset.field : event.target.name;
        event.target.classList.remove('input-error');

        // Clear error text for this field
        if (field && this.errors[field]) {
            const updatedErrors = Object.assign({}, this.errors);
            delete updatedErrors[field];
            this.errors = updatedErrors;
        }

        if (field) {
            this.form = Object.assign({}, this.form, {
                [field]: event.target.value
            });
        }
    }

    handleTermsChange(event) {
        this.agreedToTerms = event.target.checked;
        if (this.agreedToTerms && this.errorMessage.indexOf('Terms') !== -1) {
            this.errorMessage = '';
        }
    }

    handleDismissError() {
        this.errorMessage = '';
    }

    handleFileChange(event) {
        const file = event.target.files[0];
        if (!file) return;

        if (file.size > 10 * 1024 * 1024) {
            this.setFormError('File size must be under 10 MB');
            return;
        }
        if (file.type !== 'application/pdf') {
            this.setFormError('Only PDF files are allowed');
            return;
        }

        this.fileName = file.name;
        const reader = new FileReader();
        reader.onload = () => {
            const base64 = reader.result.split(',')[1];
            this.fileBase64 = base64;
        };
        reader.readAsDataURL(file);
    }

    handleRemoveFile() {
        this.fileName = '';
        this.fileBase64 = '';
        const input = this.template.querySelector('input[type="file"]');
        if (input) input.value = '';
    }

    handleRegisterAnother() {
        this.form = {
            businessName: '',
            vatNumber: '',
            nameAsPerNic: '',
            homeAddress: '',
            nicNumber: '',
            passport: '',
            tin: '',
            email: '',
            phone: '',
            projectId: ''
        };
        this.fileName = '';
        this.fileBase64 = '';
        this.agreedToTerms = false;
        this.isSubmitted = false;
        this.submittedAccountId = '';
        this.clearErrors();
    }

    // Helper to highlight field and set error message
    setFieldError(fieldName, message) {
        this.errors = Object.assign({}, this.errors, {
            [fieldName]: message
        });
        const input = this.template.querySelector('input[data-field="' + fieldName + '"]');
        if (input) {
            input.classList.add('input-error');
            input.focus();
        }
        this.errorMessage = message;
    }

    setFormError(message) {
        this.errorMessage = message;
        this.toast('Error', message, 'error');
    }

    clearErrors() {
        this.errors = {};
        this.errorMessage = '';
        this.template.querySelectorAll('input').forEach(input => {
            input.classList.remove('input-error');
        });
    }

    // =========================================================
    // SUBMIT
    // =========================================================
    async handleSubmit() {
        // 1. Force sync all values directly from DOM
        this.template.querySelectorAll('input, select').forEach(input => {
            const field = (input.dataset && input.dataset.field) ? input.dataset.field : input.name;
            if (field && input.type !== 'file' && input.type !== 'checkbox') {
                this.form[field] = input.value;
            }
        });

        this.clearErrors();

        // 2. UI VALIDATION FOR COMPANY
        if (this.isCompany) {
            if (!this.form.businessName || !this.form.businessName.trim()) {
                this.setFieldError('businessName', 'Business Name is required.');
                return;
            }
            if (!this.form.email || !this.form.email.trim()) {
                this.setFieldError('email', 'Email is required.');
                return;
            }
            if (!this.form.phone || !this.form.phone.trim()) {
                this.setFieldError('phone', 'Phone Number is required.');
                return;
            }
        }

        // 3. UI VALIDATION FOR INDIVIDUAL
        if (this.isIndividual) {
            if (!this.form.nameAsPerNic || !this.form.nameAsPerNic.trim()) {
                this.setFieldError('nameAsPerNic', 'Name as per NIC is required.');
                return;
            }
            if (!this.form.email || !this.form.email.trim()) {
                this.setFieldError('email', 'Email address is required.');
                return;
            }
            if (!this.form.phone || !this.form.phone.trim()) {
                this.setFieldError('phone', 'Phone Number is required.');
                return;
            }
        }

        // 4. TERMS
        if (!this.agreedToTerms) {
            this.setFormError('Please accept the Terms of Service & Privacy Policy.');
            return;
        }

        // 5. CALL APEX
        this.isSaving = true;

        try {
            const payload = {
                registrationType: this.registrationType,
                businessName:     this.form.businessName ? this.form.businessName.trim() : '',
                vatNumber:        this.form.vatNumber ? this.form.vatNumber.trim() : '',
                nameAsPerNic:     this.form.nameAsPerNic ? this.form.nameAsPerNic.trim() : '',
                homeAddress:      this.form.homeAddress ? this.form.homeAddress.trim() : '',
                nicNumber:        this.form.nicNumber ? this.form.nicNumber.trim() : '',
                passport:         this.form.passport ? this.form.passport.trim() : '',
                tin:              this.form.tin ? this.form.tin.trim() : '',
                email:            this.form.email ? this.form.email.trim() : '',
                phone:            this.form.phone ? this.form.phone.trim() : '',
                projectId:        this.form.projectId,
                fileName:         this.fileName,
                fileBase64:       this.fileBase64
            };

            const accountId = await submitRegistration({ req: payload });

            this.submittedAccountId = accountId;
            this.isSubmitted = true;

            this.toast(
                'Success',
                'Your application has been submitted successfully!',
                'success'
            );

            this.dispatchEvent(new CustomEvent('submitted', {
                detail: { accountId: accountId }
            }));

        } catch (err) {
            console.error('Registration error:', err);

            let serverError = 'Registration failed. Please try again.';
            if (err && err.body && err.body.message) {
                serverError = err.body.message;
            } else if (err && err.message) {
                serverError = err.message;
            }

            // Show error in banner AND directly under the phone field if duplicate
            if (serverError.toLowerCase().indexOf('phone') !== -1 || serverError.toLowerCase().indexOf('already registered') !== -1) {
                this.setFieldError('phone', serverError);
            } else {
                this.setFormError(serverError);
            }

        } finally {
            this.isSaving = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title: title, message: message, variant: variant }));
    }
}