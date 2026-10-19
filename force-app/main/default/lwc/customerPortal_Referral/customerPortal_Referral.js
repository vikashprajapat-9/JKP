import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import CP_ASSETS from '@salesforce/resourceUrl/customerPortalAssets';
import getReferralPageData from '@salesforce/apex/CustomerPortalController.getReferralPageData';
import sendReferral from '@salesforce/apex/CustomerPortalController.sendReferral';

const MOBILE_REGEX = /^[0-9]{7,10}$/;
const COUNTRY_CODE = '94';
// Figma p74 cuts the program text after "... All you have to do is" (word boundary, then "...")
const SHORT_LENGTH = 270;

// Visible text (Figma pages 74-77). The page text, the referrals and the success text come from Apex.
const LABELS = {
    title: 'Referrals',
    referNow: 'Refer Now',
    readMore: 'Read more',
    loading: 'Loading referrals',
    loadError: "We couldn't load Referrals right now. Please try again in a moment.",
    opportunityPrefix: 'Opportunity: ',
    amountPrefix: 'Value: ',
    referredOnPrefix: 'Referred on ',
    propertyPrefix: 'Property Name: ',
    email: 'Email ID:',
    phone: 'Phone Number:',
    empty: "You haven't referred anyone yet.",
    inviteTitle: 'Invite friends',
    property: 'Property Name',
    propertyPlaceholder: 'Select-',
    name: 'Name',
    namePlaceholder: 'Enter your friend’s name',
    mobile: 'Mobile Number',
    mobilePlaceholder: 'Enter your friend’s mobile number',
    countryCode: COUNTRY_CODE,
    cancel: 'Cancel',
    submit: 'Submit Referral',
    close: 'Close',
    // used only when Apex returns no heading / message (Figma p77 wording)
    successTitle: 'Referral Sent',
    successMessage:
        'Congratulations! Your referral has been successfully submitted. We appreciate your support in recommending ' +
        'JK Properties to others.',
    toastTitle: 'Something went wrong',
    loadFailed: 'Failed to load referral page data.',
    sendFailed: 'Failed to send referral.'
};

// Traced from the Figma PDF: person in the navy avatar (p74), Sri Lanka flag of the mobile field (p75)
const PERSON_PATH =
    'M14.22 12.5C15.46 12.5 16.47 13.51 16.47 14.75L16.47 15.32C16.47 16.22 16.15 17.08 15.57 17.76C14 19.6 11.61 20.5 ' +
    '8.47 20.5C5.32 20.5 2.94 19.6 1.37 17.76C0.79 17.08 0.47 16.22 0.47 15.33L0.47 14.75C0.47 13.51 1.48 12.5 2.72 12.5' +
    'L14.22 12.5ZM14.22 14L2.72 14C2.31 14 1.97 14.34 1.97 14.75L1.97 15.33C1.97 15.86 2.16 16.38 2.51 16.79C3.76 18.26 ' +
    '5.73 19 8.47 19C11.21 19 13.17 18.26 14.43 16.79C14.78 16.38 14.97 15.86 14.97 15.32L14.97 14.75C14.97 14.34 14.64 ' +
    '14 14.22 14ZM8.47 0.5C11.23 0.5 13.47 2.74 13.47 5.5C13.47 8.27 11.23 10.5 8.47 10.5C5.71 10.5 3.47 8.27 3.47 5.5' +
    'C3.47 2.74 5.71 0.5 8.47 0.5ZM8.47 2C6.54 2 4.97 3.57 4.97 5.5C4.97 7.44 6.54 9 8.47 9C10.4 9 11.97 7.44 11.97 5.5' +
    'C11.97 3.57 10.4 2 8.47 2Z';
