import { LightningElement } from 'lwc';
import getProfileData from '@salesforce/apex/customerPortalController.getProfileData';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
const DEPARTMENT_CHOICES = [
    'Sales',
    'Marketing',
    'Finance',
    'Operations',
    'Customer Service',
    'IT',
    'HR'
];

export default class CustomerPortal_Profile extends LightningElement {

    profileData;
    isLoading = true;
    hasError = false;
    searchTerm = '';

    connectedCallback() {
        this.loadProfileData();
    }

    async loadProfileData() {
        this.isLoading = true;
        this.hasError = false;

        try {
            const result = await getProfileData();
            this.profileData = { ...result };
        } catch (error) {
            this.hasError = true;
            console.error('customerProtal_Profile: failed to load profile data', error);
            this.showErrorToast('Failed to load profile data.');
        } finally {
            this.isLoading = false;
        }
    }

    get showProfile() {
        return !this.isLoading && !this.hasError && this.profileData;
    }

    get avatarUrl() {
        return this.profileData ? this.profileData.avatarUrl : null;
    }

    get userInitials() {
        const fullName = this.profileData ? this.profileData.fullName : '';
        if (!fullName) {
            return '';
        }
        return fullName
            .split(' ')
            .filter(Boolean)
            .map((part) => part.charAt(0).toUpperCase())
            .slice(0, 2)
            .join('');
    }

    get departmentOptions() {
        const currentDepartment = this.profileData ? this.profileData.department : '';
        return DEPARTMENT_CHOICES.map((label) => {
            return {
                label,
                value: label,
                isSelected: label === currentDepartment
            };
        });
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
    }

    handleFieldChange(event) {
        const field = event.target.dataset.field;
        if (field) {
            this.profileData = {
                ...this.profileData,
                [field]: event.target.value
            };
        }
    }

    handleDepartmentChange(event) {
        this.profileData = {
            ...this.profileData,
            department: event.target.value
        };
    }

    handleAddPhotoClick() {
    }

    handleChangePassword() {
    }

    handleSaveProfile() {
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