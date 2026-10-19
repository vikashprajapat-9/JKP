import { LightningElement, wire } from 'lwc';
import { loadStyle } from 'lightning/platformResourceLoader';
import { refreshApex } from '@salesforce/apex';
import PORTAL_THEME from '@salesforce/resourceUrl/JKPortalTheme';
import LOGIN_ASSETS from '@salesforce/resourceUrl/PartnerPortalLogin';
import basePath from '@salesforce/community/basePath';
import USER_ID from '@salesforce/user/Id';
import getPortalUser from '@salesforce/apex/PartnerPortalDashboard.getPortalUser';
import getReminders from '@salesforce/apex/PartnerVisitReminders.getReminders';
import getSessionState from '@salesforce/apex/partnerPortalLoginController.sessionState';

const LABELS = {
    ACCESS_ENDED_TITLE: 'Access Ended',
    ACCESS_ENDED_TEXT: 'Your access to the John Keells Properties Partner Portal has ended, so its pages are no longer available to you. If you have any questions, please contact the JKP CP team.',
    ACCESS_ENDED_LOGOUT: 'Log out',
    ACCESS_ENDED_BACK: 'Back to Login',
    ACCESS_TERMINATED_TITLE: 'Access Terminated',
    ACCESS_TERMINATED_TEXT: 'Your access to the John Keells Properties Partner Portal has been terminated, so its pages are no longer available to you. If you have any questions, please contact the JKP CP team.',
    SESSION_ENDED_TITLE: 'Session Ended',
    SESSION_ENDED_TEXT: 'Your session on the John Keells Properties Partner Portal has ended. Please log in again to continue.',
    SESSION_ENDED_LOGIN: 'Log in again',
    SESSION_CHECKING: 'Checking your session'
};

const NAV_ITEMS = [
    { page: 'dashboard', label: 'Dashboard', icon: 'utility:home' },
    { page: 'leads', label: 'Leads', icon: 'utility:user' },
    { page: 'siteVisits', label: 'Site Visits', icon: 'utility:location' },
    { page: 'myTeam', label: 'My Team', icon: 'utility:people' },
    { page: 'contract', label: 'My Contract', icon: 'utility:file' },
    { page: 'projects', label: 'Projects', icon: 'utility:list' },
    { page: 'commission', label: 'Commission', icon: 'utility:money' },
    { page: 'marketing', label: 'Marketing', icon: 'utility:announcement' },
    { page: 'aboutUs', label: 'About Us', icon: 'utility:info' },
    { page: 'terms', label: 'Terms & Conditions', icon: 'utility:description' },
    { page: 'logout', label: 'Logout', icon: 'utility:logout' }
];

// The pages only a channel head has: an executive is onboarded by their channel head, who also holds the contract
const CHANNEL_HEAD_PAGES = ['myTeam', 'contract'];

// Why the portal shows its ended screen instead of its pages, and what the screen says. ENDED: the access is over
// (temporary access without its conditions met, Access Denied, or a login switched off). TERMINATED: John Keells
// Properties terminated the partner, or an executive's channel head. SIGNED_OUT: the login is fine, but this session is
// over (logged out elsewhere, or timed out).
const ENDED = 'ENDED';
const TERMINATED = 'TERMINATED';
const SIGNED_OUT = 'SIGNED_OUT';
// The login page's Access Denied picture, for the screens that refuse the partner; a partner who was only logged out
// is refused nothing, and gets no such picture
const REFUSED_PICTURE = '/status-restricted.png';
const ENDED_SCREENS = {
    [ENDED]: { title: LABELS.ACCESS_ENDED_TITLE, text: LABELS.ACCESS_ENDED_TEXT, picture: REFUSED_PICTURE },
    [TERMINATED]: { title: LABELS.ACCESS_TERMINATED_TITLE, text: LABELS.ACCESS_TERMINATED_TEXT, picture: REFUSED_PICTURE },
    [SIGNED_OUT]: { title: LABELS.SESSION_ENDED_TITLE, text: LABELS.SESSION_ENDED_TEXT }
};
// The reasons Salesforce gives for a session that is over (partnerPortalLoginController.sessionState), as screens
const SESSION_SCREENS = { TERMINATED, ACCESS_DENIED: ENDED, INACTIVE: ENDED, SIGNED_OUT };

