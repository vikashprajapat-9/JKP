import { LightningElement, api } from 'lwc';
import CP_ASSETS from '@salesforce/resourceUrl/customerPortalAssets';

const LABELS = {
    toggleMenu: 'Toggle menu',
    notifications: 'Notifications',
    viewProfile: 'View profile',
    close: 'Close',
    closeNotifications: 'Close notifications',
    noNotifications: 'You have no notifications yet.',
    today: 'Today',
    yesterday: 'Yesterday',
    earlier: 'Earlier',
    profilePicture: 'Profile picture'
};

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

// Icons traced from the Figma design: header bell (p7), notification card bell (p6) and the close X (p6)
const BELL_PATH =
    'M24.26 19.67L24.26 20.67C24.68 20.67 25.05 20.41 25.19 20.03C25.34 19.65 25.24 19.21 24.94 18.93L24.26 19.67ZM1.04 19.67L0.37 18.93C0.06 19.21 -0.04 19.65 0.11 20.03C0.26 20.41 0.63 20.67 1.04 20.67L1.04 19.67ZM3.08 17.79L3.76 18.53L3.08 17.79ZM9.75 4.12L10.06 5.07C10.47 4.94 10.75 4.56 10.75 4.12L9.75 4.12ZM15.56 4.12L14.56 4.12C14.56 4.56 14.84 4.94 15.25 5.07L15.56 4.12ZM1.04 19.67L1.72 20.4L3.76 18.53L3.08 17.79L2.41 17.06L0.37 18.93L1.04 19.67ZM3.95 15.88L4.95 15.88L4.95 11.67L3.95 11.67L2.95 11.67L2.95 15.88L3.95 15.88ZM21.36 11.67L20.36 11.67L20.36 15.88L21.36 15.88L22.36 15.88L22.36 11.67L21.36 11.67ZM22.22 17.79L21.55 18.53L23.59 20.4L24.26 19.67L24.94 18.93L22.9 17.06L22.22 17.79ZM3.08 17.79L3.76 18.53C4.51 17.84 4.95 16.89 4.95 15.88L3.95 15.88L2.95 15.88C2.95 16.3 2.76 16.73 2.41 17.06L3.08 17.79ZM21.36 15.88L20.36 15.88C20.36 16.89 20.8 17.84 21.55 18.53L22.22 17.79L22.9 17.06C22.54 16.73 22.36 16.3 22.36 15.88L21.36 15.88ZM9.75 4.12L9.44 3.17C5.71 4.38 2.95 7.69 2.95 11.67L3.95 11.67L4.95 11.67C4.95 8.67 7.03 6.06 10.06 5.07L9.75 4.12ZM15.56 4.12L15.25 5.07C18.27 6.06 20.36 8.67 20.36 11.67L21.36 11.67L22.36 11.67C22.36 7.69 19.6 4.38 15.87 3.17L15.56 4.12L16.56 4.12L16.56 3.67L15.56 3.67L14.56 3.67L14.56 4.12L15.56 4.12ZM9.75 3.67L8.75 3.67L8.75 4.12L9.75 4.12L10.75 4.12L10.75 3.67L9.75 3.67ZM12.65 1L12.65 0C10.58 0 8.75 1.56 8.75 3.67L9.75 3.67L10.75 3.67C10.75 2.82 11.52 2 12.65 2L12.65 1ZM15.56 3.67L16.56 3.67C16.56 1.56 14.73 0 12.65 0L12.65 1L12.65 2C13.79 2 14.56 2.82 14.56 3.67L15.56 3.67ZM17.01 21L16.01 21C16.01 22.58 14.59 24 12.65 24L12.65 25L12.65 26C15.53 26 18.01 23.84 18.01 21L17.01 21ZM12.65 25L12.65 24C10.72 24 9.3 22.58 9.3 21L8.3 21L7.3 21C7.3 23.84 9.78 26 12.65 26L12.65 25ZM24.26 19.67L24.26 18.67L17.01 18.67L17.01 19.67L17.01 20.67L24.26 20.67L24.26 19.67ZM17.01 21L18.01 21L18.01 19.67L17.01 19.67L16.01 19.67L16.01 21L17.01 21ZM17.01 19.67L17.01 18.67L8.3 18.67L8.3 19.67L8.3 20.67L17.01 20.67L17.01 19.67ZM8.3 19.67L8.3 18.67L1.04 18.67L1.04 19.67L1.04 20.67L8.3 20.67L8.3 19.67ZM8.3 21L9.3 21L9.3 19.67L8.3 19.67L7.3 19.67L7.3 21L8.3 21Z';
const CARD_BELL_PATH =
    'M16 8.22C19.15 8.22 21.72 10.7 21.83 13.86L21.84 14.05L21.84 17.24L22.91 19.7C22.96 19.82 22.99 19.95 22.99 20.09C22.99 20.62 22.56 21.06 22.02 21.06L18.33 21.06C18.33 22.35 17.29 23.39 16 23.39C14.76 23.39 13.74 22.42 13.67 21.2L13.67 21.06L9.99 21.06C9.86 21.06 9.72 21.03 9.6 20.98C9.11 20.76 8.88 20.19 9.1 19.7L10.16 17.24L10.16 14.05C10.16 10.82 12.77 8.22 16 8.22ZM17.17 21.06L14.83 21.06C14.83 21.7 15.36 22.23 16 22.23C16.61 22.23 17.11 21.76 17.16 21.17L17.17 21.06ZM16 9.38C13.42 9.38 11.33 11.46 11.33 14.05L11.33 17.48L10.29 19.89L21.72 19.89L20.67 17.48L20.67 14.06L20.67 13.89C20.58 11.37 18.52 9.38 16 9.38Z';
