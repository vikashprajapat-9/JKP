import { LightningElement, wire } from 'lwc';
import { loadStyle } from 'lightning/platformResourceLoader';
import basePath from '@salesforce/community/basePath';
import PORTAL_THEME from '@salesforce/resourceUrl/JKPortalTheme';
import LOGIN_ASSETS from '@salesforce/resourceUrl/PartnerPortalLogin';
import login from '@salesforce/apex/partnerPortalLoginController.login';
import isExecutiveUsername from '@salesforce/apex/partnerPortalLoginController.isExecutiveUsername';
import getRegistrationForm from '@salesforce/apex/partnerPortalRegistrationController.getRegistrationForm';
import register from '@salesforce/apex/partnerPortalRegistrationController.register';
import uploadDocument from '@salesforce/apex/partnerPortalRegistrationController.uploadDocument';
import startDocumentUpload from '@salesforce/apex/partnerPortalRegistrationController.startDocumentUpload';
import uploadDocumentChunk from '@salesforce/apex/partnerPortalRegistrationController.uploadDocumentChunk';
import finishDocumentUpload from '@salesforce/apex/partnerPortalRegistrationController.finishDocumentUpload';
import getChannelPartnerInfo from '@salesforce/apex/partnerWebPortalInfoController.getChannelPartnerInfo';

const LABELS = {
    ACCESS_DENIED_TITLE: 'Access Denied',
    ACCESS_DENIED_TEXT: 'Your temporary access to the Partner Portal has ended because the conditions to continue were not met during the access period. Please contact the JKP CP team.'
};

const MIN_PHONE_DIGITS = 9;
const MAX_PHONE_DIGITS = 15;
const BYTES_PER_MB = 1024 * 1024;
// SharePoint takes a file in ranges that are multiples of 320 KiB; this size keeps each request well inside Apex's limits
const SHAREPOINT_CHUNK = 5 * 320 * 1024;
const CHUNK_RETRIES = 2;
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const PHONE_PATTERN = /^\+?[0-9 ().-]+$/;
// Spaces of any kind at either end, including zero-width ones, which JavaScript's trim() keeps (Salesforce removes them too)
const EDGE_SPACES = /^[\s\u200B-\u200D\u2060]+|[\s\u200B-\u200D\u2060]+$/g;

const STEP = {
    LOGIN: 'login',
    REGISTER: 'register',
    SUBMITTED: 'submitted',
    UNDER_REVIEW: 'underReview',
    RESTRICTED: 'restricted',
    EXECUTIVE: 'executive',
    ACCESS_DENIED: 'accessDenied'
};

const UNDER_REVIEW = {
    icon: 'status-review.png',
    title: 'Registration Under Review',
    text: 'Thank you for registering with us! Your application is currently under approval. Please wait while we complete the review process.'
};
const STATUS = {
    [STEP.SUBMITTED]: UNDER_REVIEW,
    [STEP.UNDER_REVIEW]: UNDER_REVIEW,
    [STEP.RESTRICTED]: {
        icon: 'status-restricted.png',
        title: 'Access Restricted',
        text: 'Your access has been revoked as per T&C. Please contact the JKP CP team.'
    },
    // Temporary access that ended without its conditions met (a converted lead or enough site visits)
    [STEP.ACCESS_DENIED]: {
        icon: 'status-restricted.png',
        title: LABELS.ACCESS_DENIED_TITLE,
        text: LABELS.ACCESS_DENIED_TEXT
    },
    // An executive is added by their channel partner, approved by JKP, and then gets a login; they never register
    [STEP.EXECUTIVE]: {
        icon: 'status-review.png',
        title: 'Awaiting Approval',
        text: 'Your channel partner has added you to their team. You will receive your login details by email once John Keells Properties approves you.'
    }
};
// How long typing in Username pauses before the page checks whether it belongs to an executive
const EXECUTIVE_CHECK_DELAY = 400;

// A value as Salesforce checks and saves it: without spaces of any kind at its ends
function cleanText(value) {
    return (value || '').replace(EDGE_SPACES, '');
}

function rawMessageOf(error) {
    return error && error.body && error.body.message ? error.body.message : error && error.message;
}

// A request that never got its answer: the connection dropped, so Salesforce may or may not have done the work
function isConnectionError(error) {
    return /failed to get error from response|failed to fetch|networkerror|load failed/i.test(rawMessageOf(error) || '');
}

// Salesforce's message for the partner; a dropped connection gets a plain explanation instead of the framework's text
function messageOf(error) {
    if (isConnectionError(error)) {
        return 'The connection was interrupted. Please check your internet connection and try again.';
    }
    return rawMessageOf(error) || 'Something went wrong. Please try again.';
}

