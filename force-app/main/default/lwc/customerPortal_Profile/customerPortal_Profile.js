import { LightningElement } from 'lwc';
import getProfile from '@salesforce/apex/CustomerPortalController.getProfile';
import updateProfile from '@salesforce/apex/CustomerPortalController.updateProfile';
import uploadProfilePicture from '@salesforce/apex/CustomerPortalController.uploadProfilePicture';
import changePassword from '@salesforce/apex/CustomerPortalController.changePassword';
import CP_ASSETS from '@salesforce/resourceUrl/customerPortalAssets';

// Phone country codes the server accepts (CustomerPortalController); Sri Lanka is the default
const COUNTRIES = [
    { code: '94', iso: 'LK', name: 'Sri Lanka' },
    { code: '91', iso: 'IN', name: 'India' },
    { code: '1', iso: 'US', name: 'United States' }
];
const COUNTRY_CODES = COUNTRIES.map((country) => country.code);
const DEFAULT_COUNTRY_CODE = '94';

// Field rules (the same as the Apex): lengths of Contact.FirstName / LastName / Email / Department
const MAX_FIRST_NAME = 40;
const MAX_LAST_NAME = 80;
const MAX_EMAIL = 80;
const MAX_DEPARTMENT = 80;
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const PHONE_PATTERN = /^\d{6,15}$/;
const PHONE_SEPARATORS = /[\s\-().]/g;
const PASSWORD_MIN = 8;

// Profile picture: checked before anything is read, then made at most 512 x 512 in the browser
const MAX_FILE_BYTES = 10 * 1024 * 1024;
const MAX_SIDE = 512;
const JPEG_QUALITY = 0.85;
const MAX_PNG_BYTES = 1024 * 1024;
const MAX_UPLOAD_BYTES = 1.5 * 1024 * 1024;
const PICTURE_TYPES = ['image/jpeg', 'image/png', 'image/jpg', 'image/pjpeg'];
const UPLOAD_TYPES = ['image/jpeg', 'image/png'];

// Field order for focusing the first field with an error
const FIELD_ORDER = ['firstName', 'lastName', 'email', 'phone', 'department'];
const FIELD_FOCUS = {
    firstName: 'first-name',
    lastName: 'last-name',
    email: 'email',
    phone: 'phone-number',
    department: 'department'
};
const PASSWORD_ORDER = ['current', 'next', 'confirm'];

// Eye icons of the login page: open eye (empty or shown), crossed-out eye (typed and hidden)
const EYE_PATH =
    'M10.17 12C10.17 12.46 10.36 12.91 10.69 13.24C11.01 13.57 11.46 13.75 11.92 13.75C12.39 13.75 12.83 13.57 13.16 13.24C13.49 12.91 13.67 12.46 13.67 12C13.67 11.54 13.49 11.09 13.16 10.76C12.83 10.43 12.39 10.25 11.92 10.25C11.46 10.25 11.01 10.43 10.69 10.76C10.36 11.09 10.17 11.54 10.17 12M18.71 11.6C17.23 8.48 14.99 6.91 11.98 6.91C8.98 6.91 6.74 8.48 5.26 11.6C5.2 11.72 5.17 11.86 5.17 12C5.17 12.14 5.2 12.28 5.26 12.4C6.74 15.52 8.98 17.09 11.98 17.09C14.99 17.09 17.23 15.52 18.71 12.4C18.83 12.15 18.83 11.85 18.71 11.6M11.92 14.75C10.4 14.75 9.17 13.52 9.17 12C9.17 10.48 10.4 9.25 11.92 9.25C13.44 9.25 14.67 10.48 14.67 12C14.67 13.52 13.44 14.75 11.92 14.75';
