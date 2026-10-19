import { LightningElement } from 'lwc';
import { loadStyle } from 'lightning/platformResourceLoader';
import basePath from '@salesforce/community/basePath';
import CP_FONTS from '@salesforce/resourceUrl/customerPortalFonts';
import LOGIN_ASSETS from '@salesforce/resourceUrl/customerPortalLoginAssets';
import login from '@salesforce/apex/CustomerPortalLoginController.login';
import reportIssue from '@salesforce/apex/CustomerPortalLoginController.reportIssue';

// The same limits as CustomerPortalLoginController
const MAX_DESCRIPTION = 2000;
const MAX_EMAIL = 80;
const MAX_MOBILE = 40;
const MIN_PHONE_DIGITS = 9;
const MAX_PHONE_DIGITS = 15;
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const PHONE_PATTERN = /^\+?[0-9 ().-]+$/;

// Everything the page shows (no Custom Labels)
const TEXT = {
    LOGO_LABEL: 'John Keells Properties - Creating New Worlds',
    USERNAME: 'Username',
    USERNAME_PLACEHOLDER: 'Enter Username',
    PASSWORD: 'Password',
    PASSWORD_PLACEHOLDER: 'Enter Password',
    SHOW_PASSWORD: 'Show password',
    FORGOT_PASSWORD: 'Forgot Password?',
    LOGIN: 'Login',
    FACING_ISSUE: 'Facing an issue?',
    EMAIL: 'Email',
    EMAIL_PLACEHOLDER: 'Enter Email',
    MOBILE: 'Mobile number',
    MOBILE_PLACEHOLDER: 'Enter mobile number',
    ISSUE: 'Please let us know where we went wrong.',
    ISSUE_PLACEHOLDER: 'Please let us know where we went wrong.',
    SUBMIT: 'Submit',
    BACK: 'Back',
    SUBMITTED_TITLE: 'Submitted Successfully.',
    SUBMITTED_TEXT_LINE_1: 'Please wait while our',
    SUBMITTED_TEXT_LINE_2: 'executive connects with you.',
    CLOSE: 'Close',
    EMAIL_INVALID: 'Enter a valid email address.',
    MOBILE_INVALID: 'Enter a valid mobile number.',
    ISSUE_TOO_LONG: `Please describe the issue in ${MAX_DESCRIPTION} characters or fewer.`,
    GENERIC_ERROR: 'Something went wrong. Please try again.',
    CONNECTION_ERROR: 'The connection was interrupted. Please check your internet connection and try again.'
};

const STEP = {
    LOGIN: 'login',
    ISSUE: 'issue'
};

function rawMessageOf(error) {
    return error && error.body && error.body.message ? error.body.message : error && error.message;
}

// A request that never got its answer (the connection dropped) gets a plain explanation instead of the framework's text
function messageOf(error) {
    const message = rawMessageOf(error) || '';
    if (/failed to get error from response|failed to fetch|networkerror|load failed/i.test(message)) {
        return TEXT.CONNECTION_ERROR;
    }
    return message || TEXT.GENERIC_ERROR;
}

// Digits with spaces, brackets, dashes or dots: 9 to 15 digits without a leading 0 (as the controller checks)
function isMobile(value) {
    const digits = value.replace(/\D/g, '').replace(/^0+/, '').length;
    return PHONE_PATTERN.test(value) && digits >= MIN_PHONE_DIGITS && digits <= MAX_PHONE_DIGITS;
}

function cssUrl(path) {
    return `url("${path}")`;
}

// The Customer Portal's login page (site SFA), as in the Figma design pages 1-5: the family photo, the logo, username and
// password. Customers log in through Salesforce's own site login (CustomerPortalLoginController.login), so the session
// is their customer community user's. "Forgot Password?" opens the site's standard Forgot Password page. "Facing an
// issue?" opens a short form (email, mobile number, what went wrong) that is saved as a Case, then a confirmation popup.
export default class CustomerPortalLogin extends LightningElement {
    text = TEXT;
    maxDescription = MAX_DESCRIPTION;