// A click on a page asks Salesforce again whether the partner still has access: a moment after the click (its own
// request goes first), and not more often than this
const CLICK_CHECK_DELAY = 1200;
const CLICK_CHECK_GAP = 5000;
// Coming back to the browser tab asks at once, unless it was just asked
const RETURN_CHECK_GAP = 3000;
// How long the question "is this session over?" may take before the portal goes on as it was
const SESSION_CHECK_TIMEOUT = 5000;

export default class PartnerWebPortal extends LightningElement {

    selectedPage = 'dashboard';
    userName = '';
    // An executive is onboarded by their channel head and onboards nobody, and their channel head holds the contract: no
    // My Team and no My Contract for them
    isExecutive = false;
    // Why the portal shows only its ended screen (ENDED, TERMINATED or SIGNED_OUT), whose one action leaves the portal;
    // undefined while the partner has access. The partner's access has ended (temporary access over without its
    // conditions met, Access Denied or Terminated), however they logged in, or their session is over.
    endedReason;
    // The session of this browser is over (the login was switched off, or the partner was logged out): Salesforce
    // answers none of the portal's requests any more, so the ended screen stays
    sessionOver = false;
    // The wired portal user, asked for again as the partner moves around, so that an access ending while the portal is
    // open is noticed
    portalUserResult;
    // Given to the partner's own portal while logged in; shown to Salesforce again with the question why the session
    // is over (a user id alone gets no reason)
    sessionKey;
    showLogoutConfirm = false;
    logoUrl = PORTAL_THEME + '/logo.png';
    labels = { checking: LABELS.SESSION_CHECKING };
    // Element to focus after the next render
    pendingFocus;
    // The bell, the only place that shows the site visit reminders: today's visits, tomorrow's and the ones to update
    // (PartnerVisitReminders)
    reminderCount = 0;
    showBell = false;

    // When Salesforce was last asked whether the partner still has access, and the question a click has waiting
    lastAccessCheck = 0;
    clickCheckTimer;
    checkingSession = false;

    @wire(getPortalUser)
    wiredUser(result) {
        this.portalUserResult = result;
        const { data, error } = result;
        if (data) {
            this.lastAccessCheck = Date.now();
            this.userName = data.name || '';
            this.sessionKey = data.sessionKey || this.sessionKey;
            this.isExecutive = data.isExecutive === true;
            if (this.isExecutive && CHANNEL_HEAD_PAGES.includes(this.selectedPage)) {
                this.selectedPage = 'dashboard';
            }
            if (this.sessionOver) {
                return;
            }
            if (data.accessEnded === true) {
                this.showEnded(data.terminated === true ? TERMINATED : ENDED);
            } else {
                this.endedReason = undefined;
            }
        } else if (error) {
            // Salesforce no longer answers for this partner: their session may be over
            this.checkSession();
        }
    }

    connectedCallback() {
        loadStyle(this, PORTAL_THEME + '/theme.css').catch(() => {
            // Font falls back to the system stack if the theme fails to load.
        });
        this.refreshReminderCount();
        this.bellKeyHandler = (event) => {
            if (event.key === 'Escape' && this.showBell) {
                this.closeBell();
            }
        };
        window.addEventListener('keydown', this.bellKeyHandler);
        // A partner who comes back to this browser tab, or clicks anything on a page, learns at once (and not from the
        // page's failing requests) that their access or session has ended meanwhile
        this.returnHandler = () => {
            if (document.visibilityState !== 'hidden' && Date.now() - this.lastAccessCheck > RETURN_CHECK_GAP) {
                this.refreshAccess();
            }
        };
        document.addEventListener('visibilitychange', this.returnHandler);
        window.addEventListener('focus', this.returnHandler);
        this.clickHandler = () => this.checkAccessAfterClick();
        this.template.addEventListener('click', this.clickHandler);
    }