const EYE_OFF_PATH =
    'M11.94 13.84C12.4 13.84 12.85 13.66 13.17 13.33C13.5 13 13.69 12.56 13.69 12.09C13.69 12.04 13.68 11.99 13.68 11.94L11.79 13.84C11.84 13.84 11.89 13.84 11.94 13.84M17.73 6.68L17.06 6.01C17.04 5.99 17.01 5.98 16.97 5.98C16.94 5.98 16.91 5.99 16.89 6.01L15.18 7.72C14.24 7.24 13.18 7 12 7C9 7 6.76 8.56 5.28 11.69C5.22 11.82 5.19 11.96 5.19 12.1C5.19 12.23 5.22 12.37 5.28 12.5C5.87 13.74 6.58 14.74 7.41 15.49L5.76 17.14C5.74 17.16 5.72 17.2 5.72 17.23C5.72 17.26 5.74 17.29 5.76 17.32L6.43 17.99C6.45 18.01 6.48 18.02 6.51 18.02C6.55 18.02 6.58 18.01 6.6 17.99L17.73 6.86C17.74 6.85 17.75 6.83 17.76 6.82C17.76 6.8 17.77 6.79 17.77 6.77C17.77 6.75 17.76 6.74 17.76 6.72C17.75 6.71 17.74 6.69 17.73 6.68M9.19 12.09C9.19 11.62 9.31 11.15 9.54 10.74C9.78 10.33 10.12 9.98 10.52 9.74C10.93 9.49 11.39 9.36 11.87 9.35C12.34 9.33 12.81 9.44 13.23 9.67L12.47 10.43C12.17 10.33 11.84 10.32 11.53 10.39C11.21 10.47 10.93 10.63 10.7 10.86C10.47 11.09 10.31 11.37 10.24 11.68C10.16 12 10.17 12.32 10.27 12.63L9.51 13.39C9.3 12.99 9.19 12.55 9.19 12.09M18.72 11.69C18.17 10.53 17.52 9.59 16.76 8.86L14.51 11.11C14.7 11.61 14.74 12.15 14.63 12.67C14.52 13.19 14.26 13.66 13.88 14.04C13.51 14.41 13.03 14.67 12.51 14.78C11.99 14.89 11.45 14.85 10.95 14.66L9.04 16.57C9.93 16.98 10.92 17.19 12 17.19C15 17.19 17.24 15.62 18.72 12.5C18.78 12.37 18.81 12.23 18.81 12.09C18.81 11.95 18.78 11.82 18.72 11.69';
const CLOSE_PATH = 'M14 1.41L12.59 0L7 5.59L1.41 0L0 1.41L5.59 7L0 12.59L1.41 14L7 8.41L12.59 14L14 12.59L8.41 7L14 1.41Z';

const TEXT = {
    title: 'Profile',
    intro:
        'View and update your personal information, change your profile photo, and manage your account details ' +
        'including username and password. Keep your profile up-to-date to ensure smooth communication and access to ' +
        'all features provided by John Keels Properties . Stay current to make the most of your partnership and ' +
        'maximize your success.',
    loading: 'Loading profile',
    loadError: "We couldn't load your profile right now. Please try again in a moment.",
    retry: 'Try again',
    personal: 'Personal Information',
    account: 'Account Details',
    firstName: 'First Name',
    lastName: 'Last Name',
    email: 'Email ID',
    phone: 'Phone Number',
    countryCode: 'Country code',
    department: 'Department',
    username: 'Username',
    password: 'Password',
    passwordMask: '********',
    change: 'Change',
    changePassword: 'Change password',
    edit: 'Edit Profile',
    save: 'Save Profile',
    saving: 'Saving your profile',
    cancel: 'Cancel',
    addPhoto: 'Choose a profile photo',
    photoAlt: 'Profile photo',
    preparingPhoto: 'Preparing your photo',
    photoReady: 'New photo chosen. Select Save Profile to keep it.',
    photoType: 'Please choose a JPEG or PNG picture.',
    photoTooLarge: 'Please choose a picture smaller than 10 MB.',
    photoUnreadable: "We couldn't read this picture. Please choose another JPEG or PNG picture.",
    firstNameRequired: 'Please enter your first name.',
    firstNameTooLong: 'First name can have up to 40 characters.',
    lastNameRequired: 'Please enter your last name.',
    lastNameTooLong: 'Last name can have up to 80 characters.',
    emailRequired: 'Please enter your email address.',
    emailTooLong: 'Email address can have up to 80 characters.',
    emailInvalid: 'Please enter a valid email address, for example name@example.com.',
    countryInvalid: 'Please choose a country code.',
    phoneRequired: 'Please enter your phone number.',
    phoneInvalid: 'Please enter 6 to 15 digits, without the country code.',
    departmentTooLong: 'Department can have up to 80 characters.',
    saved: 'Your profile has been saved.',
    savedEmailPending:
        'Your profile has been saved. We have sent a confirmation link to your new email address; ' +
        'your email address changes once you open that link.',
    emailPendingNote: 'Please confirm your new email address with the link we sent to it.',
    saveFailed: "We couldn't save your profile. Please try again.",
    photoSaveFailed: "We couldn't save your profile photo. Please try again.",
    photoSavedDetailsFailed: "Your photo was saved, but we couldn't save your other changes. Please try again.",
    noAnswer: "We didn't get an answer from the server. Please check your internet connection and try again.",
    close: 'Close',
    pwTitle: 'Change Password',
    pwText: 'Enter your current password, then choose a new one.',
    pwCurrent: 'Current Password',
    pwNew: 'New Password',
    pwConfirm: 'Confirm New Password',
    pwRules: 'At least 8 characters, 1 letter and 1 number',
    pwShowCurrent: 'Show current password',
    pwShowNew: 'Show new password',
    pwShowConfirm: 'Show confirmed password',
    pwSubmit: 'Change Password',
    pwBusy: 'Changing your password',
    pwCurrentRequired: 'Please enter your current password.',
    pwNewRequired: 'Please enter a new password.',
    pwNewWeak: 'Use at least 8 characters, with at least 1 letter and 1 number.',
    pwSame: 'Your new password must be different from your current password.',
    pwConfirmRequired: 'Please enter your new password again.',
    pwMismatch: 'The new passwords do not match.',
    pwFailed: "We couldn't change your password. Please try again.",
    pwDoneTitle: 'Password Changed',
    pwDoneText: 'Your password has been changed. Use your new password the next time you log in.',
    pwDone: 'Done'
};

