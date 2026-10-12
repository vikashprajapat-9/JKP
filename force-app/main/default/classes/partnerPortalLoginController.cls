// Username and password login for the Channel Partner Portal's login page, which runs as the site's guest user. A
// username that belongs to no partner leads the page to sign-up; one on a pending registration or a deactivated
// partner gets a status screen instead of a login. Only partners whose account has the channel partner record type
// (Partner Registration Setting) may log in. Executives (channel partner accounts with a Channel Head) are added by
// their channel partner and only ever log in: the page never offers them registration. A partner whose temporary access
// ended without meeting its conditions, or whose account is marked Access Denied, is refused from the day after the end
// date (PartnerTemporaryAccess) and told to contact the JKP CP team: the login page offers no extension of the access
// (a channel head asks for one on the portal, in the last days of the access). An executive goes by their channel
// head's access, and a Terminated partner gets Access Restricted. The portal's shell also asks here why a session that
// was open is over (sessionState): by then the partner is the guest user too.
public without sharing class partnerPortalLoginController {

    public static final String LOGGED_IN = 'LOGGED_IN';
    public static final String NOT_REGISTERED = 'NOT_REGISTERED';
    public static final String UNDER_REVIEW = 'UNDER_REVIEW';
    public static final String RESTRICTED = 'RESTRICTED';
    public static final String EXECUTIVE = 'EXECUTIVE';
    public static final String ACCESS_DENIED = 'ACCESS_DENIED';
    // Why a partner's portal session is over (sessionState)
    public static final String TERMINATED = 'TERMINATED';
    public static final String INACTIVE = 'INACTIVE';
    public static final String SIGNED_OUT = 'SIGNED_OUT';

    private static final String LOGIN_FAILED = 'Incorrect username or password. Please try again, or reset your password.';
    private static final String NOT_CHANNEL_PARTNER = 'This login does not belong to a channel partner account. Please contact the JKP CP team.';

    public class LoginResult {
        // LOGGED_IN (with url), NOT_REGISTERED, UNDER_REVIEW, RESTRICTED, EXECUTIVE (an executive without a login yet)
        // or ACCESS_DENIED (temporary access ended without its conditions met, or the account is marked Access Denied)
        @AuraEnabled public String status;
        // With LOGGED_IN: opens the session and then the page the partner asked for
        @AuraEnabled public String url;
    }

    // Site.login; tests replace it, because no real session can be started there
    public virtual class SiteLogin {
        public virtual PageReference login(String username, String password, String startUrl) {
            return Site.login(username, password, startUrl);
        }
    }

    @TestVisible
    private static SiteLogin sites = new SiteLogin();

    @AuraEnabled
    public static LoginResult login(String username, String password, String startUrl) {
        String name = username == null ? '' : username.trim();
        if (String.isBlank(name) || String.isBlank(password)) {
            throw userError('Enter your username and password.');
        }
        LoginResult result = new LoginResult();
        List<User> partners = partnersFor(name);
        List<User> active = new List<User>();
        for (User partner : partners) {
            if (partner.IsActive) {
                active.add(partner);
            }
        }
        if (active.size() > 1) {
            throw userError('This email is linked to more than one partner login. Please log in with your username.');
        }
        if (active.isEmpty()) {
            // A deactivated partner (for example when temporary access ended) is told their access was revoked; an
            // executive waits for the login JKP releases after approving them, and is never sent to registration
            result.status = !partners.isEmpty() ? (anyAccessDenied(partners) ? ACCESS_DENIED : RESTRICTED)
                : (isExecutive(name) ? EXECUTIVE : (isPendingRegistration(name) ? UNDER_REVIEW : NOT_REGISTERED));
            return result;
        }
        if (isFrozen(active[0].Id)) {
            result.status = RESTRICTED;
            return result;
        }
        // The portal is for channel partners only: the partner's account must have the channel partner record type
        Id partnerType = partnerPortalRegistrationController.partnerRecordTypeId();
        if (partnerType == null) {
            System.debug(LoggingLevel.ERROR, 'Portal login refused: the Partner Registration Setting has no active Account Record Type.');
            throw userError('The portal login is not available right now. Please contact the JKP CP team.');
        }
        if (active[0].Contact.Account.RecordTypeId != partnerType) {
            throw userError(NOT_CHANNEL_PARTNER);
        }
        // A Terminated partner (or an executive of one) is told their access was revoked; temporary access that ended
        // without its conditions met (no converted lead and too few site visits in those days), or an account marked
        // Access Denied, gets Access Denied from the day after the end date: no login either way, and nothing to request
        if (PartnerTemporaryAccess.isTerminated(active[0].Contact.Account)) {
            result.status = RESTRICTED;
            return result;
        }
        if (PartnerTemporaryAccess.isDenied(active[0].Contact.Account)) {
            result.status = ACCESS_DENIED;
            return result;
        }

        PageReference session;
        try {
            session = sites.login(active[0].Username, password, safeStartUrl(startUrl));
        } catch (Exception e) {
            // Wrong password, or the login is locked after too many attempts
            System.debug(LoggingLevel.INFO, 'Portal login failed for ' + active[0].Id + ': ' + e.getMessage());
            throw userError(e.getMessage() != null && e.getMessage().containsIgnoreCase('locked')
                ? 'Your login is locked after too many attempts. Please try again later, or reset your password.'
                : LOGIN_FAILED);
        }
        if (session == null) {
            throw userError(LOGIN_FAILED);
        }
        result.status = LOGGED_IN;
        result.url = session.getUrl();
        return result;
    }

    // What the portal's shell is told when its own Apex calls start failing, for the user it was opened by
    public class SessionState {
        // The caller is the site's guest user: the partner session of this browser is over. A partner who is still
        // logged in is told nothing.
        @AuraEnabled public Boolean sessionEnded = false;
        // Why, once it is over: TERMINATED (the partner, or an executive's channel head), ACCESS_DENIED (the access ended
        // without its conditions met, or the account is marked Access Denied), INACTIVE (the login was switched off for
        // another reason, or frozen) or SIGNED_OUT (the login is fine: the partner logged out elsewhere or the session
        // timed out). Null without the login's session key, and for an id that is no partner login.
        @AuraEnabled public String reason;
    }

    // A partner whose login is switched off while the portal is open (a termination, the nightly access check) is from
    // then on the site's guest user to Salesforce: every Apex call of the portal is refused, and only this class answers.
    // The shell asks here with the id of the user it was opened by and that login's session key, and shows the reason
    // instead of the refusals. Without the key the guest user learns only that there is no session: a user id alone
    // tells a stranger nothing about a partner.
    @AuraEnabled
    public static SessionState sessionState(String userId, String key) {
        SessionState state = new SessionState();
        state.sessionEnded = UserInfo.getUserType() == 'Guest';
        if (!state.sessionEnded || !(userId instanceof Id) || String.isBlank(key) || key != sessionKeyOf(userId)) {
            return state;
        }
        List<User> partners = [
            SELECT Id, IsActive, Contact.Account.Id, Contact.Account.Partner_Type__c, Contact.Account.Temporary_Access_Start_Date__c,
                Contact.Account.Temporary_Access_End_Date__c, Contact.Account.Channel_Head__c, Contact.Account.Channel_Head__r.Id,
                Contact.Account.Channel_Head__r.Partner_Type__c, Contact.Account.Channel_Head__r.Temporary_Access_Start_Date__c,
                Contact.Account.Channel_Head__r.Temporary_Access_End_Date__c
            FROM User
            WHERE Id = :userId AND UserType = 'PowerPartner'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (partners.isEmpty()) {
            return state;
        }
        // A disabled partner user has no contact any more
        Account partner = partners[0].Contact == null ? null : partners[0].Contact.Account;
        if (PartnerTemporaryAccess.isTerminated(partner)) {
            state.reason = TERMINATED;
        } else if (PartnerTemporaryAccess.isDenied(partner)) {
            state.reason = ACCESS_DENIED;
        } else {
            // A frozen login is refused at the login page too (Access Restricted): not merely logged out
            state.reason = partners[0].IsActive && !isFrozen(partners[0].Id) ? SIGNED_OUT : INACTIVE;
        }
        return state;
    }

    // What only a partner's own portal knows about their login: the shell gets it while the partner is logged in
    // (PartnerPortalDashboard.getPortalUser) and shows it again to sessionState. It is made of facts of the login that
    // never change and that no page shows, so it still fits once the login is switched off. Null for an unknown user.
    public static String sessionKeyOf(Id userId) {
        List<User> logins = [
            SELECT Id, CreatedDate, Contact.CreatedDate, Contact.Account.CreatedDate
            FROM User WHERE Id = :userId WITH SYSTEM_MODE LIMIT 1
        ];
        if (logins.isEmpty()) {
            return null;
        }
        User login = logins[0];
        String facts = String.join(new List<String>{
            UserInfo.getOrganizationId(), login.Id, String.valueOf(login.CreatedDate.getTime()),
            String.valueOf(login.Contact?.CreatedDate?.getTime()), String.valueOf(login.Contact?.Account?.CreatedDate?.getTime())
        }, '|');
        return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(facts)));
    }

    // Whether one of these deactivated partner logins is on an account marked Access Denied, or is an executive of one
    // (a disabled partner user has no contact any more)
    @TestVisible
    private static Boolean anyAccessDenied(List<User> partners) {
        for (User partner : partners) {
            Account partnerAccount = partner.Contact == null ? null : partner.Contact.Account;
            if (partnerAccount != null && (partnerAccount.Partner_Type__c == PartnerTemporaryAccess.ACCESS_DENIED
                    || (partnerAccount.Channel_Head__r != null && partnerAccount.Channel_Head__r.Partner_Type__c == PartnerTemporaryAccess.ACCESS_DENIED))) {
                return true;
            }
        }
        return false;
    }

    // Whether this username or email belongs to an executive, so the login page stops offering registration
    @AuraEnabled(cacheable=true)
    public static Boolean isExecutiveUsername(String username) {
        return isExecutive(username == null ? '' : username.trim());
    }

    // An executive: a channel partner account with a Channel Head that has this username or email on its partner
    // login, as its own email or on one of its contacts
    private static Boolean isExecutive(String name) {
        Id partnerType = partnerPortalRegistrationController.partnerRecordTypeId();
        if (String.isBlank(name) || partnerType == null) {
            return false;
        }
        Integer users = [
            SELECT COUNT()
            FROM User
            WHERE UserType = 'PowerPartner' AND (Username = :name OR Email = :name)
                AND Contact.Account.RecordTypeId = :partnerType AND Contact.Account.Channel_Head__c != null
            WITH SYSTEM_MODE
        ];
        if (users > 0 || !name.contains('@')) {
            return users > 0;
        }
        // A rejected executive is no longer waiting for a login (and may be added, or register, again). Without a
        // rejected status in the settings, a value no account has: comparing with null would leave out every account
        // without a status.
        String rejected = partnerPortalRegistrationController.rejectedStatus();
        rejected = rejected == null ? '(no rejected status)' : rejected;
        Integer contacts = [
            SELECT COUNT()
            FROM Contact
            WHERE Email = :name AND Account.RecordTypeId = :partnerType AND Account.Channel_Head__c != null
                AND Account.Onboarding_Status__c != :rejected
            WITH SYSTEM_MODE
        ];
        Integer accounts = [
            SELECT COUNT()
            FROM Account
            WHERE Email__c = :name AND RecordTypeId = :partnerType AND Channel_Head__c != null AND Onboarding_Status__c != :rejected
            WITH SYSTEM_MODE
        ];
        return contacts + accounts > 0;
    }

    // Partner portal users (active or not) with this username; failing that, with this email (partners usually know
    // their email, while PartnerPortalUserCreation gives them the username "<email>.partner")
    private static List<User> partnersFor(String name) {
        List<User> byUsername = [
            SELECT Id, Username, IsActive, Contact.Account.Id, Contact.Account.RecordTypeId, Contact.Account.Partner_Type__c,
                Contact.Account.Temporary_Access_Start_Date__c, Contact.Account.Temporary_Access_End_Date__c,
                Contact.Account.Channel_Head__c, Contact.Account.Channel_Head__r.Id, Contact.Account.Channel_Head__r.Partner_Type__c,
                Contact.Account.Channel_Head__r.Temporary_Access_Start_Date__c, Contact.Account.Channel_Head__r.Temporary_Access_End_Date__c
            FROM User
            WHERE UserType = 'PowerPartner' AND Username = :name
            WITH SYSTEM_MODE
            LIMIT 5
        ];
        if (!byUsername.isEmpty() || !name.contains('@')) {
            return byUsername;
        }
        return [
            SELECT Id, Username, IsActive, Contact.Account.Id, Contact.Account.RecordTypeId, Contact.Account.Partner_Type__c,
                Contact.Account.Temporary_Access_Start_Date__c, Contact.Account.Temporary_Access_End_Date__c,
                Contact.Account.Channel_Head__c, Contact.Account.Channel_Head__r.Id, Contact.Account.Channel_Head__r.Partner_Type__c,
                Contact.Account.Channel_Head__r.Temporary_Access_Start_Date__c, Contact.Account.Channel_Head__r.Temporary_Access_End_Date__c
            FROM User
            WHERE UserType = 'PowerPartner' AND Email = :name
            WITH SYSTEM_MODE
            LIMIT 5
        ];
    }

    // A registration waiting for approval: a channel partner account with the registration status of the Partner
    // Registration Setting that carries this email, itself or on one of its contacts
    private static Boolean isPendingRegistration(String name) {
        String status = partnerPortalRegistrationController.registrationStatus();
        Id partnerType = partnerPortalRegistrationController.partnerRecordTypeId();
        if (!name.contains('@') || status == null || partnerType == null) {
            return false;
        }
        Integer contacts = [
            SELECT COUNT()
            FROM Contact
            WHERE Email = :name AND Account.Onboarding_Status__c = :status AND Account.RecordTypeId = :partnerType
            WITH SYSTEM_MODE
        ];
        Integer accounts = [
            SELECT COUNT()
            FROM Account
            WHERE Email__c = :name AND Onboarding_Status__c = :status AND RecordTypeId = :partnerType
            WITH SYSTEM_MODE
        ];
        return contacts + accounts > 0;
    }

    private static Boolean isFrozen(Id userId) {
        List<UserLogin> logins = [SELECT IsFrozen FROM UserLogin WHERE UserId = :userId WITH SYSTEM_MODE LIMIT 1];
        return !logins.isEmpty() && logins[0].IsFrozen;
    }

    // Only a path on this site: another host, a protocol-relative URL or a script is never used
    @TestVisible
    private static String safeStartUrl(String startUrl) {
        String value = startUrl == null ? '' : startUrl.trim();
        if (!value.startsWith('/') || value.startsWith('//') || value.contains('\\') || value.contains(':')) {
            return '/';
        }
        return value;
    }

    // AuraHandledException only exposes its text to Apex callers (and tests) when setMessage is also called
    private static AuraHandledException userError(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}