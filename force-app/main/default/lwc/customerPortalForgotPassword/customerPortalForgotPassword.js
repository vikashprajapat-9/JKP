import { LightningElement } from 'lwc';
import { loadStyle } from 'lightning/platformResourceLoader';
import basePath from '@salesforce/community/basePath';
import CP_FONTS from '@salesforce/resourceUrl/customerPortalFonts';
import LOGIN_ASSETS from '@salesforce/resourceUrl/customerPortalLoginAssets';
import requestPasswordReset from '@salesforce/apex/CustomerPortalLoginController.requestPasswordReset';

// The longest username Salesforce allows
const MAX_USERNAME = 80;

// Everything the page shows (no Custom Labels)
const TEXT = {
    LOGO_LABEL: 'John Keells Properties - Creating New Worlds',
    TITLE: 'Forgot Password?',
    INTRO: "Enter your username and we'll send a password reset link to the email address of your login.",
    USERNAME: 'Username',
    USERNAME_PLACEHOLDER: 'Enter Username',
    RESET: 'Reset Password',
    BACK_TO_LOGIN: 'Back to Login',
    SENT_TITLE: 'Check your email',
    // The confirmation reads: If <username> is a customer login, we've sent ...
    SENT_BEFORE: 'If ',
    SENT_AFTER: " is a customer login, we've sent a password reset link to the email address of that login.",
    SENT_NOTE: "The link works once and for a limited time. If the email doesn't arrive within a few minutes, check your Spam folder or try again.",
    TRY_AGAIN: 'Try again',
    USERNAME_REQUIRED: 'Enter your username.',
    GENERIC_ERROR: 'Something went wrong. Please try again.',
    CONNECTION_ERROR: 'The connection was interrupted. Please check your internet connection and try again.'
};

function rawMessageOf(error) {
    return error && error.body && error.body.message ? error.body.message : error && error.message;
}

// A request that never got its answer (the connection dropped) gets a plain explanation. Apart from the controller's
// own "Enter your username." every other failure gets the general message, so the page never says more about a
// username than the confirmation does.
function messageOf(error) {
    const message = rawMessageOf(error) || '';
    if (/failed to get error from response|failed to fetch|networkerror|load failed/i.test(message)) {
        return TEXT.CONNECTION_ERROR;
    }
    return message === TEXT.USERNAME_REQUIRED ? message : TEXT.GENERIC_ERROR;
}

function cssUrl(path) {
    return `url("${path}")`;
}

// The Customer Portal's Forgot Password page (site SFA) in the design of its login page: the family photo, the logo,
// the username and "Reset Password". CustomerPortalLoginController.requestPasswordReset emails a customer login the link
// to choose a new password. The confirmation is the same whether or not the username is a customer login, so the page
// never tells which usernames exist.
export default class CustomerPortalForgotPassword extends LightningElement {
    text = TEXT;
    maxUsername = MAX_USERNAME;

    username = '';
    // The username the last request was sent for, shown in the confirmation
    sentTo = '';
    error;
    isBusy = false;
    isSent = false;

    // Element to focus after the next render (the field after an error, the confirmation's title)
    pendingFocus;

    photoStyle = `background-image: ${cssUrl(`${LOGIN_ASSETS}/photo.jpg`)};`;
    logoStyle = `background-image: ${cssUrl(`${LOGIN_ASSETS}/logo.svg`)};`;
    sentIconStyle = `background-image: ${cssUrl(`${LOGIN_ASSETS}/submitted.png`)};`;

    connectedCallback() {
        // JKP DIN (the portal font), as the login page and the customer portal's shell load it
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

    // The site's login page
    get loginUrl() {
        return `${basePath}/login`;
    }

    get showForm() {
        return !this.isSent;
    }

    get isEmpty() {
        return !this.username.trim();
    }

    // Grey until the field is filled, as Login. The button stays clickable (aria-disabled, not disabled), so clicking it
    // with an empty field says what is missing.
    get emptyState() {
        return String(this.isEmpty);
    }

    get busyState() {
        return String(this.isBusy);
    }

    get invalidState() {
        return this.error ? 'true' : 'false';
    }

    get usernameClass() {
        return this.error ? 'cp-input forgot__input cp-input_invalid' : 'cp-input forgot__input';
    }

    // Navy with a spinner while Salesforce answers
    get submitClass() {
        const base = 'cp-btn cp-btn_lg cp-btn_block forgot__submit';
        if (this.isBusy) {
            return `${base} forgot__submit_busy`;
        }
        return this.isEmpty ? `${base} forgot__submit_empty` : base;
    }

    handleUsernameInput(event) {
        this.username = event.target.value;
        this.error = undefined;
    }

    async handleSubmit(event) {
        if (event) {
            event.preventDefault();
        }
        if (this.isBusy) {
            return;
        }
        const name = this.username.trim();
        if (!name) {
            this.error = TEXT.USERNAME_REQUIRED;
            this.pendingFocus = 'username';
            return;
        }
        this.isBusy = true;
        this.error = undefined;
        try {
            await requestPasswordReset({ username: name });
            this.sentTo = name;
            this.isSent = true;
            this.pendingFocus = 'sent-title';
        } catch (error) {
            this.error = messageOf(error);
            this.pendingFocus = 'username';
        } finally {
            this.isBusy = false;
        }
    }

    // Back to the form with the username kept, for example to correct a typo
    handleTryAgain() {
        this.isSent = false;
        this.error = undefined;
        this.pendingFocus = 'username';
    }
}