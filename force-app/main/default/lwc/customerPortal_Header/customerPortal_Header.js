import { LightningElement, api } from 'lwc';

export default class CustomerProtal_Header extends LightningElement {

    // Header data supplied by the parent shell (loaded from Apex there).
    @api headerData = {};

    get userName() {
        return this.headerData && this.headerData.userName
            ? this.headerData.userName
            : '';
    }

    get userRole() {
        return this.headerData && this.headerData.userRole
            ? this.headerData.userRole
            : '';
    }

    get avatarUrl() {
        return this.headerData ? this.headerData.avatarUrl : null;
    }

    get notificationCount() {
        return this.headerData && this.headerData.notificationCount
            ? this.headerData.notificationCount
            : 0;
    }

    get hasNotifications() {
        return this.notificationCount > 0;
    }

    // Simple fallback initials avatar when no static resource / avatar URL exists.
    get userInitials() {
        if (!this.userName) {
            return '';
        }
        return this.userName
            .split(' ')
            .filter(Boolean)
            .map((part) => part.charAt(0).toUpperCase())
            .slice(0, 2)
            .join('');
    }

    handleHamburgerClick() {
        this.dispatchEvent(new CustomEvent('togglesidebar'));
    }

    handleProfileClick() {
        this.dispatchEvent(new CustomEvent('profileclick'));
    }
}