// Server messages written for people are shown as they are; technical ones get the screen's own message
const TECHNICAL_MESSAGE = /exception|first error|FIELD_|INVALID_|System\.|Apex|Script-thrown/i;
const NO_ANSWER_MESSAGE = /failed to get error from response|failed to fetch|networkerror|disconnected/i;

function trimText(value) {
    return value === undefined || value === null ? '' : String(value).trim();
}

function errorText(error, fallback) {
    const body = error && error.body;
    let message = '';
    if (Array.isArray(body)) {
        message = body
            .map((item) => item && item.message)
            .filter(Boolean)
            .join(' ');
    } else if (body) {
        if (typeof body.message === 'string') {
            message = body.message;
        }
        if (!message && Array.isArray(body.pageErrors) && body.pageErrors.length) {
            message = body.pageErrors[0].message || '';
        }
        if (!message && body.fieldErrors) {
            const lists = Object.values(body.fieldErrors).filter((list) => Array.isArray(list) && list.length);
            message = lists.length ? lists[0][0].message || '' : '';
        }
    }
    message = trimText(message);
    if (NO_ANSWER_MESSAGE.test(message)) {
        return TEXT.noAnswer;
    }
    if (!message || message.length > 300 || TECHNICAL_MESSAGE.test(message)) {
        return fallback;
    }
    return message;
}

function normalizeProfile(raw) {
    const data = raw || {};
    const firstName = trimText(data.firstName);
    const lastName = trimText(data.lastName);
    const photoUrl = data.photoUrl ? String(data.photoUrl) : null;
    return {
        firstName,
        lastName,
        fullName: trimText(data.fullName) || [firstName, lastName].filter(Boolean).join(' '),
        email: trimText(data.email),
        phoneCountryCode: trimText(data.phoneCountryCode).replace(/\D/g, ''),
        phoneNumber: trimText(data.phoneNumber),
        department: trimText(data.department),
        username: trimText(data.username),
        photoUrl,
        hasPhoto: data.hasPhoto === true || Boolean(photoUrl),
        emailPending: data.emailPending === true
    };
}

function draftFrom(profile) {
    return {
        firstName: profile.firstName,
        lastName: profile.lastName,
        email: profile.email,
        phoneCountryCode: COUNTRY_CODES.includes(profile.phoneCountryCode) ? profile.phoneCountryCode : DEFAULT_COUNTRY_CODE,
        phoneNumber: profile.phoneNumber,
        department: profile.department
    };
}

// What is sent to updateProfile: trimmed, the phone number as digits only
function cleanValues(draft) {
    return {
        firstName: trimText(draft.firstName),
        lastName: trimText(draft.lastName),
        email: trimText(draft.email),
        phoneCountryCode: trimText(draft.phoneCountryCode),
        phoneNumber: trimText(draft.phoneNumber).replace(PHONE_SEPARATORS, ''),
        department: trimText(draft.department)
    };
}