const CLOSE_PATH = 'M14 1.41L12.59 0L7 5.59L1.41 0L0 1.41L5.59 7L0 12.59L1.41 14L7 8.41L12.59 14L14 12.59L8.41 7L14 1.41Z';
const FLAG_PATHS = [
    { key: 'f0', fill: '#feca00', rule: 'evenodd', d: 'M0.5 0.5L23.5 0.5L23.5 17.75L0.5 17.75L0.5 0.5Z' },
    { key: 'f1', fill: '#1f8a6e', rule: 'nonzero', d: 'M1.94 1.94L6.25 1.94L6.25 16.31L1.94 16.31L1.94 1.94Z' },
    { key: 'f2', fill: '#f56800', rule: 'nonzero', d: 'M6.25 1.94L10.56 1.94L10.56 16.31L6.25 16.31L6.25 1.94Z' },
    { key: 'f3', fill: '#b01d00', rule: 'nonzero', d: 'M10.56 1.94L22.06 1.94L22.06 16.31L10.56 16.31L10.56 1.94Z' },
    {
        key: 'f4',
        fill: '#feca00',
        rule: 'nonzero',
        d:
            'M12.68 4.81C12.68 4.81 12.62 5.18 12.5 5.72C12.39 6.27 12.37 8.74 12.37 8.78C12.38 8.79 12.77 8.94 12.77 9.13' +
            'C12.77 9.34 12.62 9.46 12.62 9.46L13.26 10.16C13.26 10.16 13.14 10.05 13.36 9.29C13.59 8.53 14.2 8.55 14.46 8.3' +
            'C14.71 8.05 14.33 8.37 14.12 8.38C13.91 8.38 14.12 8.29 13.98 8.19C13.85 8.09 14.12 8.08 13.81 8.19C13.51 8.29 ' +
            '13.74 8.08 13.68 7.98C13.62 7.87 13.48 8.08 13.26 8.19C13.04 8.29 13.27 8.08 13.36 7.98C13.45 7.87 13.27 7.98 ' +
            '13.07 7.98C12.86 7.98 13.07 7.61 13.14 7.41C13.21 7.2 13.07 7.34 13.07 7.04C13.07 6.74 13.48 7.04 13.36 6.95' +
            'C13.24 6.86 13.07 6.42 13.07 6.27C13.07 6.12 13.23 5.95 13.36 5.95C13.5 5.95 13.68 6.16 13.68 6.16C13.68 6.16 ' +
            '13.91 6.16 14.2 6.12C14.5 6.09 14.46 5.95 14.46 5.72C14.46 5.5 14.62 5.72 14.87 5.72C15.12 5.72 15.35 5.84 15.35 ' +
            '5.84C15.35 5.84 15.35 5.58 15.53 5.58C15.71 5.58 15.82 5.84 15.82 5.84L16.09 5.58C16.1 5.59 16.52 5.84 16.67 5.84' +
            'C16.82 5.84 16.99 5.59 16.99 5.58L16.99 5.95C17 5.93 17.35 5.51 18.32 5.39C19.31 5.28 20.25 6.37 20.6 6.5C20.95 ' +
            '6.62 20.73 6.5 20.73 6.5C20.73 6.49 20.61 6.31 20.83 6.31C21.05 6.31 21.16 6.49 21.17 6.5C21.17 6.5 21.19 6.88 ' +
            '20.73 6.95C20.28 7.02 19.81 6.44 19.79 6.42C19.8 6.43 20.02 6.76 19.79 6.63C19.56 6.49 19.4 6.5 19.4 6.5C19.4 ' +
            '6.49 19.44 6.11 19.33 6.42C19.21 6.73 18.81 6.76 18.8 6.76C18.8 6.76 18.95 6.51 19.02 6.31C19.05 6.2 18.92 6.14 ' +
            '18.8 6.08C18.77 5.95 18.69 5.88 18.65 5.95C18.62 6 18.7 6.04 18.8 6.08C18.82 6.16 18.83 6.27 18.8 6.37C18.73 ' +
            '6.65 18.33 6.63 18.32 6.63C18.32 6.62 18.22 6.53 18.38 6.27C18.55 6 17.96 5.84 17.96 5.84C17.96 5.84 17.98 5.97 ' +
            '17.96 6.12C17.94 6.28 17.71 6.17 17.71 6.16C17.71 6.16 17.5 5.97 17.34 6.16C17.18 6.35 17.42 6.62 17.43 6.63' +
            'C17.44 6.62 17.48 6.5 17.71 6.42C17.94 6.34 18.07 6.5 18.07 6.5C18.07 6.5 18 6.57 17.85 6.76C17.7 6.95 17.91 ' +
            '7.04 17.92 7.04C17.93 7.03 18.21 6.69 18.21 6.88C18.21 7.07 18.32 7.04 18.72 7.16C19.12 7.27 20.01 7.04 20.02 ' +
            '7.04C20.02 7.04 20.93 7.11 20.93 7.68C20.93 8.25 20.54 8.54 20.53 8.55C20.53 8.55 20.83 9.13 20.83 9.65C20.83 ' +
            '10.16 20.6 10.54 20.53 11.19C20.45 11.83 20.69 11.78 20.83 11.94C20.97 12.11 20.69 12.3 20.53 12.48C20.36 12.66 ' +
            '20.51 12.74 20.6 12.92C20.7 13.11 20.75 13.33 20.6 13.33C20.46 13.33 20.25 13.21 20.25 13.21C20.25 13.21 20.17 ' +
            '13.33 20.02 13.33C19.88 13.33 19.8 13.21 19.79 13.21C19.79 13.21 19.79 13.33 19.62 13.33C19.45 13.33 19.4 13.21 ' +
            '19.4 13.21C19.4 13.21 19.07 13.33 18.91 13.33C18.76 13.33 18.72 13.21 18.72 13.21C18.72 13.21 18.72 13.33 18.54 ' +
            '13.33C18.36 13.33 18.32 13.21 18.32 13.21C18.32 13.21 18.21 13.32 18.07 13.33C17.93 13.33 17.85 13.21 17.85 ' +
            '13.21C17.85 13.21 17.85 13.33 17.71 13.33C17.56 13.33 17.55 13.23 17.55 13.03C17.55 12.82 18.32 12.74 18.32 ' +
            '12.74C18.32 12.74 18.56 12.07 18.21 11.78C17.86 11.49 17.83 10.79 17.71 10.79C17.58 10.8 17.09 10.9 16.8 11.01' +
            'C16.5 11.11 15.82 11.45 15.82 11.45C15.82 11.45 15.58 11.63 15.53 11.9C15.48 12.18 15.94 12.19 15.94 12.19' +
            'C15.82 12.59 15.36 12.66 15.35 12.66C15.49 12.78 15.34 13.28 15.15 13.33C14.96 13.37 14.87 13.23 14.87 13.23' +
            'C14.86 13.24 14.73 13.33 14.62 13.33C14.5 13.32 14.33 13.21 14.33 13.21C14.33 13.21 14.28 13.32 14.12 13.33' +
            'C13.96 13.33 13.98 13.21 13.98 13.21C13.98 13.21 13.94 13.26 13.74 13.33C13.54 13.39 13.65 13.06 13.68 12.92' +
            'C13.71 12.79 14.06 12.69 14.28 12.74C14.5 12.79 14.69 12.61 14.74 12.3C14.78 11.99 14.47 11.54 14.46 11.52' +
            'L14.01 11.27C14.01 11.27 13.7 11.63 13.48 11.63C13.27 11.63 12.79 11.2 12.77 11.19C12.77 11.19 12.68 11.27 ' +
            '12.62 11.27C12.56 11.27 12.45 11.16 12.5 10.9C12.54 10.75 12.48 10.62 12.43 10.53C12.42 10.52 12.42 10.51 12.41 ' +
            '10.5C12.39 10.47 12.38 10.45 12.37 10.45C12.39 10.47 12.4 10.48 12.41 10.5C12.42 10.51 12.42 10.52 12.43 10.53' +
            'C12.51 10.68 12.44 10.79 12.33 10.79C12.21 10.8 12.24 10.88 12.18 11.01C12.13 11.14 12.3 11.45 12.3 11.45' +
            'C12.3 11.45 12.58 11.45 12.58 11.59C12.58 11.72 12.43 11.73 12.37 11.78C12.32 11.83 12.35 11.87 12.37 11.9' +
            'C12.4 11.93 12.62 12.07 12.62 12.07L12.18 12.07L11.97 12.48L11.75 12.07L11.31 12.07C11.31 12.07 11.31 12.03 ' +
            '11.49 11.94C11.67 11.86 11.58 11.82 11.58 11.82C11.58 11.82 11.42 11.77 11.42 11.59C11.42 11.4 11.58 11.45 ' +
            '11.58 11.45C11.58 11.45 11.75 11.32 11.75 11.01C11.75 10.7 11.75 10.79 11.58 10.79C11.41 10.79 11.58 10.45 ' +
            '11.75 10.45C11.93 10.45 11.75 9.65 11.58 9.65C11.41 9.65 11.31 9.41 11.31 9.13C11.31 8.86 11.75 8.78 11.75 ' +
            '8.78L11.75 6.42C11.75 4.81 12.68 4.81 12.68 4.81ZM19.23 11.52C19.23 11.52 18.92 11.82 19.12 11.88C19.31 11.95 ' +
            '19.64 11.92 19.48 12.08C19.31 12.24 19.17 12.46 19.17 12.66C19.17 12.86 19.18 13.03 19.23 12.95C19.28 12.86 ' +
            '19.64 12.77 19.8 12.66C19.96 12.55 19.93 12.44 19.93 12.19C19.93 11.95 19.25 11.53 19.23 11.52ZM16.94 6.76' +
            'C16.94 6.76 16.93 7.46 16.86 7.51C16.79 7.57 16.75 7.66 16.81 7.73C16.86 7.8 16.89 7.98 16.81 7.98C16.73 7.98 ' +
            '16.6 8.07 16.71 8.22C16.81 8.37 16.8 8.45 16.99 8.45C17.18 8.45 18.23 8.48 18.53 8.37C18.84 8.26 19.13 8.37 ' +
            '19.55 8.31C19.97 8.26 20.56 7.95 20.48 7.73C20.4 7.51 20.3 7.23 19.55 7.42C18.8 7.6 18.52 7.71 18.24 7.56' +
            'C17.95 7.42 17.57 7.33 17.52 7.33C17.47 7.33 17.49 7.7 17.34 7.61C17.2 7.51 17.02 7.42 17.08 7.25C17.14 7.09 ' +
            '17.19 7.06 17.19 6.95C17.19 6.84 16.94 6.76 16.94 6.76Z'
    },
    { key: 'f5', fill: '#e8aa00', rule: 'nonzero', d: 'M9.12 1.94L10.56 1.94L10.56 16.31L9.12 16.31L9.12 1.94Z' },
    {
        key: 'f6',
        fill: '#feca00',
        rule: 'evenodd',
        d:
            'M11.63 15C11.72 14.83 11.63 15.35 11.63 15.61C11.63 15.86 11.34 16.36 11.14 16.22C10.94 16.08 10.69 16.21 ' +
            '10.68 16.22C10.68 16.22 10.68 16.09 10.68 15.96C10.68 15.82 10.45 15.49 10.84 15.41C11.24 15.34 11.54 15.16 ' +
            '11.63 15ZM21 15C21.09 15.16 21.39 15.34 21.78 15.41C22.18 15.49 21.94 15.82 21.94 15.96L21.94 16.22C21.94 ' +
            '16.22 21.69 16.08 21.49 16.22C21.29 16.36 21 15.86 21 15.61C21 15.35 20.91 14.83 21 15ZM11.14 2.02C11.34 1.89 ' +
            '11.63 2.38 11.63 2.64C11.63 2.89 11.72 3.41 11.63 3.25C11.54 3.08 11.24 2.91 10.84 2.83C10.45 2.75 10.68 2.42 ' +
            '10.68 2.28L10.68 2.02C10.69 2.03 10.94 2.16 11.14 2.02ZM21 2.64C21 2.38 21.29 1.89 21.49 2.02C21.69 2.16 21.94 ' +
            '2.03 21.94 2.02L21.94 2.28C21.94 2.42 22.18 2.75 21.78 2.83C21.39 2.91 21.09 3.08 21 3.25C20.91 3.41 21 2.89 ' +
            '21 2.64Z'
    }
];

