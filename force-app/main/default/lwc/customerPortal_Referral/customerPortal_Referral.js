import { LightningElement } from 'lwc';
import getReferralPageData from '@salesforce/apex/CustomerPortalController.getReferralPageData';
import sendReferral from '@salesforce/apex/CustomerPortalController.sendReferral';
import SuccessReferralImage from '@salesforce/resourceUrl/SuccessReferralImage';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
const MOBILE_REGEX = /^[0-9]{7,10}$/;

export default class CustomerPortal_Referral extends LightningElement {

    pageData;
    isLoading = true;
    hasError = false;

    isDescriptionExpanded = false;

    isInviteModalOpen = false;
    isSuccessModalOpen = false;

    selectedProperty = '';
    friendName = '';
    mobileNumber = '';

    successData;
    successIllustrationUrl = SuccessReferralImage;

    connectedCallback() {
        this.loadReferralPageData();
    }

    async loadReferralPageData() {
        this.isLoading = true;
        this.hasError = false;

        try {
            this.pageData = await getReferralPageData();
        } catch (error) {
            this.hasError = true;
            console.error('customerPortal_Referral: failed to load referral page data', error);
             this.showErrorToast('Failed to load referral page data.');
        } finally {
            this.isLoading = false;
        }
    }

    get showContent() {
        return !this.isLoading && !this.hasError && this.pageData;
    }

    get displayedDescription() {
        if (!this.pageData || !this.pageData.description) {
            return '';
        }
        if (this.isDescriptionExpanded) {
            return this.pageData.description;
        }
        const shortLength = 160;
        return this.pageData.description.length > shortLength
            ? this.pageData.description.substring(0, shortLength) + '... '
            : this.pageData.description;
    }

    handleReadMore() {
        this.isDescriptionExpanded = true;
    }
    get bannerStyle() {
        if (this.pageData && this.pageData.bannerImageUrl) {
            return `background-image: url(${this.pageData.bannerImageUrl});`;
        }
        return '';
    }
    get displayedReferrals() {
        if (!this.pageData || !this.pageData.referrals) {
            return [];
        }
        return this.pageData.referrals.map((ref) => {
            const isBooked = (ref.status || '').toLowerCase() === 'booked';
            return {
                ...ref,
                statusPillClass: isBooked
                    ? 'status-pill status-pill_completed'
                    : 'status-pill status-pill_pending'
            };
        });
    }

    get hasNoReferrals() {
        return this.displayedReferrals.length === 0;
    }


    get displayedSteps() {
        if (!this.pageData || !this.pageData.referralSteps) {
            return [];
        }
        return this.pageData.referralSteps.map((step) => {
            return {
                ...step,
                iconWrapClass: 'step-icon-wrap step-icon-' + step.stepNumber
            };
        });
    }

    handleOpenInviteModal() {
        this.selectedProperty = '';
        this.friendName = '';
        this.mobileNumber = '';
        this.isInviteModalOpen = true;
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
        return !this.isFormValid;
    }

    get sendInviteBtnClass() {
        return this.isFormValid
            ? 'send-invite-btn send-invite-btn_enabled'
            : 'send-invite-btn send-invite-btn_disabled';
    }

    async handleSendInvite() {
        if (!this.isFormValid) {
            return;
        }

        try {
            const result = await sendReferral({
                propertyName: this.selectedProperty,
                friendName: this.friendName,
                mobileNumber: '94' + this.mobileNumber
            });

            this.successData = result;
            this.isInviteModalOpen = false;
            this.isSuccessModalOpen = true;

            await this.loadReferralPageData();
        } catch (error) {
            console.error('customerPortal_Referral: failed to send referral', error);
             this.showErrorToast('Failed to send referral.');
        }
    }

    handleCloseSuccessModal() {
        this.isSuccessModalOpen = false;
    }

    showErrorToast(message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Something went wrong',
                message,
                variant: 'error',
                mode: 'dismissable'
            })
        );
    }
}