function validateProfile(values) {
    const errors = {};
    if (!values.firstName) {
        errors.firstName = TEXT.firstNameRequired;
    } else if (values.firstName.length > MAX_FIRST_NAME) {
        errors.firstName = TEXT.firstNameTooLong;
    }
    if (!values.lastName) {
        errors.lastName = TEXT.lastNameRequired;
    } else if (values.lastName.length > MAX_LAST_NAME) {
        errors.lastName = TEXT.lastNameTooLong;
    }
    if (!values.email) {
        errors.email = TEXT.emailRequired;
    } else if (values.email.length > MAX_EMAIL) {
        errors.email = TEXT.emailTooLong;
    } else if (!EMAIL_PATTERN.test(values.email)) {
        errors.email = TEXT.emailInvalid;
    }
    if (!COUNTRY_CODES.includes(values.phoneCountryCode)) {
        errors.phone = TEXT.countryInvalid;
    } else if (!values.phoneNumber) {
        errors.phone = TEXT.phoneRequired;
    } else if (!PHONE_PATTERN.test(values.phoneNumber)) {
        errors.phone = TEXT.phoneInvalid;
    }
    if (values.department.length > MAX_DEPARTMENT) {
        errors.department = TEXT.departmentTooLong;
    }
    return errors;
}

function validatePasswords(passwords) {
    const errors = {};
    if (!passwords.current) {
        errors.current = TEXT.pwCurrentRequired;
    }
    if (!passwords.next) {
        errors.next = TEXT.pwNewRequired;
    } else if (passwords.next.length < PASSWORD_MIN || !/[A-Za-z]/.test(passwords.next) || !/\d/.test(passwords.next)) {
        errors.next = TEXT.pwNewWeak;
    } else if (passwords.current && passwords.next === passwords.current) {
        errors.next = TEXT.pwSame;
    }
    if (!passwords.confirm) {
        errors.confirm = TEXT.pwConfirmRequired;
    } else if (passwords.next && passwords.confirm !== passwords.next) {
        errors.confirm = TEXT.pwMismatch;
    }
    return errors;
}

// grey eye while the field is empty, as on the login page
function eyeClass(value) {
    return value ? 'profile-pw__eye' : 'profile-pw__eye profile-pw__eye_empty';
}

// ---------- profile picture helpers ----------
function pictureType(file) {
    const type = trimText(file && file.type).toLowerCase();
    if (type) {
        return PICTURE_TYPES.includes(type) ? type : '';
    }
    // some systems give no type: fall back to the file name
    const name = trimText(file && file.name).toLowerCase();
    if (/\.png$/.test(name)) {
        return 'image/png';
    }
    return /\.jpe?g$/.test(name) ? 'image/jpeg' : '';
}

function splitDataUrl(dataUrl) {
    const match = /^data:([^;,]+);base64,(.*)$/.exec(dataUrl || '');
    return match ? { contentType: match[1].toLowerCase(), base64: match[2] } : null;
}

function base64Bytes(base64) {
    const padding = base64.endsWith('==') ? 2 : base64.endsWith('=') ? 1 : 0;
    return Math.floor((base64.length * 3) / 4) - padding;
}

function pictureFileName(originalName, contentType) {
    const base =
        trimText(originalName)
            .replace(/\.[^.]*$/, '')
            .replace(/[\\/:*?"<>|]+/g, ' ')
            .trim()
            .slice(0, 80) || 'Profile Picture';
    return base + (contentType === 'image/png' ? '.png' : '.jpg');
}

function readFileAsDataUrl(file) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(reader.result);
        reader.onerror = () => reject(reader.error || new Error('read failed'));
        reader.readAsDataURL(file);
    });
}

function loadImage(src) {
    return new Promise((resolve, reject) => {
        const image = new Image();
        image.onload = () => resolve(image);
        image.onerror = () => reject(new Error('decode failed'));
        image.src = src;
    });
}

function hasTransparency(context, width, height) {
    try {
        const pixels = context.getImageData(0, 0, width, height).data;
        for (let index = 3; index < pixels.length; index += 4) {
            if (pixels[index] < 255) {
                return true;
            }
        }
    } catch (error) {
        // unreadable pixels: treat as opaque (saved as JPEG on white)
    }
    return false;
}