export default class CustomerPortal_Referral extends LightningElement {
    labels = LABELS;
    personPath = PERSON_PATH;
    closePath = CLOSE_PATH;
    flagPaths = FLAG_PATHS;
    emptyImageUrl = CP_ASSETS + '/empty-state.svg';
    successImageUrl = CP_ASSETS + '/success-referral.png';

    pageData;
    isLoading = true;
    hasError = false;

    isDescriptionExpanded = false;

    isInviteModalOpen = false;
    isSuccessModalOpen = false;

    selectedProperty = '';
    submitError;
    friendName = '';
    mobileNumber = '';
    isSending = false;

    successData;

    // move focus into a modal once it has rendered
    focusModalPending = false;
    overlayPointerDown = false;

    connectedCallback() {
        this.loadReferralPageData();
    }

    renderedCallback() {
        if (this.focusModalPending) {
            const panel = this.template.querySelector('.cp-modal');
            if (panel) {
                this.focusModalPending = false;
                panel.focus();
            }
        }
    }

    // silent = refresh the cards without the spinner (after a referral, behind the "Referral Sent" popup, as in p77)
    async loadReferralPageData(silent = false) {
        if (!silent) {
            this.isLoading = true;
            this.hasError = false;
        }

        try {
            this.pageData = await getReferralPageData();
            this.hasError = false;
        } catch (error) {
            if (!silent) {
                this.hasError = true;
            }
            console.error('customerPortal_Referral: failed to load referral page data', error);
            this.showErrorToast(LABELS.loadFailed);
        } finally {
            this.isLoading = false;
        }
    }