    step = STEP.LOGIN;
    username = '';
    password = '';
    showPassword = false;
    loginError;
    isBusy = false;

    email = '';
    mobile = '';
    issueText = '';
    emailError;
    mobileError;
    issueTextError;
    issueError;
    isSending = false;
    showSubmitted = false;

    // Element to focus after the next render (a new screen, the popup)
    pendingFocus;

    photoStyle = `background-image: ${cssUrl(`${LOGIN_ASSETS}/photo.jpg`)};`;
    logoStyle = `background-image: ${cssUrl(`${LOGIN_ASSETS}/logo.svg`)};`;
    submittedIconStyle = `background-image: ${cssUrl(`${LOGIN_ASSETS}/submitted.png`)};`;

    connectedCallback() {
        // JKP DIN (the portal font), as the customer portal's shell loads it
        loadStyle(this, `${CP_FONTS}/fonts.css`).catch(() => {
            // The fallback fonts are used if the fonts cannot be loaded
        });
    }

    renderedCallback() {
        if (this.pendingFocus) {
            const target = this.template.querySelector(`[data-id="${this.pendingFocus}"]`);
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

    // Where to go after logging in: the page that sent the customer here, or the portal home
    get startUrl() {
        let target = null;
        try {
            target = new URL(window.location.href).searchParams.get('startURL');
        } catch (e) {
            target = null;
        }
        return target && target.startsWith('/') && !target.startsWith('//') ? target : `${basePath}/`;
    }

    // Salesforce's own forgot-password page of this site
    get forgotPasswordUrl() {
        return `${basePath}/ForgotPassword`;
    }

    // ---------- login ----------
    get usernameClass() {
        return this.loginError ? 'cp-input login__input cp-input_invalid' : 'cp-input login__input';
    }

    get passwordClass() {
        return this.loginError
            ? 'cp-input login__input login__input_password cp-input_invalid'
            : 'cp-input login__input login__input_password';
    }

    get loginInvalid() {
        return this.loginError ? 'true' : 'false';
    }

    get busyState() {
        return String(this.isBusy);
    }

    get passwordType() {
        return this.showPassword ? 'text' : 'password';
    }

    get passwordShownState() {
        return String(this.showPassword);
    }

    // As in the design: a grey eye while the field is empty, a crossed-out eye while a typed password is hidden
    get showEyeOff() {
        return Boolean(this.password) && !this.showPassword;
    }

    get eyeClass() {
        return this.password ? 'login__eye' : 'login__eye login__eye_empty';
    }

    // Grey until both fields are filled, as in the design
    get loginDisabled() {
        return this.isBusy || !this.username.trim() || !this.password;
    }

    // Stays navy (with a spinner) while Salesforce answers
    get loginButtonClass() {
        return this.isBusy ? 'cp-btn cp-btn_lg cp-btn_block login__submit login__submit_busy' : 'cp-btn cp-btn_lg cp-btn_block login__submit';
    }

    handleUsernameInput(event) {
        this.username = event.target.value;
        this.loginError = undefined;
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
            const url = await login({ username: this.username.trim(), password: this.password, startUrl: this.startUrl });
            if (url) {
                // Stays busy while the browser opens the portal
                window.location.assign(url);
                return;
            }
            this.isBusy = false;
            this.loginError = TEXT.GENERIC_ERROR;
        } catch (error) {
            // Salesforce's own message (wrong username or password, a locked login, ...)
            this.isBusy = false;
            this.loginError = messageOf(error);
            this.password = '';
            this.pendingFocus = 'password';
        }
    }

    handleOpenIssue() {
        this.step = STEP.ISSUE;
        this.loginError = undefined;
        this.pendingFocus = 'email';
    }

    // ---------- facing an issue ----------
    get emailClass() {
        return this.emailError ? 'cp-input login__input cp-input_invalid' : 'cp-input login__input';
    }

    get mobileClass() {
        return this.mobileError ? 'cp-input login__input cp-input_invalid' : 'cp-input login__input';
    }

    get issueTextClass() {
        return this.issueTextError ? 'cp-textarea login__textarea cp-input_invalid' : 'cp-textarea login__textarea';
    }

    get emailInvalid() {
        return this.emailError ? 'true' : 'false';
    }

    get mobileInvalid() {
        return this.mobileError ? 'true' : 'false';
    }

    get issueTextInvalid() {
        return this.issueTextError ? 'true' : 'false';
    }

    get sendingState() {
        return String(this.isSending);
    }

    // Grey until the three fields are filled, as in the design
    get submitDisabled() {
        return this.isSending || !this.email.trim() || !this.mobile.trim() || !this.issueText.trim();
    }

    get submitButtonClass() {
        const base = 'cp-btn cp-btn_lg cp-btn_block login__submit login__submit_issue';
        return this.isSending ? `${base} login__submit_busy` : base;
    }

    handleEmailInput(event) {
        this.email = event.target.value;
        this.emailError = undefined;
        this.issueError = undefined;
    }

    handleMobileInput(event) {
        this.mobile = event.target.value;
        this.mobileError = undefined;
        this.issueError = undefined;
    }

    handleIssueTextInput(event) {
        this.issueText = event.target.value;
        this.issueTextError = undefined;
        this.issueError = undefined;
    }

    // The same checks as the controller, so most mistakes are shown without a round trip
    validateIssue() {
        const email = this.email.trim();
        const mobile = this.mobile.trim();
        this.emailError = email.length > MAX_EMAIL || !EMAIL_PATTERN.test(email) ? TEXT.EMAIL_INVALID : undefined;
        this.mobileError = mobile.length > MAX_MOBILE || !isMobile(mobile) ? TEXT.MOBILE_INVALID : undefined;
        this.issueTextError = this.issueText.trim().length > MAX_DESCRIPTION ? TEXT.ISSUE_TOO_LONG : undefined;
        const firstInvalid = [
            ['email', this.emailError],
            ['mobile', this.mobileError],
            ['issue-text', this.issueTextError]
        ].find(([, message]) => message);
        if (firstInvalid) {
            this.pendingFocus = firstInvalid[0];
            return false;
        }
        return true;
    }

    async handleSubmitIssue(event) {
        if (event) {
            event.preventDefault();
        }
        if (this.submitDisabled || !this.validateIssue()) {
            return;
        }
        this.isSending = true;
        this.issueError = undefined;
        try {
            await reportIssue({ email: this.email.trim(), mobile: this.mobile.trim(), description: this.issueText.trim() });
            this.isSending = false;
            // The popup opens over the login form, where closing it leaves the customer
            this.resetIssue();
            this.step = STEP.LOGIN;
            this.showSubmitted = true;
            this.pendingFocus = 'close-submitted';
        } catch (error) {
            this.isSending = false;
            this.issueError = messageOf(error);
        }
    }

    handleBack() {
        this.showLogin();
    }

    resetIssue() {
        this.email = '';
        this.mobile = '';
        this.issueText = '';
        this.emailError = undefined;
        this.mobileError = undefined;
        this.issueTextError = undefined;
        this.issueError = undefined;
    }

    showLogin() {
        this.resetIssue();
        this.step = STEP.LOGIN;
        this.pendingFocus = this.username ? 'password' : 'username';
    }

    // ---------- submitted popup ----------
    handleCloseSubmitted() {
        this.showSubmitted = false;
        this.showLogin();
    }

    // A click on the dimmed page around the popup closes it too
    handleOverlayClick(event) {
        if (event.target === event.currentTarget) {
            this.handleCloseSubmitted();
        }
    }

    // Escape closes the popup; Tab stays on its only control
    handleModalKeydown(event) {
        if (event.key === 'Escape') {
            event.preventDefault();
            this.handleCloseSubmitted();
        } else if (event.key === 'Tab') {
            event.preventDefault();
            const close = this.template.querySelector('[data-id="close-submitted"]');
            if (close) {
                close.focus();
            }
        }
    }
}