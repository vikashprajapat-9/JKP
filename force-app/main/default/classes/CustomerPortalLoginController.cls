// The Customer Portal's (Experience site SFA) login and forgot-password pages, which run as the site's guest user.
// Customers log in with their username (or the email of their login) and password through Salesforce's own site login,
// as their customer community users. "Facing an issue?" saves what the customer wrote, with their email and mobile
// number, as a Case for the customer service team; nothing else is created. "Forgot Password?" emails a customer login
// the link to choose a new password.
public without sharing class CustomerPortalLoginController {

    @TestVisible
    private static final String ISSUE_SUBJECT = 'Customer Portal login issue';
    // A value of the Case Origin picklist
    @TestVisible
    private static final String ISSUE_ORIGIN = 'Web';
    @TestVisible
    private static final Integer MAX_DESCRIPTION = 2000;

    // Only people whose account is a customer may use this portal (Account record type "Customer")
    private static final String CUSTOMER_RECORD_TYPE = 'Customer';
    @TestVisible
    private static final String NOT_A_CUSTOMER = 'This portal is only for John Keells Properties customers.';
    private static final String LOGIN_FAILED = 'Your login attempt has failed. Make sure the username and password are correct.';
    private static final String NOT_SENT = 'Your request could not be sent right now. Please try again.';
    private static final Integer MIN_PHONE_DIGITS = 9;
    private static final Integer MAX_PHONE_DIGITS = 15;
    private static final Integer MAX_EMAIL = 80;
    private static final Integer MAX_PHONE = 40;
    // The public issue form: the same request again within this many minutes is not saved twice, and one email or
    // mobile number opens at most MAX_ISSUES_PER_HOUR requests an hour
    private static final Integer REPEAT_MINUTES = 10;
    private static final Integer MAX_ISSUES_PER_HOUR = 3;
    @TestVisible private static final String ISSUE_LIMIT = 'We have already received your requests. Our team will contact you shortly.';
    // The user types of customer community logins
    private static final Set<String> CUSTOMER_USER_TYPES = new Set<String>{ 'PowerCustomerSuccess', 'CspLitePortal', 'CustomerSuccess' };
    private static final Pattern EMAIL_PATTERN = Pattern.compile('^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$');
    private static final Pattern PHONE_PATTERN = Pattern.compile('^\\+?[0-9 ().-]+$');

    // Site.login; tests replace it, because no real session can be started there
    public virtual class SiteLogin {
        public virtual PageReference login(String username, String password, String startUrl) {
            return Site.login(username, password, startUrl);
        }
    }

    @TestVisible
    private static SiteLogin sites = new SiteLogin();

    // Site.forgotPassword, which sends the site's Forgot Password email (Administration > Emails: Customer Portal Forgot
    // Password) with the link to choose a new password; tests replace it, because a test has no site and sends no email
    public virtual class SitePasswords {
        public virtual Boolean forgotPassword(String username) {
            return Site.forgotPassword(username);
        }
    }

    @TestVisible
    private static SitePasswords passwords = new SitePasswords();

    // Logs the customer in and returns the address that opens their session and then the page they asked for. A
    // refused login shows Salesforce's own message (wrong username or password, a locked login, ...).
    @AuraEnabled
    public static String login(String username, String password, String startUrl) {
        String name = username == null ? '' : username.trim();
        if (String.isBlank(name) || String.isBlank(password)) {
            throw userError('Enter your username and password.');
        }
        String loginName = usernameFor(name);
        PageReference session;
        try {
            session = sites.login(loginName, password, safeStartUrl(startUrl));
        } catch (Exception e) {
            System.debug(LoggingLevel.INFO, 'Customer Portal login refused: ' + e.getMessage());
            throw userError(String.isBlank(e.getMessage()) ? LOGIN_FAILED : e.getMessage());
        }
        if (session == null) {
            throw userError(LOGIN_FAILED);
        }
        // Checked once Salesforce has accepted the password, so nobody learns what kind of login a username is without
        // it; the session Salesforce started is not handed out
        if (!isCustomerLogin(loginName)) {
            throw userError(NOT_A_CUSTOMER);
        }
        return session.getUrl();
    }

    // "Facing an issue?": a Case with the customer's email and mobile number in its own fields and their text as the
    // description. Saved in system mode: the guest user has no access to Cases.
    @AuraEnabled
    public static void reportIssue(String email, String mobile, String description) {
        String mail = email == null ? '' : email.trim();
        String phone = mobile == null ? '' : mobile.trim();
        String text = description == null ? '' : description.trim();
        if (String.isBlank(mail) || String.isBlank(phone) || String.isBlank(text)) {
            throw userError('Enter your email, mobile number and what went wrong.');
        }
        if (mail.length() > MAX_EMAIL || !EMAIL_PATTERN.matcher(mail).matches()) {
            throw userError('Enter a valid email address.');
        }
        if (phone.length() > MAX_PHONE || !isMobile(phone)) {
            throw userError('Enter a valid mobile number.');
        }
        if (text.length() > MAX_DESCRIPTION) {
            throw userError('Please describe the issue in ' + MAX_DESCRIPTION + ' characters or fewer.');
        }
        Datetime hourAgo = System.now().addHours(-1);
        Datetime repeatSince = System.now().addMinutes(-REPEAT_MINUTES);
        List<Case> recent = [
            SELECT Description, CreatedDate
            FROM Case
            WHERE Subject = :ISSUE_SUBJECT AND (Email__c = :mail OR Phone__c = :phone) AND CreatedDate >= :hourAgo
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 20
        ];
        for (Case earlier : recent) {
            // The same request sent again (a second click, a dropped connection): it is already with the team
            if (earlier.CreatedDate >= repeatSince && text.equals(earlier.Description)) {
                return;
            }
        }
        if (recent.size() >= MAX_ISSUES_PER_HOUR) {
            throw userError(ISSUE_LIMIT);
        }
        Case issue = new Case(
            Origin = ISSUE_ORIGIN,
            Subject = ISSUE_SUBJECT,
            Description = text,
            Email__c = mail,
            Phone__c = phone
        );
        try {
            insert as system issue;
        } catch (DmlException e) {
            System.debug(LoggingLevel.ERROR, 'Customer Portal login issue not saved: ' + e.getMessage());
            throw userError(e.getDmlType(0) == StatusCode.INVALID_EMAIL_ADDRESS ? 'Enter a valid email address.' : NOT_SENT);
        }
    }

    // "Forgot Password?": emails the link to choose a new password to the email address of the login. The username is
    // resolved as login() does; only an active login of a contact of a Customer account (and a member of this site)
    // gets the email. The answer is the same for every username, so the page never tells whether a username exists or
    // what kind of login it is. The email is the site's own Forgot Password email (Site.forgotPassword, as the Partner
    // Portal's Forgot Password page and Salesforce's LightningForgotPasswordController send it). Its answer is not used:
    // Salesforce documents that it answers false whenever it is not called from a Visualforce page, as here. The password
    // itself is never reset here (System.resetPassword ends the current password at once, and anybody who knows a
    // customer's username or email could trigger it).
    @AuraEnabled
    public static void requestPasswordReset(String username) {
        String name = username == null ? '' : username.trim();
        if (String.isBlank(name)) {
            throw userError('Enter your username.');
        }
        String loginName = usernameFor(name);
        User customer = customerLogin(loginName);
        if (customer == null || !isMemberOfThisSite(customer.Id)) {
            System.debug(LoggingLevel.INFO, 'Customer Portal password reset: no customer login for ' + masked(name));
            return;
        }
        try {
            passwords.forgotPassword(loginName);
            System.debug(LoggingLevel.INFO, 'Customer Portal password reset email requested for ' + masked(name));
        } catch (Exception e) {
            System.debug(LoggingLevel.INFO, 'Customer Portal Site.forgotPassword failed for ' + masked(name) + ': '
                + e.getTypeName() + ' ' + withoutLogin(e.getMessage(), loginName, customer.Id));
        }
    }

    // The username as typed when a login has it; failing that, the username of the one active customer login of this
    // site with this email (customers know their email, while their username can differ). Anything else is passed on
    // unchanged, so Salesforce's own failure message shows and nobody learns whether an email has a login.
    private static String usernameFor(String name) {
        Integer byUsername = [SELECT COUNT() FROM User WHERE Username = :name WITH SYSTEM_MODE];
        if (byUsername > 0 || !name.contains('@')) {
            return name;
        }
        List<String> usernames = new List<String>();
        Id networkId = Network.getNetworkId();
        if (networkId != null) {
            for (NetworkMember member : [
                SELECT Member.Username
                FROM NetworkMember
                WHERE NetworkId = :networkId AND Member.Email = :name AND Member.IsActive = true
                    AND Member.UserType IN :CUSTOMER_USER_TYPES
                WITH SYSTEM_MODE
                LIMIT 2
            ]) {
                usernames.add(member.Member.Username);
            }
        } else {
            for (User u : [
                SELECT Username
                FROM User
                WHERE Email = :name AND IsActive = true AND UserType IN :CUSTOMER_USER_TYPES
                WITH SYSTEM_MODE
                LIMIT 2
            ]) {
                usernames.add(u.Username);
            }
        }
        return usernames.size() == 1 ? usernames[0] : name;
    }

    // The portal asks this when it opens, for a session that did not come through this page (for example the automatic
    // login after a password reset): only a contact of a Customer account may use it
    @AuraEnabled
    public static Boolean isCustomer() {
        List<User> users = [
            SELECT Contact.Account.RecordType.DeveloperName
            FROM User
            WHERE Id = :UserInfo.getUserId()
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return !users.isEmpty() && isCustomerAccount(users[0]);
    }

    // Whether the active login with this username belongs to a contact of a Customer account
    private static Boolean isCustomerLogin(String username) {
        return customerLogin(username) != null;
    }

    // The active login with this username when it belongs to a contact of a Customer account, otherwise null
    private static User customerLogin(String username) {
        List<User> users = [
            SELECT Id, Contact.Account.RecordType.DeveloperName
            FROM User
            WHERE Username = :username AND IsActive = true
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return !users.isEmpty() && isCustomerAccount(users[0]) ? users[0] : null;
    }

    // Whether the login may use this site (always true outside a site, as in tests)
    private static Boolean isMemberOfThisSite(Id userId) {
        Id networkId = Network.getNetworkId();
        return networkId == null
            || [SELECT COUNT() FROM NetworkMember WHERE NetworkId = :networkId AND MemberId = :userId WITH SYSTEM_MODE] > 0;
    }

    // A username or email for the debug log: two characters of each part around the @, the rest hidden
    @TestVisible
    private static String masked(String name) {
        if (String.isBlank(name)) {
            return '';
        }
        List<String> parts = new List<String>();
        for (String part : name.split('@', 2)) {
            parts.add(part.left(2) + '***');
        }
        return String.join(parts, '@');
    }

    // An error message for the debug log, without the login's username or id
    private static String withoutLogin(String message, String loginName, Id userId) {
        String text = message == null ? '' : message;
        text = text.replace(loginName, masked(loginName));
        text = text.replace(String.valueOf(userId), '[user]');
        return text.replace(String.valueOf(userId).left(15), '[user]');
    }

    private static Boolean isCustomerAccount(User login) {
        return login.Contact != null && login.Contact.Account != null && login.Contact.Account.RecordType != null
            && CUSTOMER_RECORD_TYPE.equals(login.Contact.Account.RecordType.DeveloperName);
    }

    private static Boolean isMobile(String value) {
        Integer digits = value.replaceAll('[^0-9]', '').replaceFirst('^0+', '').length();
        return PHONE_PATTERN.matcher(value).matches() && digits >= MIN_PHONE_DIGITS && digits <= MAX_PHONE_DIGITS;
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