    get showContent() {
        return !this.isLoading && !this.hasError && !!this.pageData;
    }

    // ---------------------------------------------------------------
    // Program text with "Read more" (Figma p74)
    // ---------------------------------------------------------------

    get descriptionText() {
        return (this.pageData && this.pageData.description) || '';
    }

    get isDescriptionLong() {
        return this.descriptionText.length > SHORT_LENGTH;
    }

    get displayedDescription() {
        const text = this.descriptionText;
        if (this.isDescriptionExpanded || !this.isDescriptionLong) {
            return text;
        }
        const cut = text.substring(0, SHORT_LENGTH);
        const lastSpace = cut.lastIndexOf(' ');
        return (lastSpace > 0 ? cut.substring(0, lastSpace) : cut).replace(/[\s.,;:—-]+$/, '') + '...';
    }

    get showReadMore() {
        return this.isDescriptionLong && !this.isDescriptionExpanded;
    }

    handleReadMore() {
        this.isDescriptionExpanded = true;
    }

    // ---------------------------------------------------------------
    // Referral cards (Figma p74: Booked green, Not booked orange)
    // ---------------------------------------------------------------

    get displayedReferrals() {
        if (!this.pageData || !this.pageData.referrals) {
            return [];
        }
        return this.pageData.referrals.map((ref, index) => {
            // A referral that became an opportunity shows the booking and its stage; the others show the lead's status
            const converted = !!ref.isConverted && !!ref.opportunityName;
            const status = converted ? ref.opportunityStage : ref.status;
            const good = converted || ['converted', 'qualified', 'booked'].includes((ref.status || '').trim().toLowerCase());
            return {
                ...ref,
                key: ref.id || 'ref-' + index,
                propertyLine: LABELS.propertyPrefix + (ref.propertyName || ''),
                status,
                hasEmail: !!ref.emailId,
                converted,
                opportunityLine: converted ? LABELS.opportunityPrefix + ref.opportunityName : '',
                amountLine: converted && ref.opportunityAmount ? LABELS.amountPrefix + ref.opportunityAmount : '',
                statusPillClass: 'cp-badge ref-badge ' + (good ? 'cp-badge_completed' : 'cp-badge_warning')
            };
        });
    }