const CLOSE_PATH = 'M14 1.41L12.59 0L7 5.59L1.41 0L0 1.41L5.59 7L0 12.59L1.41 14L7 8.41L12.59 14L14 12.59L8.41 7L14 1.41Z';

function startOfDay(date) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
}

function dateText(date) {
    return date.getDate() + ' ' + MONTHS[date.getMonth()] + ', ' + date.getFullYear();
}

function timeText(date) {
    const hours = date.getHours();
    const minutes = String(date.getMinutes()).padStart(2, '0');
    return (hours % 12 || 12) + ':' + minutes + ' ' + (hours < 12 ? 'AM' : 'PM');
}

export default class CustomerProtal_Header extends LightningElement {

    _headerData = {};

    // Header data supplied by the parent shell (loaded from Apex there; the Profile screen updates the photo and name).
    // A new photo gets a fresh chance to load even if the previous one failed.
    @api
    get headerData() {
        return this._headerData;
    }

    set headerData(value) {
        const next = value || {};
        const previousUrl = (this._headerData && this._headerData.avatarUrl) || null;
        if ((next.avatarUrl || null) !== previousUrl) {
            this.avatarFailed = false;
        }
        this._headerData = next;
    }

    labels = LABELS;
    bellPath = BELL_PATH;
    cardBellPath = CARD_BELL_PATH;
    closePath = CLOSE_PATH;
    emptyIconUrl = CP_ASSETS + '/notification-bell.svg';

    isPanelOpen = false;
    avatarFailed = false;

    _focusClose = false;
    _focusBell = false;
    _keydownHandler;

    connectedCallback() {
        this._keydownHandler = (event) => {
            if (event.key === 'Escape' && this.isPanelOpen) {
                this.closePanel();
            }
        };
        window.addEventListener('keydown', this._keydownHandler);
    }

    disconnectedCallback() {
        window.removeEventListener('keydown', this._keydownHandler);
    }

    renderedCallback() {
        if (this._focusClose) {
            this._focusClose = false;
            const closeButton = this.template.querySelector('.np-close');
            if (closeButton) {
                closeButton.focus();
            }
        } else if (this._focusBell) {
            this._focusBell = false;
            const bell = this.template.querySelector('.bell-btn');
            if (bell) {
                bell.focus();
            }
        }
    }

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

    // The user's photo when there is one, otherwise the Figma default avatar
    get avatarSrc() {
        return this.avatarUrl && !this.avatarFailed ? this.avatarUrl : CP_ASSETS + '/avatar-default.png';
    }

    get avatarAlt() {
        return this.userName || LABELS.profilePicture;
    }

    get notificationCount() {
        return this.headerData && this.headerData.notificationCount
            ? this.headerData.notificationCount
            : 0;
    }

    get hasNotifications() {
        return this.notificationCount > 0;
    }

    get bellAriaLabel() {
        return this.hasNotifications
            ? LABELS.notifications + ' (' + this.notificationCount + ')'
            : LABELS.notifications;
    }

    get panelExpanded() {
        return this.isPanelOpen ? 'true' : 'false';
    }

    // Initials of the user (kept for callers; the avatar now falls back to the default picture)
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

    // Notification list, when the header data carries one: [{ id, title, message, createdDate }]
    get notificationItems() {
        const list = this.headerData && this.headerData.notifications;
        return Array.isArray(list) ? list : [];
    }

    get hasNotificationItems() {
        return this.notificationItems.length > 0;
    }

    // Figma p6: grouped under "Today", "Yesterday" or the date, newest first as given
    get notificationGroups() {
        const groups = [];
        const byLabel = new Map();
        const today = startOfDay(new Date());
        const dayMs = 24 * 60 * 60 * 1000;
        this.notificationItems.forEach((item, index) => {
            const when = item && item.createdDate ? new Date(item.createdDate) : null;
            const valid = when && !isNaN(when.getTime());
            let label = LABELS.earlier;
            let time = '';
            if (valid) {
                const day = startOfDay(when);
                if (day === today) {
                    label = LABELS.today;
                    time = LABELS.today + ', ' + timeText(when);
                } else {
                    label = day === today - dayMs ? LABELS.yesterday : dateText(when);
                    time = dateText(when) + ', ' + timeText(when);
                }
            }
            let group = byLabel.get(label);
            if (!group) {
                group = { key: 'group-' + groups.length, label, items: [] };
                byLabel.set(label, group);
                groups.push(group);
            }
            group.items.push({
                key: (item && item.id) || 'note-' + index,
                title: (item && item.title) || '',
                message: (item && item.message) || '',
                time
            });
        });
        return groups;
    }

    handleHamburgerClick() {
        this.dispatchEvent(new CustomEvent('togglesidebar'));
    }

    handleProfileClick() {
        this.dispatchEvent(new CustomEvent('profileclick'));
    }

    handleAvatarError() {
        this.avatarFailed = true;
    }

    handleBellClick() {
        if (this.isPanelOpen) {
            this.closePanel();
            return;
        }
        this.isPanelOpen = true;
        this._focusClose = true;
    }

    closePanel() {
        this.isPanelOpen = false;
        this._focusBell = true;
    }
}