// Keeps the centre square of the picture (what the round photo shows) at most 512 x 512: the account's Profile Picture
// formula shows the file in a 120 x 120 box, where a picture that is not square would look squashed.
// JPEG (quality 0.85, on white); a PNG with transparency stays PNG while it is at most 1 MB.
// Returns { dataUrl, base64, contentType }.
async function preparePicture(file, type) {
    const source = await readFileAsDataUrl(file);
    const image = await loadImage(source);
    const width = image.naturalWidth || image.width;
    const height = image.naturalHeight || image.height;
    if (!width || !height) {
        throw new Error('empty picture');
    }
    const side = Math.min(width, height);
    const target = Math.max(1, Math.round(Math.min(side, MAX_SIDE)));
    const canvas = document.createElement('canvas');
    canvas.width = target;
    canvas.height = target;
    const context = canvas.getContext('2d');
    if (!context) {
        throw new Error('no canvas');
    }
    context.imageSmoothingEnabled = true;
    context.imageSmoothingQuality = 'high';
    context.drawImage(image, (width - side) / 2, (height - side) / 2, side, side, 0, 0, target, target);

    let parts = null;
    let dataUrl = '';
    if (type === 'image/png' && hasTransparency(context, target, target)) {
        const png = canvas.toDataURL('image/png');
        const pngParts = splitDataUrl(png);
        if (pngParts && pngParts.contentType === 'image/png' && base64Bytes(pngParts.base64) <= MAX_PNG_BYTES) {
            parts = pngParts;
            dataUrl = png;
        }
    }
    if (!parts) {
        // JPEG has no transparency: the picture goes on white
        context.globalCompositeOperation = 'destination-over';
        context.fillStyle = '#ffffff';
        context.fillRect(0, 0, target, target);
        context.globalCompositeOperation = 'source-over';
        dataUrl = canvas.toDataURL('image/jpeg', JPEG_QUALITY);
        parts = splitDataUrl(dataUrl);
    }
    if (!parts || !UPLOAD_TYPES.includes(parts.contentType) || base64Bytes(parts.base64) > MAX_UPLOAD_BYTES) {
        throw new Error('picture could not be prepared');
    }
    return { dataUrl, base64: parts.base64, contentType: parts.contentType };
}

export default class CustomerPortal_Profile extends LightningElement {
    text = TEXT;
    closePath = CLOSE_PATH;
    eyePath = EYE_PATH;
    eyeOffPath = EYE_OFF_PATH;
    defaultPhoto = CP_ASSETS + '/avatar-default.png';

    isLoading = true;
    loadError = '';
    // What is saved (from CustomerPortalController); the form shows a copy (draft) while editing
    profile;
    draft;
    isEditing = false;
    isSaving = false;
    isPreparingPhoto = false;
    fieldErrors = {};
    formError = '';
    successMessage = '';
    photoError = '';
    // A chosen picture that is not saved yet: { base64, contentType, fileName }, shown at once from previewUrl
    pendingPhoto;
    previewUrl;
    failedAvatarSrc;

    // Change password popup; the typed passwords are cleared whenever it closes
    isPasswordOpen = false;
    isChangingPassword = false;
    passwordChanged = false;
    passwordError = '';
    passwordErrors = {};
    passwords = { current: '', next: '', confirm: '' };
    shown = { current: false, next: false, confirm: false };

    _photoToken = 0;
    _focusTarget;

    connectedCallback() {
        this.loadProfile();
    }

    disconnectedCallback() {
        this._photoToken++;
        this.resetPasswords();
    }

    renderedCallback() {
        const target = this._focusTarget;
        if (!target) {
            return;
        }
        this._focusTarget = undefined;
        const element = this.template.querySelector(`[data-id="${target}"]`);
        if (element && typeof element.focus === 'function') {
            element.focus();
        }
    }

    async loadProfile() {
        this.isLoading = true;
        this.loadError = '';
        try {
            const result = await getProfile();
            this.profile = normalizeProfile(result);
            // keeps the header avatar and name in step with the saved profile
            this.notifyShell();
        } catch (error) {
            this.profile = undefined;
            this.loadError = errorText(error, TEXT.loadError);
        } finally {
            this.isLoading = false;
        }
    }

    // ---------- view state ----------
    get showProfile() {
        return !this.isLoading && !this.loadError && Boolean(this.profile);
    }

    get isViewing() {
        return !this.isEditing;
    }