    get hasNoReferrals() {
        return this.displayedReferrals.length === 0;
    }

    get propertyOptionsView() {
        const options = (this.pageData && this.pageData.propertyOptions) || [];
        return options.map((opt) => ({ ...opt, selected: opt.value === this.selectedProperty }));
    }

    get isPropertyEmpty() {
        return !this.selectedProperty;
    }

    get propertySelectClass() {
        return this.selectedProperty ? 'cp-select' : 'cp-select ref-select_empty';
    }

    // ---------------------------------------------------------------
    // Invite friends (Figma p75 empty, p76 filled) and Referral Sent (p77)
    // ---------------------------------------------------------------

    handleOpenInviteModal() {
        this.selectedProperty = '';
        this.friendName = '';
        this.mobileNumber = '';
        this.submitError = undefined;
        this.isInviteModalOpen = true;
        this.focusModalPending = true;
    }

    handleCloseInviteModal() {
        this.isInviteModalOpen = false;
    }

    handlePropertyChange(event) {
        this.selectedProperty = event.target.value;
    }

    handleNameChange(event) {
        this.friendName = event.target.value;
    }

    handleMobileChange(event) {
        this.mobileNumber = event.target.value;
    }

    get isFormValid() {
        const hasProperty = !!this.selectedProperty;
        const hasName = !!(this.friendName && this.friendName.trim().length > 0);
        const hasMobile = MOBILE_REGEX.test((this.mobileNumber || '').trim());
        return hasProperty && hasName && hasMobile;
    }