// Digits without a leading trunk 0
function nationalDigits(value) {
    return (value || '').replace(/\D/g, '').replace(/^0+/, '');
}

// The same check as Salesforce makes: digits with spaces, brackets, dashes or dots, 9 to 15 digits without a leading 0
function isPhone(value) {
    const digits = nationalDigits(value).length;
    return PHONE_PATTERN.test(value) && digits >= MIN_PHONE_DIGITS && digits <= MAX_PHONE_DIGITS;
}

function formatSize(bytes) {
    return bytes >= BYTES_PER_MB ? `${(bytes / BYTES_PER_MB).toFixed(1)} MB` : `${Math.max(1, Math.round(bytes / 1024))} KB`;
}

function extensionOf(name) {
    const dot = (name || '').lastIndexOf('.');
    return dot >= 0 ? name.slice(dot + 1).toLowerCase() : '';
}

// "PDF", or "PDF, JPG or PNG"
function typesText(types) {
    const names = types.map((type) => type.toUpperCase());
    return names.length > 1 ? `${names.slice(0, -1).join(', ')} or ${names[names.length - 1]}` : names[0];
}

// A file's content (or a slice of it) in base64, as Salesforce receives documents
function readAsBase64(blob, name) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => {
            const result = String(reader.result || '');
            resolve(result.slice(result.indexOf(',') + 1));
        };
        reader.onerror = () => reject(new Error(`${name || blob.name} could not be read. Please choose it again.`));
        reader.readAsDataURL(blob);
    });
}

// Tries a request again after a dropped connection; Salesforce's own refusals are not retried
async function withRetry(request) {
    for (let attempt = 0; ; attempt++) {
        try {
            // eslint-disable-next-line no-await-in-loop
            return await request();
        } catch (error) {
            if (attempt >= CHUNK_RETRIES || !isConnectionError(error)) {
                throw error;
            }
        }
    }
}

// The Channel Partner Portal's login page, as in the Figma design. Partners log in with their username (or email) and
// password through Salesforce's own login, as their Partner Community users. "Register here" opens the registration
// form, whose types and fields come from the Partner Registration Field custom metadata. Submitting it creates the
// partner's Account and Contact together with the first document, then uploads the other documents one by one, all as
// Files on the Account. A username that belongs to no partner also opens the registration form; a pending registration
// or revoked access gets its status screen.
export default class PartnerPortalLogin extends LightningElement {
    step = STEP.LOGIN;
    username = '';
    password = '';
    showPassword = false;
    loginError;
    // The username that was not found, mentioned on the registration screen
    unknownUsername;
    // The typed username or email belongs to an executive, who only logs in: Register here is not offered to them
    isExecutiveUser = false;
    executiveCheck;
    executiveTimer;
    isBusy = false;
    shake = false;

    // The registration form from Salesforce (types, their fields, document rules), or why it could not be loaded
    form;
    formError;
    termsAccepted = false;
    registrationType = '';
    values = {};
    // Chosen documents for display ({ key, name, bytes, size, removeLabel, state }); the File objects are kept apart
    files = [];
    fileObjects = new Map();
    uploadError;
    dragOver = false;
    // Field errors show once Submit has been pressed; Salesforce's own until the field changes
    submitAttempted = false;
    serverErrors = {};
    submitError;
    isSubmitting = false;
    progressText;
    // Once the registration is saved: lets its documents be uploaded (and retried)
    ticket;
    // The registration keeps its documents in SharePoint (Document categories) rather than as Salesforce Files
    documentsInSharePoint = false;
    // An email typed on the login page, for the form's email field
    prefillEmail;
    // A registration call lost its answer, so the registration may have been saved with only its first document
    registrationInterrupted = false;
    // Shown on Under Review when that happened and other documents may not have arrived
    documentsMayBeMissing = false;
    openMenu = null;

    // Terms of Service / Privacy Policy dialog
    doc = null;
    docOpener;
    docLoading = false;
    termsHtml;

    // Element to focus after the next render (a new screen, an opened menu)
    pendingFocus;

    logoUrl = `${LOGIN_ASSETS}/logo.png`;
    illustrationUrl = `${LOGIN_ASSETS}/login-illustration.png`;

    @wire(getRegistrationForm)
    wiredForm({ data, error }) {
        if (data) {
            this.form = data;
            this.formError = undefined;
        } else if (error) {
            this.form = undefined;
            this.formError = messageOf(error);
        }
    }

    connectedCallback() {
        loadStyle(this, `${PORTAL_THEME}/theme.css`).catch(() => {
            // The system font is used if the theme cannot be loaded
        });
    }