    get isBusy() {
        return this.isSaving || this.isPreparingPhoto;
    }

    // the saved values in view mode, the draft while editing
    get form() {
        return this.isEditing && this.draft ? this.draft : this.profile;
    }

    get avatarSrc() {
        const candidate = this.previewUrl || (this.profile && this.profile.photoUrl) || null;
        return candidate && candidate !== this.failedAvatarSrc ? candidate : this.defaultPhoto;
    }

    get photoHint() {
        return this.isEditing && this.pendingPhoto && !this.photoError ? TEXT.photoReady : '';
    }

    get showEmailNote() {
        return !this.isEditing && Boolean(this.profile && this.profile.emailPending);
    }

    get saveButtonClass() {
        return this.isSaving ? 'cp-btn profile-action profile-action_busy' : 'cp-btn profile-action';
    }

    get savingState() {
        return String(this.isSaving);
    }

    get savingStatus() {
        return this.isSaving ? TEXT.saving : '';
    }

    // input classes and aria-invalid per field (errors only while editing)
    get ui() {
        const errors = this.isEditing ? this.fieldErrors : {};
        const inputClass = (name) => (errors[name] ? 'cp-input cp-input_invalid' : 'cp-input');
        const invalid = (name) => (errors[name] ? 'true' : 'false');
        return {
            firstNameClass: inputClass('firstName'),
            firstNameInvalid: invalid('firstName'),
            lastNameClass: inputClass('lastName'),
            lastNameInvalid: invalid('lastName'),
            emailClass: inputClass('email'),
            emailInvalid: invalid('email'),
            phoneInvalid: invalid('phone'),
            departmentClass: inputClass('department'),
            departmentInvalid: invalid('department')
        };
    }

    // ---------- phone ----------
    get phoneCode() {
        return (this.form && this.form.phoneCountryCode) || '';
    }

    get isFlagLK() {
        return this.phoneCode === '94';
    }

    get isFlagIN() {
        return this.phoneCode === '91';
    }

    get isFlagUS() {
        return this.phoneCode === '1';
    }

    get countryOptions() {
        const selectedCode = this.phoneCode;
        return COUNTRIES.map((country) => ({
            code: country.code,
            label: country.name + ' (+' + country.code + ')',
            selected: country.code === selectedCode
        }));
    }

    get phoneCountryClass() {
        return this.isEditing ? 'profile-phone__country profile-phone__country_edit' : 'profile-phone__country';
    }

    get phoneBoxClass() {
        if (!this.isEditing) {
            return 'profile-phone profile-phone_readonly';
        }
        return this.fieldErrors.phone ? 'profile-phone profile-phone_invalid' : 'profile-phone';
    }

    // ---------- password popup ----------
    get passwordTitle() {
        return this.passwordChanged ? TEXT.pwDoneTitle : TEXT.pwTitle;
    }

    get pw() {
        const errors = this.passwordErrors;
        const inputClass = (name) =>
            errors[name] ? 'cp-input profile-pw__input cp-input_invalid' : 'cp-input profile-pw__input';
        return {
            currentType: this.shown.current ? 'text' : 'password',
            nextType: this.shown.next ? 'text' : 'password',
            confirmType: this.shown.confirm ? 'text' : 'password',
            currentShown: String(this.shown.current),
            nextShown: String(this.shown.next),
            confirmShown: String(this.shown.confirm),
            currentClass: inputClass('current'),
            nextClass: inputClass('next'),
            confirmClass: inputClass('confirm'),
            currentInvalid: errors.current ? 'true' : 'false',
            nextInvalid: errors.next ? 'true' : 'false',
            confirmInvalid: errors.confirm ? 'true' : 'false',
            currentEyeOff: Boolean(this.passwords.current) && !this.shown.current,
            nextEyeOff: Boolean(this.passwords.next) && !this.shown.next,
            confirmEyeOff: Boolean(this.passwords.confirm) && !this.shown.confirm,
            currentEyeClass: eyeClass(this.passwords.current),
            nextEyeClass: eyeClass(this.passwords.next),
            confirmEyeClass: eyeClass(this.passwords.confirm)
        };
    }

    get pwSubmitClass() {
        return this.isChangingPassword ? 'cp-btn cp-btn_lg profile-pw__submit profile-action_busy' : 'cp-btn cp-btn_lg profile-pw__submit';
    }