    get isSendDisabled() {
        return !this.isFormValid || this.isSending;
    }

    async handleSendInvite() {
        if (!this.isFormValid || this.isSending) {
            return;
        }

        this.isSending = true;
        this.submitError = undefined;
        try {
            const result = await sendReferral({
                propertyName: this.selectedProperty,
                friendName: this.friendName,
                mobileNumber: COUNTRY_CODE + this.mobileNumber
            });

            this.successData = result;
            this.isInviteModalOpen = false;
            this.isSuccessModalOpen = true;
            this.focusModalPending = true;

            await this.loadReferralPageData(true);
        } catch (error) {
            // Toasts do not show on this site, so the reason stays in the popup. The server's own wording is used
            // when it reads like a sentence for the customer (the duplicate rule says the lead already exists).
            console.error('customerPortal_Referral: failed to send referral', error);
            const message = (error && error.body && error.body.message) || '';
            const readable = message && message.length < 200 && !/exception|system\.|field_|invalid_|apex|script-thrown/i.test(message);
            this.submitError = readable ? message : LABELS.sendFailed;
        } finally {
            this.isSending = false;
        }
    }

    get successTitle() {
        return (this.successData && this.successData.heading) || LABELS.successTitle;
    }

    get successMessage() {
        return (this.successData && this.successData.message) || LABELS.successMessage;
    }

    handleCloseSuccessModal() {
        this.isSuccessModalOpen = false;
        // The list is read again as the popup closes, so the new referral is on the page straight away even if the
        // reload right after sending had not come back yet
        this.loadReferralPageData(true);
    }

    closeOpenModal() {
        if (this.isSuccessModalOpen) {
            this.handleCloseSuccessModal();
        } else if (this.isInviteModalOpen) {
            this.handleCloseInviteModal();
        }
    }

    // close on a click on the dimmed overlay only (not when a text selection inside the panel ends outside it)
    handleOverlayMouseDown(event) {
        this.overlayPointerDown = event.target === event.currentTarget;
    }

    handleOverlayClick(event) {
        const onOverlay = event.target === event.currentTarget && this.overlayPointerDown;
        this.overlayPointerDown = false;
        if (onOverlay) {
            this.closeOpenModal();
        }
    }

    handleModalKeydown(event) {
        if (event.key === 'Escape' || event.key === 'Esc') {
            event.stopPropagation();
            this.closeOpenModal();
        }
    }

    showErrorToast(message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: LABELS.toastTitle,
                message,
                variant: 'error',
                mode: 'dismissible'
            })
        );
    }
}