    renderedCallback() {
        if (this.pendingFocus) {
            const target = this.template.querySelector(this.pendingFocus);
            this.pendingFocus = undefined;
            if (target) {
                target.focus();
            }
        }
    }

    // ---------- screens ----------
    get isLoginStep() {
        return this.step === STEP.LOGIN;
    }

    get isRegisterStep() {
        return this.step === STEP.REGISTER;
    }

    get formColumnClass() {
        return this.shake ? 'form-column shake' : 'form-column';
    }

    // Where to go after logging in: the page that sent the partner here, or the portal home
    get startUrl() {
        let target = null;
        try {
            target = new URL(window.location.href).searchParams.get('startURL');
        } catch (e) {
            target = null;
        }
        return target && target.startsWith('/') && !target.startsWith('//') ? target : `${basePath}/`;
    }

    flashError() {
        this.shake = false;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        requestAnimationFrame(() => {
            this.shake = true;
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                this.shake = false;
            }, 450);
        });
    }

    // ---------- login ----------
    get usernameClass() {
        return this.loginError ? 'text-input text-input_error' : 'text-input';
    }

    get passwordBoxClass() {
        return this.loginError ? 'password-box password-box_error' : 'password-box';
    }

    get loginInvalid() {
        return this.loginError ? 'true' : 'false';
    }

    get passwordType() {
        return this.showPassword ? 'text' : 'password';
    }

    get passwordToggleLabel() {
        return this.showPassword ? 'Hide password' : 'Show password';
    }

    get passwordShownState() {
        return String(this.showPassword);
    }

    get loginDisabled() {
        return this.isBusy || !this.username.trim() || !this.password;
    }

    // Salesforce's own forgot-password page of this site
    get forgotPasswordUrl() {
        return `${basePath}/ForgotPassword`;
    }

    handleUsernameInput(event) {
        this.username = event.target.value;
        this.loginError = undefined;
        this.checkExecutive(this.username.trim());
    }

    get showRegisterLink() {
        return !this.isExecutiveUser;
    }

    // Once typing pauses, asks whether the username or email is an executive's; only the latest answer counts
    checkExecutive(name) {
        window.clearTimeout(this.executiveTimer);
        const check = {};
        this.executiveCheck = check;
        if (!name.includes('@')) {
            this.isExecutiveUser = false;
            return;
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.executiveTimer = window.setTimeout(async () => {
            let executive = false;
            try {
                executive = (await isExecutiveUsername({ username: name })) === true;
            } catch (error) {
                executive = false;
            }
            if (this.executiveCheck === check) {
                this.isExecutiveUser = executive;
            }
        }, EXECUTIVE_CHECK_DELAY);
    }

    handlePasswordInput(event) {
        this.password = event.target.value;
        this.loginError = undefined;
    }

    handleTogglePassword() {
        this.showPassword = !this.showPassword;
    }

    async handleLogin(event) {
        if (event) {
            event.preventDefault();
        }
        if (this.loginDisabled) {
            return;
        }
        this.isBusy = true;
        this.loginError = undefined;
        try {
            const result = await login({ username: this.username.trim(), password: this.password, startUrl: this.startUrl });
            const status = result ? result.status : undefined;
            if (status === 'LOGGED_IN' && result.url) {
                // Stays busy while the browser opens the portal
                window.location.assign(result.url);
                return;
            }
            this.isBusy = false;
            this.password = '';
            if (status === 'NOT_REGISTERED') {
                this.startRegistration(this.username.trim());
            } else if (status === 'UNDER_REVIEW') {
                this.step = STEP.UNDER_REVIEW;
            } else if (status === 'RESTRICTED') {
                this.step = STEP.RESTRICTED;
            } else if (status === 'ACCESS_DENIED') {
                this.step = STEP.ACCESS_DENIED;
            } else if (status === 'EXECUTIVE') {
                this.isExecutiveUser = true;
                this.step = STEP.EXECUTIVE;
            } else {
                this.loginError = 'Something went wrong. Please try again.';
            }
        } catch (error) {
            this.isBusy = false;
            this.loginError = messageOf(error);
            this.password = '';
            this.pendingFocus = '.password-input';
            this.flashError();
        }
    }

    handleRegister() {
        this.startRegistration(null);
    }

    // An email that was used to log in fills the registration's email
    startRegistration(unknownUsername) {
        this.resetRegistration();
        this.unknownUsername = unknownUsername;
        this.prefillEmail = unknownUsername && EMAIL_PATTERN.test(unknownUsername) ? unknownUsername : undefined;
        this.step = STEP.REGISTER;
        this.pendingFocus = '.select-btn[data-menu="type"]';
    }

    handleBackToLogin() {
        this.step = STEP.LOGIN;
        this.loginError = undefined;
        this.password = '';
        this.unknownUsername = undefined;
        this.resetRegistration();
        this.pendingFocus = this.username ? '.password-input' : '[data-field="username"]';
    }

    resetRegistration() {
        this.termsAccepted = false;
        this.registrationType = '';
        this.values = {};
        this.files = [];
        this.fileObjects.clear();
        this.uploadError = undefined;
        this.submitAttempted = false;
        this.serverErrors = {};
        this.submitError = undefined;
        this.progressText = undefined;
        this.ticket = undefined;
        this.documentsInSharePoint = false;
        this.prefillEmail = undefined;
        this.registrationInterrupted = false;
        this.documentsMayBeMissing = false;
        this.openMenu = null;
    }

    // ---------- registration ----------
    get notRegisteredText() {
        return this.unknownUsername
            ? `We couldn't find a channel partner account for ${this.unknownUsername}. Register below to join the portal.`
            : undefined;
    }

    get registrationTypes() {
        return this.form && this.form.types ? this.form.types : [];
    }

    get selectedType() {
        return this.registrationTypes.find((type) => type.value === this.registrationType);
    }

    get typeOptions() {
        return this.registrationTypes.map((type) => ({
            label: type.label,
            value: type.value,
            selected: type.value === this.registrationType ? 'true' : 'false',
            cssClass: type.value === this.registrationType ? 'menu-option menu-option_selected' : 'menu-option'
        }));
    }

    get typesLoading() {
        return !this.form && !this.formError;
    }

    get typeLabel() {
        const type = this.selectedType;
        return type ? type.label : 'Select';
    }

    // Once the registration is saved its details are fixed; only its documents can still be uploaded
    get formLocked() {
        return Boolean(this.ticket) || this.isSubmitting;
    }

    fieldOfType(kind) {
        const type = this.selectedType;
        return type ? type.fields.find((field) => field.type === kind) : undefined;
    }

    get typeMenuOpen() {
        return this.openMenu === 'type';
    }

    get typeMenuExpanded() {
        return String(this.typeMenuOpen);
    }

    get typeButtonClass() {
        return this.typeMenuOpen ? 'select-btn select-btn_open' : 'select-btn';
    }

    get projectMenuOpen() {
        return this.openMenu === 'project';
    }

    get projectMenuExpanded() {
        return String(this.projectMenuOpen);
    }

    get projectField() {
        return this.fieldOfType('project');
    }

    get projectOptions() {
        const field = this.projectField;
        return field && field.options ? field.options : [];
    }

    get projectValue() {
        const field = this.projectField;
        return field ? this.values[field.name] : undefined;
    }

    get projectMenuOptions() {
        return this.projectOptions.map((option) => ({
            ...option,
            selected: option.value === this.projectValue ? 'true' : 'false',
            cssClass: option.value === this.projectValue ? 'menu-option menu-option_selected' : 'menu-option'
        }));
    }

    get noProjects() {
        return this.projectOptions.length === 0;
    }

    get projectLabel() {
        const chosen = this.projectOptions.find((option) => option.value === this.projectValue);
        if (chosen) {
            return chosen.label;
        }
        return this.projectField && this.projectField.placeholder ? this.projectField.placeholder : 'Select';
    }

    get projectValueClass() {
        return this.projectValue ? 'select-value' : 'select-value select-value_placeholder';
    }

    get registrationFields() {
        const type = this.selectedType;
        if (!type) {
            return [];
        }
        return type.fields.map((field) => {
            const value = this.values[field.name] || '';
            const error = this.fieldError(field, value);
            return {
                ...field,
                key: `${type.value}-${field.name}`,
                inputId: `reg-${field.name}`,
                value,
                error,
                invalid: error ? 'true' : 'false',
                ariaRequired: field.required ? 'true' : 'false',
                inputType: field.type === 'email' || field.type === 'tel' ? field.type : 'text',
                inputClass: error ? 'text-input text-input_error' : 'text-input',
                selectClass: `${this.projectMenuOpen ? 'select-btn select-btn_open' : 'select-btn'}${error ? ' select-btn_error' : ''}`,
                autocomplete: field.autocomplete || 'off',
                isUpload: field.type === 'upload',
                isProject: field.type === 'project'
            };
        });
    }

    // Salesforce's verdict shows until the field changes; the form's own checks once Submit has been pressed
    fieldError(field, value) {
        if (this.serverErrors[field.name]) {
            return this.serverErrors[field.name];
        }
        return this.submitAttempted ? this.errorFor(field, value) : undefined;
    }

    errorFor(field, value) {
        if (field.type === 'upload') {
            return undefined;
        }
        const text = cleanText(value);
        if (!text) {
            if (!field.required) {
                return undefined;
            }
            return field.type === 'project' ? 'Choose a project.' : 'This field is required.';
        }
        if (field.type !== 'project' && field.maxLength && text.length > field.maxLength) {
            return `Use ${field.maxLength} characters or fewer.`;
        }
        if (field.type === 'email' && !EMAIL_PATTERN.test(text)) {
            return 'Enter a valid email address.';
        }
        if (field.type === 'tel' && !isPhone(text)) {
            return 'Enter a valid phone number.';
        }
        return undefined;
    }

    clearServerError(name) {
        if (this.serverErrors[name]) {
            const errors = { ...this.serverErrors };
            delete errors[name];
            this.serverErrors = errors;
        }
    }

    // ---------- documents ----------
    get uploadField() {
        return this.fieldOfType('upload');
    }

    get fileTypes() {
        return this.form && this.form.fileTypes ? this.form.fileTypes : [];
    }

    get maxFileBytes() {
        return this.form && this.form.maxFileSizeMb ? this.form.maxFileSizeMb * BYTES_PER_MB : undefined;
    }

    get maxFileSizeText() {
        return this.form && this.form.maxFileSizeMb ? `${Number(this.form.maxFileSizeMb)} MB` : '';
    }

    get fileAccept() {
        return this.fileTypes.length ? this.fileTypes.map((type) => `.${type}`).join(',') : undefined;
    }

    get fileTypesText() {
        const types = this.fileTypes;
        if (!types.length) {
            return 'any file type';
        }
        return types.length === 1 && types[0] === 'pdf' ? 'PDF documents only' : `${typesText(types)} files only`;
    }

    get fileLimitText() {
        return this.maxFileSizeText ? ` (Max file size: ${this.maxFileSizeText} per file)` : '';
    }

    // "PDF documents only (Max file size: 10 MB per file)", as in the design, from the document rules
    get fileRulesText() {
        const text = this.fileTypesText;
        return `${text.charAt(0).toUpperCase()}${text.slice(1)}${this.fileLimitText}`;
    }

    get dropzoneHint() {
        return `Upload ${this.fileTypesText}${this.fileLimitText}`;
    }

    get uploadMissing() {
        const field = this.uploadField;
        return this.submitAttempted && Boolean(field && field.required) && this.files.length === 0;
    }

    get uploadMessage() {
        const field = this.uploadField;
        if (this.uploadError) {
            return this.uploadError;
        }
        if (field && this.serverErrors[field.name]) {
            return this.serverErrors[field.name];
        }
        return this.uploadMissing ? 'Upload at least one document.' : undefined;
    }

    get fileRows() {
        return this.files.map((file) => ({
            ...file,
            itemClass: `file-item file-item_${file.state}`,
            isUploading: file.state === 'uploading',
            isDone: file.state === 'done',
            canRemove: file.state !== 'done' && file.state !== 'uploading' && !this.isSubmitting
        }));
    }

    setFileState(key, state) {
        this.files = this.files.map((file) => (file.key === key ? { ...file, state } : file));
    }

    get dropzoneClass() {
        let css = 'dropzone';
        if (this.dragOver) {
            css += ' dropzone_active';
        }
        if (this.uploadMessage) {
            css += ' dropzone_error';
        }
        return css;
    }

    get hasFiles() {
        return this.files.length > 0;
    }

    // Before a type is chosen the design leaves room under the list for its options
    get termsClass() {
        return this.registrationType ? 'terms' : 'terms terms_roomy';
    }

    get submitDisabled() {
        return !this.registrationType || !this.termsAccepted || this.isSubmitting || !this.form;
    }

    get submitLabel() {
        if (this.isSubmitting) {
            return this.progressText || 'Submitting…';
        }
        return this.ticket ? 'Retry Upload' : 'Submit For Approval';
    }

    handleTermsChange(event) {
        this.termsAccepted = event.target.checked;
    }

    handleFieldInput(event) {
        const name = event.target.dataset.name;
        this.values = { ...this.values, [name]: event.target.value };
        this.clearServerError(name);
    }

    handleMenuToggle(event) {
        if (this.formLocked) {
            return;
        }
        const menu = event.currentTarget.dataset.menu;
        this.openMenu = this.openMenu === menu ? null : menu;
        if (this.openMenu) {
            this.focusMenuOption(menu);
        }
    }

    focusMenuOption(menu) {
        const selected = menu === 'type' ? this.registrationType : this.projectValue;
        this.pendingFocus = selected
            ? `.menu-option[data-menu="${menu}"][data-value="${selected}"]`
            : `.menu-option[data-menu="${menu}"]`;
    }

    handleMenuButtonKeyDown(event) {
        if (!this.formLocked && (event.key === 'ArrowDown' || event.key === 'ArrowUp')) {
            event.preventDefault();
            const menu = event.currentTarget.dataset.menu;
            this.openMenu = menu;
            this.focusMenuOption(menu);
        }
    }

    // Keeps focus on the list while an option is clicked, so the menu does not close before the click
    handleOptionMouseDown(event) {
        event.preventDefault();
    }

    handleMenuSelect(event) {
        const { menu, value } = event.currentTarget.dataset;
        if (menu === 'type') {
            if (this.registrationType !== value) {
                this.registrationType = value;
                this.submitAttempted = false;
                this.serverErrors = {};
                this.submitError = undefined;
                this.files = [];
                this.fileObjects.clear();
                this.uploadError = undefined;
                this.prefill();
            }
        } else if (this.projectField) {
            this.values = { ...this.values, [this.projectField.name]: value };
            this.clearServerError(this.projectField.name);
        }
        this.openMenu = null;
        this.pendingFocus = `.select-btn[data-menu="${menu}"]`;
    }

    handleMenuOptionKeyDown(event) {
        const menu = event.currentTarget.dataset.menu;
        const options = Array.from(this.template.querySelectorAll(`.menu-option[data-menu="${menu}"]`));
        const index = options.indexOf(event.currentTarget);
        if (event.key === 'ArrowDown') {
            event.preventDefault();
            options[Math.min(index + 1, options.length - 1)].focus();
        } else if (event.key === 'ArrowUp') {
            event.preventDefault();
            options[Math.max(index - 1, 0)].focus();
        } else if (event.key === 'Escape') {
            event.preventDefault();
            this.openMenu = null;
            this.pendingFocus = `.select-btn[data-menu="${menu}"]`;
        }
    }

    handleMenuFocusOut(event) {
        const next = event.relatedTarget;
        if (!next || !event.currentTarget.contains(next)) {
            this.openMenu = null;
        }
    }

    // The email typed on the login page fills the chosen type's email field
    prefill() {
        const field = this.fieldOfType('email');
        if (this.prefillEmail && field && !this.values[field.name]) {
            this.values = { ...this.values, [field.name]: this.prefillEmail };
        }
    }

    handleChooseFiles() {
        const input = this.template.querySelector('.file-input');
        if (input) {
            input.click();
        }
    }

    handleFilesChosen(event) {
        this.addFiles(event.target.files);
        event.target.value = '';
    }

    handleDragOver(event) {
        event.preventDefault();
        this.dragOver = !this.isSubmitting;
    }

    handleDragLeave() {
        this.dragOver = false;
    }

    handleDrop(event) {
        event.preventDefault();
        this.dragOver = false;
        this.addFiles(event.dataTransfer ? event.dataTransfer.files : null);
    }

    // Keeps the files that suit the document rules; they are uploaded once the registration is saved
    addFiles(fileList) {
        if (this.isSubmitting) {
            return;
        }
        const known = new Set(this.files.map((file) => file.key));
        const maxFiles = this.form && this.form.maxFiles ? this.form.maxFiles : undefined;
        const added = [];
        const refused = [];
        const replaced = new Set();
        Array.from(fileList || []).forEach((file) => {
            const key = `${file.name}-${file.size}-${file.lastModified}`;
            if (known.has(key)) {
                // Choosing a file again replaces its row when that row could not be read or was refused
                const row = this.files.find((item) => item.key === key);
                if (row && row.state === 'failed') {
                    this.fileObjects.set(key, file);
                    replaced.add(key);
                }
                return;
            }
            if (this.fileTypes.length && !this.fileTypes.includes(extensionOf(file.name))) {
                refused.push(`${file.name} is not a ${typesText(this.fileTypes)} file`);
            } else if (this.maxFileBytes && file.size > this.maxFileBytes) {
                refused.push(`${file.name} is larger than ${this.maxFileSizeText}`);
            } else if (!file.size) {
                refused.push(`${file.name} is empty`);
            } else if (maxFiles && this.files.length + added.length >= maxFiles) {
                refused.push(`${file.name} was not added: up to ${maxFiles} documents can be uploaded`);
            } else {
                known.add(key);
                this.fileObjects.set(key, file);
                added.push({
                    key,
                    name: file.name,
                    bytes: file.size,
                    size: formatSize(file.size),
                    removeLabel: `Remove ${file.name}`,
                    state: 'ready'
                });
            }
        });
        this.files = [...this.files.map((file) => (replaced.has(file.key) ? { ...file, state: 'ready' } : file)), ...added];
        this.uploadError = refused.length ? `${refused.join('; ')}.` : undefined;
        if ((added.length || replaced.size) && this.uploadField) {
            this.clearServerError(this.uploadField.name);
        }
    }

    handleRemoveFile(event) {
        const key = event.currentTarget.dataset.key;
        this.files = this.files.filter((file) => file.key !== key);
        this.fileObjects.delete(key);
        this.uploadError = undefined;
        if (this.uploadField) {
            this.clearServerError(this.uploadField.name);
        }
    }

    async handleSubmitRegistration() {
        if (this.submitDisabled) {
            return;
        }
        this.submitAttempted = true;
        this.submitError = undefined;
        // Refused files and failed uploads are notices only; a missing or invalid document stops the registration
        const uploadField = this.uploadField;
        const documentsProblem = this.uploadMissing || Boolean(uploadField && this.serverErrors[uploadField.name]);
        // Before the registration is saved, a document marked in red would only fail again
        const redRows = !this.ticket && this.files.some((file) => file.state === 'failed');
        if (redRows && !documentsProblem) {
            this.uploadError = 'Remove the documents marked in red, or choose them again.';
        }
        if (this.registrationFields.some((field) => field.error) || documentsProblem || redRows) {
            this.focusFirstError();
            return;
        }
        this.isSubmitting = true;
        this.uploadError = undefined;
        try {
            if (!this.ticket && !(await this.saveRegistration())) {
                return;
            }
            const failed = await this.uploadDocuments();
            if (failed.length) {
                this.uploadError = failed.join(' ');
                this.submitError = 'Your details were received, but some documents did not upload. Press Retry Upload to send them again.';
                this.flashError();
                return;
            }
            this.step = STEP.SUBMITTED;
        } catch (error) {
            this.submitError = messageOf(error);
            this.flashError();
        } finally {
            this.isSubmitting = false;
            this.progressText = undefined;
        }
    }

    focusFirstError() {
        this.pendingFocus = '.text-input_error, .select-btn_error, .dropzone_error .upload-link';
        this.flashError();
    }

    // Creates the partner's Account and Contact together with the first document, so that a registration is never saved
    // without one; false when Salesforce found something to fix first
    async saveRegistration() {
        const values = {};
        this.selectedType.fields
            .filter((field) => field.type !== 'upload')
            .forEach((field) => {
                const value = cleanText(this.values[field.name]);
                if (value) {
                    values[field.name] = value;
                }
            });
        const documents = this.files.map((file) => ({ name: file.name, size: file.bytes }));
        const first = this.files[0];
        if (first) {
            try {
                documents[0].base64Data = await readAsBase64(this.fileObjects.get(first.key), first.name);
            } catch (error) {
                this.setFileState(first.key, 'failed');
                this.uploadError = messageOf(error);
                this.focusFirstError();
                return false;
            }
            this.setFileState(first.key, 'uploading');
        }
        this.progressText = this.files.length > 1 ? this.uploadProgress(first) : 'Submitting…';
        let result;
        try {
            result = await register({ registrationType: this.registrationType, values, documents });
        } catch (error) {
            if (first) {
                this.setFileState(first.key, 'ready');
            }
            if (isConnectionError(error)) {
                this.registrationInterrupted = true;
            }
            throw error;
        }
        const status = result ? result.status : undefined;
        if (status === 'REGISTERED' && result.ticket) {
            this.ticket = result.ticket;
            this.documentsInSharePoint = result.documentsInSharePoint === true;
            if (first) {
                this.setFileState(first.key, 'done');
            }
            return true;
        }
        if (result && result.pendingRegistration && this.registrationInterrupted) {
            // After a lost answer the waiting registration is most likely the one just sent, saved with its first
            // document only; anyone else is told under the email field that the email is already waiting for approval
            this.documentsMayBeMissing = this.files.length > 1;
            this.step = STEP.UNDER_REVIEW;
            return false;
        }
        this.serverErrors = (result && result.fieldErrors) || {};
        if (first) {
            // The first document's own problem (a damaged or renamed file) marks its row
            const documentsError = this.uploadField && this.serverErrors[this.uploadField.name];
            this.setFileState(first.key, documentsError && documentsError.startsWith(first.name) ? 'failed' : 'ready');
        }
        if (!Object.keys(this.serverErrors).length) {
            this.submitError = 'Your registration could not be sent. Please try again.';
        }
        this.focusFirstError();
        return false;
    }

    // "Uploading document 2 of 3…", counted over all the registration's documents
    uploadProgress(file) {
        const position = this.files.findIndex((item) => item.key === file.key) + 1;
        return `Uploading document ${position} of ${this.files.length}…`;
    }

    // One document into the registration's SharePoint folder: an upload handle, the file in chunks, then its Sub Document.
    // The handle stands for the SharePoint session, which Salesforce keeps to itself.
    async uploadToSharePoint(file) {
        const blob = this.fileObjects.get(file.key);
        const total = blob.size;
        const handle = await startDocumentUpload({ ticket: this.ticket, fileName: file.name, size: total });
        let itemId;
        for (let start = 0; start < total; start += SHAREPOINT_CHUNK) {
            const end = Math.min(start + SHAREPOINT_CHUNK, total);
            // eslint-disable-next-line no-await-in-loop
            const base64Chunk = await readAsBase64(blob.slice(start, end), file.name);
            // eslint-disable-next-line no-await-in-loop
            const result = await withRetry(() =>
                uploadDocumentChunk({ ticket: this.ticket, handle, base64Chunk, startByte: start, endByte: end })
            );
            if (result && result.complete) {
                itemId = result.itemId;
            }
        }
        if (!itemId) {
            throw new Error(`${file.name}: SharePoint did not confirm the upload. Please try again.`);
        }
        await withRetry(() => finishDocumentUpload({ ticket: this.ticket, handle, itemId }));
    }

    // Uploads each document that is not uploaded yet, one at a time; the problems of those that failed
    async uploadDocuments() {
        const pending = this.files.filter((file) => file.state !== 'done');
        const failed = [];
        for (let index = 0; index < pending.length; index++) {
            const file = pending[index];
            this.progressText = this.uploadProgress(file);
            this.setFileState(file.key, 'uploading');
            try {
                if (this.documentsInSharePoint) {
                    // eslint-disable-next-line no-await-in-loop
                    await this.uploadToSharePoint(file);
                } else {
                    // eslint-disable-next-line no-await-in-loop
                    const base64Data = await readAsBase64(this.fileObjects.get(file.key), file.name);
                    // eslint-disable-next-line no-await-in-loop
                    await uploadDocument({ ticket: this.ticket, fileName: file.name, base64Data });
                }
                this.setFileState(file.key, 'done');
            } catch (error) {
                this.setFileState(file.key, 'failed');
                const message = messageOf(error);
                failed.push(message.startsWith(file.name) ? message : `${file.name}: ${message}`);
            }
        }
        return failed;
    }

    // ---------- status screens ----------
    get statusIconUrl() {
        const status = STATUS[this.step];
        return `${LOGIN_ASSETS}/${status ? status.icon : 'status-review.png'}`;
    }

    get statusTitle() {
        return STATUS[this.step] ? STATUS[this.step].title : '';
    }

    get statusText() {
        return STATUS[this.step] ? STATUS[this.step].text : '';
    }

    get statusNote() {
        return this.step === STEP.UNDER_REVIEW && this.documentsMayBeMissing
            ? 'Some of your documents may not have reached us because the connection was interrupted. Please send them to the JKP CP team.'
            : undefined;
    }

    // ---------- Terms of Service / Privacy Policy ----------
    get docOpen() {
        return this.doc !== null;
    }

    get docTitle() {
        return this.doc === 'terms' ? 'Terms of Service' : 'Privacy Policy';
    }

    get docHtml() {
        return this.doc === 'terms' ? this.termsHtml : null;
    }

    get docNote() {
        return this.doc === 'terms'
            ? 'The Terms of Service could not be loaded. Please try again later.'
            : 'Our Privacy Policy will be published here soon. For any questions about how we use your information, please contact the JKP CP team.';
    }

    async handleOpenDoc(event) {
        // The links sit inside the checkbox label: opening a document must not tick the box
        event.preventDefault();
        event.stopPropagation();
        this.docOpener = event.currentTarget;
        this.doc = event.currentTarget.dataset.doc;
        this.pendingFocus = '.modal-close';
        if (this.doc === 'terms' && this.termsHtml === undefined) {
            this.docLoading = true;
            try {
                const info = await getChannelPartnerInfo();
                this.termsHtml = info && info.termsAndConditions ? info.termsAndConditions : null;
            } catch (error) {
                this.termsHtml = null;
            } finally {
                this.docLoading = false;
            }
        }
    }

    handleCloseDoc() {
        this.doc = null;
        if (this.docOpener) {
            this.docOpener.focus();
            this.docOpener = undefined;
        }
    }

    handleModalKeyDown(event) {
        if (event.key === 'Escape') {
            this.handleCloseDoc();
        }
    }
}