    get pwBusyState() {
        return String(this.isChangingPassword);
    }

    get pwStatus() {
        return this.isChangingPassword ? TEXT.pwBusy : '';
    }

    // ---------- loading ----------
    handleRetry() {
        this.loadProfile();
    }

    handleAvatarError() {
        const candidate = this.previewUrl || (this.profile && this.profile.photoUrl) || null;
        if (candidate) {
            this.failedAvatarSrc = candidate;
        }
    }

    // ---------- edit / save ----------
    handleEditProfile() {
        this.formError = '';
        this.successMessage = '';
        this.photoError = '';
        this.fieldErrors = {};
        this.draft = draftFrom(this.profile);
        this.isEditing = true;
        this._focusTarget = 'first-name';
    }

    handleCancelEdit() {
        if (this.isSaving) {
            return;
        }
        this._photoToken++;
        this.isPreparingPhoto = false;
        this.pendingPhoto = undefined;
        this.previewUrl = undefined;
        this.draft = undefined;
        this.fieldErrors = {};
        this.formError = '';
        this.photoError = '';
        this.isEditing = false;
        this._focusTarget = 'edit';
    }

    handleFieldInput(event) {
        const field = event.target.dataset.field;
        if (!field || !this.draft) {
            return;
        }
        this.draft = { ...this.draft, [field]: event.target.value };
        this.clearFieldError(field === 'phoneNumber' ? 'phone' : field);
    }

    handleCountryChange(event) {
        if (!this.draft) {
            return;
        }
        this.draft = { ...this.draft, phoneCountryCode: event.target.value };
        this.clearFieldError('phone');
    }

    clearFieldError(name) {
        if (this.fieldErrors[name]) {
            this.fieldErrors = { ...this.fieldErrors, [name]: '' };
        }
        this.formError = '';
    }

    async handleSaveProfile() {
        if (this.isBusy || !this.draft) {
            return;
        }
        this.formError = '';
        this.successMessage = '';
        const values = cleanValues(this.draft);
        const errors = validateProfile(values);
        const firstInvalid = FIELD_ORDER.find((name) => errors[name]);
        if (firstInvalid) {
            this.fieldErrors = errors;
            this._focusTarget = FIELD_FOCUS[firstInvalid];
            return;
        }
        this.fieldErrors = {};
        this.isSaving = true;
        let photoSaved = false;
        try {
            // the picture first (as a new version of the same file when there is one), then the fields
            if (this.pendingPhoto) {
                let uploaded;
                try {
                    uploaded = await uploadProfilePicture({
                        base64Data: this.pendingPhoto.base64,
                        fileName: this.pendingPhoto.fileName,
                        contentType: this.pendingPhoto.contentType
                    });
                } catch (error) {
                    this.formError = errorText(error, TEXT.photoSaveFailed);
                    return;
                }
                photoSaved = true;
                const savedPhotoUrl = normalizeProfile(uploaded).photoUrl || this.previewUrl;
                this.profile = { ...this.profile, photoUrl: savedPhotoUrl, hasPhoto: true };
                this.failedAvatarSrc = undefined;
                this.pendingPhoto = undefined;
                this.previewUrl = undefined;
            }

            const updated = normalizeProfile(await updateProfile(values));
            if (!updated.photoUrl && this.profile.photoUrl) {
                updated.photoUrl = this.profile.photoUrl;
                updated.hasPhoto = true;
            }
            this.profile = updated;
            this.draft = undefined;
            this.isEditing = false;
            this.successMessage = updated.emailPending ? TEXT.savedEmailPending : TEXT.saved;
            this.notifyShell();
            this._focusTarget = 'edit';
        } catch (error) {
            this.formError = errorText(error, photoSaved ? TEXT.photoSavedDetailsFailed : TEXT.saveFailed);
            if (photoSaved) {
                this.notifyShell();
            }
        } finally {
            this.isSaving = false;
        }
    }

    notifyShell() {
        if (!this.profile) {
            return;
        }
        this.dispatchEvent(
            new CustomEvent('profileupdated', {
                bubbles: true,
                composed: true,
                detail: { fullName: this.profile.fullName, photoUrl: this.profile.photoUrl || null }
            })
        );
    }

    // ---------- profile picture ----------
    handleAddPhotoClick() {
        const input = this.template.querySelector('[data-id="photo-input"]');
        if (input && !this.isSaving) {
            input.click();
        }
    }