    disconnectedCallback() {
        window.removeEventListener('keydown', this.bellKeyHandler);
        document.removeEventListener('visibilitychange', this.returnHandler);
        window.removeEventListener('focus', this.returnHandler);
        this.template.removeEventListener('click', this.clickHandler);
        clearTimeout(this.clickCheckTimer);
        this.clickCheckTimer = undefined;
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

    async refreshReminderCount() {
        try {
            const reminders = await getReminders();
            this.reminderCount = reminders ? reminders.count || 0 : 0;
        } catch (e) {
            // The bell stays without a count; the reminders say why when opened.
        }
    }

    get navItems() {
        return NAV_ITEMS.filter(item => !(this.isExecutive && CHANNEL_HEAD_PAGES.includes(item.page))).map(item => ({
            ...item,
            cssClass: this.selectedPage === item.page ? 'nav-item active' : 'nav-item'
        }));
    }

    handleNavigation(event) {
        const page = event.currentTarget.dataset.page;
        this.showBell = false;
        if (page === 'logout') {
            this.showLogoutConfirm = true;
        } else {
            this.selectedPage = page;
            // A visit may have been updated on the page just left, and the access may have ended meanwhile
            this.refreshReminderCount();
            this.refreshAccess();
        }
    }

    // Asks Salesforce again who the partner is: an access that ended while the portal was open shows the ended screen
    // at the partner's next move. Before Salesforce's first answer there is nothing to ask again (that answer decides).
    // A refresh Salesforce refuses may mean that the partner's session is over: checkSession finds out.
    refreshAccess() {
        const result = this.portalUserResult;
        if (this.sessionOver || !result || (!result.data && !result.error)) {
            return;
        }
        this.lastAccessCheck = Date.now();
        Promise.resolve()
            .then(() => refreshApex(result))
            .catch(() => this.checkSession());
    }

    // A click anywhere on the portal: the menu asks at once (handleNavigation); a click on a page asks a moment later
    // (as soon as the last question is old enough), so that a partner whose login was switched off meanwhile sees the
    // ended screen instead of the page's refusals
    checkAccessAfterClick() {
        const sinceLastCheck = Date.now() - this.lastAccessCheck;
        // Nothing to add when this very click has just asked (the menu, the profile button)
        if (this.endedReason || this.clickCheckTimer || sinceLastCheck < 50) {
            return;
        }
        const wait = Math.max(CLICK_CHECK_DELAY, CLICK_CHECK_GAP - sinceLastCheck);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.clickCheckTimer = setTimeout(() => {
            this.clickCheckTimer = undefined;
            // The menu, or coming back to the tab, may have asked meanwhile
            if (Date.now() - this.lastAccessCheck >= CLICK_CHECK_DELAY) {
                this.refreshAccess();
            }
        }, wait);
    }

    // Salesforce refused the partner's request. Once a login is switched off (a termination, the nightly access check)
    // or the session is over, the browser is the site's guest user to Salesforce: only the login page's class still
    // answers, and it says why (the partner's own session may not call it, so a refusal here means they are still
    // logged in, or offline, and the portal stays as it is).
    async checkSession() {
        if (this.sessionOver || this.checkingSession || !USER_ID) {
            return;
        }
        this.checkingSession = true;
        let timer;
        try {
            // An answer that does not come is no answer: the portal goes on as it was
            const state = await Promise.race([
                getSessionState({ userId: USER_ID, key: this.sessionKey }),
                new Promise((resolve) => {
                    // eslint-disable-next-line @lwc/lwc/no-async-operation
                    timer = setTimeout(resolve, SESSION_CHECK_TIMEOUT);
                })
            ]);
            if (state && state.sessionEnded === true) {
                this.sessionOver = true;
                this.showEnded(SESSION_SCREENS[state.reason] || SIGNED_OUT);
            }
        } catch (e) {
            // Still logged in, or no connection
        } finally {
            clearTimeout(timer);
            this.checkingSession = false;
        }
    }

    // The ended screen replaces everything, open popups included, and takes the focus of the page it replaces
    showEnded(reason) {
        if (this.endedReason !== reason) {
            this.showBell = false;
            this.showLogoutConfirm = false;
            this.pendingFocus = '.ended-title';
        }
        this.endedReason = reason;
    }

    get accessEnded() {
        return Boolean(this.endedReason);
    }

    // What the ended screen shows. While the session lasts its button logs the partner out; once the session is over
    // there is nothing to log out of, and the button leads back to the login page.
    get ended() {
        const screen = ENDED_SCREENS[this.endedReason] || ENDED_SCREENS[ENDED];
        let button = LABELS.ACCESS_ENDED_LOGOUT;
        if (this.endedReason === SIGNED_OUT) {
            button = LABELS.SESSION_ENDED_LOGIN;
        } else if (this.sessionOver) {
            button = LABELS.ACCESS_ENDED_BACK;
        }
        return {
            title: screen.title,
            text: screen.text,
            pictureUrl: screen.picture ? LOGIN_ASSETS + screen.picture : undefined,
            button,
            buttonIcon: this.sessionOver ? undefined : 'utility:logout'
        };
    }

    // The ended screen's one action. With the session over the portal is simply opened again: without a session that is
    // the login page (and the portal itself for a partner who has logged in again in another tab; logging out here
    // would end that new session).
    leaveEnded() {
        if (this.sessionOver) {
            window.location.replace(basePath + '/');
        } else {
            this.confirmLogout();
        }
    }

    // ---------- RENDER CONDITIONS (Boolean) ----------
    get isDashboard() { return this.selectedPage === 'dashboard'; }
    get isLeads()     { return this.selectedPage === 'leads'; }
    get isSiteVisit() { return this.selectedPage === 'siteVisits'; }
    get isMyTeam()    { return this.selectedPage === 'myTeam' && !this.isExecutive; }
    get isContract()  { return this.selectedPage === 'contract' && !this.isExecutive; }
    get isProjects()  { return this.selectedPage === 'projects'; }
    get isCommission() { return this.selectedPage === 'commission'; }
    get isMarketing() { return this.selectedPage === 'marketing'; }
    get isAboutUs()   { return this.selectedPage === 'aboutUs'; }
    get isTerms()     { return this.selectedPage === 'terms'; }
    get isProfile()   { return this.selectedPage === 'profile'; }

    // ---------- LABELS ----------
    get selectedPageLabel() {
        const labels = {
            commission: 'Commission'
        };
        return labels[this.selectedPage] || '';
    }

    get userInitials() {
        if (!this.userName) return 'U';
        return this.userName
            .split(' ')
            .filter(n => n)
            .map(n => n.charAt(0))
            .join('')
            .slice(0, 2)
            .toUpperCase();
    }

    // ---------- THE BELL ----------
    get hasReminders() {
        return this.reminderCount > 0;
    }

    get reminderBadge() {
        return this.reminderCount > 9 ? '9+' : String(this.reminderCount);
    }

    get bellExpanded() {
        return this.showBell ? 'true' : 'false';
    }

    get bellLabel() {
        return this.hasReminders ? `Notifications (${this.reminderCount})` : 'Notifications';
    }

    handleNotifications() {
        this.showBell = !this.showBell;
    }

    closeBell() {
        this.showBell = false;
    }

    // The bell's reminders loaded or a visit was updated there: the count on the bell follows
    handleReminderChange(event) {
        this.reminderCount = event.detail ? event.detail.count || 0 : 0;
    }

    handleProfile() {
        this.selectedPage = 'profile';
        this.refreshAccess();
    }

    // The Profile page's Logout asks for the same confirmation as the menu's
    handleLogoutRequest(event) {
        event.preventDefault();
        this.showLogoutConfirm = true;
    }

    closeLogout() {
        this.showLogoutConfirm = false;
    }

    // The Partner Portal's own logout (basePath is the site's path): the domain's /secur/logout.jsp belongs to another
    // site on this domain and ended on that site's login page. The ended screen logs out without asking; when the
    // session is already over this leads to the login page all the same.
    confirmLogout() {
        window.location.replace(basePath + '/secur/logout.jsp');
    }
}