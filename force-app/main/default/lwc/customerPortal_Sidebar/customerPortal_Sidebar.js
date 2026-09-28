import { LightningElement, api } from 'lwc';
import JohnKeellsLogo from '@salesforce/resourceUrl/JohnKeellsLogo';

export default class CustomerPortal_Sidebar extends LightningElement {

    @api menuItems = [];

    @api activePage = 'dashboard';

    _isOpen = false;

    @api
    get isOpen() {
        return this._isOpen;
    }
    set isOpen(value) {
        this._isOpen = !!value;
    }

    logoUrl = JohnKeellsLogo;

    _keydownHandler;
    _scrollLocked = false;

    connectedCallback() {
        this._keydownHandler = (event) => {
            if (event.key === 'Escape' && this._isOpen) {
                this.closeMobileMenu();
            }
        };
        window.addEventListener('keydown', this._keydownHandler);
    }

    disconnectedCallback() {
        window.removeEventListener('keydown', this._keydownHandler);
        this.setScrollLock(false);
    }

    renderedCallback() {
        this.setScrollLock(this._isOpen);
    }

    setScrollLock(shouldLock) {
        if (shouldLock === this._scrollLocked) {
            return;
        }
        this._scrollLocked = shouldLock;
        document.body.classList.toggle('jk-sidebar-open', shouldLock);
    }

    get isMobileMenuOpen() {
        return this._isOpen;
    }

    get sidebarClass() {
        return this._isOpen ? 'portal-sidebar portal-sidebar_open' : 'portal-sidebar';
    }

    get toggleAriaLabel() {
        return this._isOpen ? 'Close menu' : 'Open menu';
    }

    get ariaExpanded() {
        return this._isOpen ? 'true' : 'false';
    }

    get bar1Class() {
        return this._isOpen ? 'bar bar1 open' : 'bar bar1';
    }
    get bar2Class() {
        return this._isOpen ? 'bar bar2 open' : 'bar bar2';
    }
    get bar3Class() {
        return this._isOpen ? 'bar bar3 open' : 'bar bar3';
    }

    get decoratedMenuItems() {
        return (this.menuItems || [])
            .slice()
            .sort((a, b) => a.displayOrder - b.displayOrder)
            .map((item) => {
                return {
                    ...item,
                    itemClass:
                        item.value === this.activePage
                            ? 'menu-item menu-item_active'
                            : 'menu-item'
                };
            });
    }

    get menuItemsToRender() {
        return this.decoratedMenuItems;
    }

    handleItemClick(event) {
        const value = event.currentTarget.dataset.value;

        this.dispatchEvent(
            new CustomEvent('menuselect', {
                detail: { value }
            })
        );

        if (this._isOpen) {
            this.closeMobileMenu();
        }
    }

    handleToggleClick() {
        this._isOpen = !this._isOpen;
        this.dispatchEvent(
            new CustomEvent(this._isOpen ? 'openmobilemenu' : 'closemobilemenu')
        );
    }

    closeMobileMenu() {
        this._isOpen = false;
        this.dispatchEvent(new CustomEvent('closemobilemenu'));
    }
}