    async handlePhotoSelected(event) {
        const input = event.target;
        const file = input.files && input.files[0];
        // lets the same file be chosen again
        try {
            input.value = '';
        } catch (error) {
            // read-only in some browsers
        }
        if (!file || !this.isEditing) {
            return;
        }
        this.photoError = '';
        this.formError = '';
        const type = pictureType(file);
        if (!type) {
            this.photoError = TEXT.photoType;
            return;
        }
        if (file.size > MAX_FILE_BYTES) {
            this.photoError = TEXT.photoTooLarge;
            return;
        }
        const token = ++this._photoToken;
        this.isPreparingPhoto = true;
        try {
            const picture = await preparePicture(file, type === 'image/png' ? 'image/png' : 'image/jpeg');
            if (token !== this._photoToken) {
                return;
            }
            this.pendingPhoto = {
                base64: picture.base64,
                contentType: picture.contentType,
                fileName: pictureFileName(file.name, picture.contentType)
            };
            this.previewUrl = picture.dataUrl;
        } catch (error) {
            if (token === this._photoToken) {
                this.photoError = TEXT.photoUnreadable;
            }
        } finally {
            if (token === this._photoToken) {
                this.isPreparingPhoto = false;
            }
        }
    }

    // ---------- change password ----------
    handleOpenPassword() {
        this.resetPasswords();
        this.passwordChanged = false;
        this.passwordError = '';
        this.passwordErrors = {};
        this.isPasswordOpen = true;
        this._focusTarget = 'pw-current';
    }

    handleClosePassword() {
        if (this.isChangingPassword) {
            return;
        }
        this.resetPasswords();
        this.passwordChanged = false;
        this.passwordError = '';
        this.passwordErrors = {};
        this.isPasswordOpen = false;
        this._focusTarget = 'change-password';
    }

    resetPasswords() {
        this.passwords = { current: '', next: '', confirm: '' };
        this.shown = { current: false, next: false, confirm: false };
    }

    handlePasswordInput(event) {
        const field = event.target.dataset.field;
        if (!PASSWORD_ORDER.includes(field)) {
            return;
        }
        this.passwords = { ...this.passwords, [field]: event.target.value };
        if (this.passwordErrors[field]) {
            this.passwordErrors = { ...this.passwordErrors, [field]: '' };
        }
        this.passwordError = '';
    }

    handleTogglePasswordShown(event) {
        const field = event.currentTarget.dataset.field;
        if (PASSWORD_ORDER.includes(field)) {
            this.shown = { ...this.shown, [field]: !this.shown[field] };
        }
    }

    async handleSubmitPassword(event) {
        if (event) {
            event.preventDefault();
        }
        if (this.isChangingPassword) {
            return;
        }
        this.passwordError = '';
        const errors = validatePasswords(this.passwords);
        const firstInvalid = PASSWORD_ORDER.find((name) => errors[name]);
        if (firstInvalid) {
            this.passwordErrors = errors;
            this._focusTarget = 'pw-' + firstInvalid;
            return;
        }
        this.passwordErrors = {};
        this.isChangingPassword = true;
        try {
            await changePassword({
                oldPassword: this.passwords.current,
                newPassword: this.passwords.next,
                confirmPassword: this.passwords.confirm
            });
            this.resetPasswords();
            this.passwordChanged = true;
            this._focusTarget = 'pw-done';
        } catch (error) {
            this.passwordError = errorText(error, TEXT.pwFailed);
        } finally {
            this.isChangingPassword = false;
        }
    }

    // Escape closes the popup; Tab stays inside it
    handlePasswordKeydown(event) {
        if (event.key === 'Escape' || event.key === 'Esc') {
            event.preventDefault();
            event.stopPropagation();
            this.handleClosePassword();
            return;
        }
        if (event.key !== 'Tab') {
            return;
        }
        const items = Array.from(this.template.querySelectorAll('[data-pw-focus]')).filter((item) => !item.disabled);
        if (!items.length) {
            return;
        }
        const first = items[0];
        const last = items[items.length - 1];
        const active = this.template.activeElement;
        if (event.shiftKey && (active === first || !items.includes(active))) {
            event.preventDefault();
            last.focus();
        } else if (!event.shiftKey && (active === last || !items.includes(active))) {
            event.preventDefault();
            first.focus();
        }
    }
}