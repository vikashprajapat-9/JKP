@isTest
private class CustomerPortalLoginControllerTest {

    private static final String GOOD_PASSWORD = 'Correct#Horse9';
    private static final String LOGIN_FAILED = 'Your login attempt has failed. Make sure the username and password are correct.';

    // Stands in for Site.login: accepts GOOD_PASSWORD, refuses anything else with Salesforce's message, and records
    // what it was given
    private class FakeSiteLogin extends CustomerPortalLoginController.SiteLogin {
        public String username;
        public String startUrl;

        public override PageReference login(String username, String password, String startUrl) {
            this.username = username;
            this.startUrl = startUrl;
            if (password != GOOD_PASSWORD) {
                throw new SecurityException(LOGIN_FAILED);
            }
            return new PageReference('https://customers.example.com/secur/frontdoor.jsp?retURL=' + startUrl);
        }
    }

    private static FakeSiteLogin fakeSite() {
        FakeSiteLogin fake = new FakeSiteLogin();
        CustomerPortalLoginController.sites = fake;
        return fake;
    }

    private class FakeSiteException extends Exception {}

    // Stands in for Site.forgotPassword: records what it was asked and answers as the test says (true, false as it does
    // outside a Visualforce page, or fails)
    private class FakeSitePasswords extends CustomerPortalLoginController.SitePasswords {
        public Boolean siteAnswer = true;
        public Boolean siteFails = false;
        public List<String> forgotFor = new List<String>();

        public override Boolean forgotPassword(String username) {
            forgotFor.add(username);
            if (siteFails) {
                throw new FakeSiteException('Site.forgotPassword failed for ' + username);
            }
            return siteAnswer;
        }
    }

    private static FakeSitePasswords fakePasswords() {
        FakeSitePasswords fake = new FakeSitePasswords();
        CustomerPortalLoginController.passwords = fake;
        return fake;
    }

    // The message the forgot-password page shows, or null when the request was taken
    private static String resetError(String username) {
        try {
            CustomerPortalLoginController.requestPasswordReset(username);
            return null;
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
    }

    // The message shown on the login page, or the address a login that was not refused opens
    private static String loginError(String username, String password, String startUrl) {
        try {
            return 'Not refused: ' + CustomerPortalLoginController.login(username, password, startUrl);
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
    }

    private static String issueError(String email, String mobile, String description) {
        try {
            CustomerPortalLoginController.reportIssue(email, mobile, description);
            return null;
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
    }

    private static User siteGuest() {
        return [SELECT Id FROM User WHERE UserType = 'Guest' AND Profile.Name = 'SFA Profile' AND IsActive = true LIMIT 1];
    }

    private static List<Case> issues() {
        return [
            SELECT Origin, Subject, Description, Email__c, Phone__c
            FROM Case
            WHERE Subject = :CustomerPortalLoginController.ISSUE_SUBJECT
            WITH SYSTEM_MODE
        ];
    }

    // Customer community logins with this email, on a Customer account whose owner has a role (a portal account needs one)
    private static List<User> customersWithEmail(String email, Integer count) {
        return loginsOnAccount(email, count, 'Customer');
    }

    // Calls of loginsOnAccount so far, so each call gets its own owner and usernames
    private static Integer accountsMade = 0;

    // The same, on an account of the given record type
    private static List<User> loginsOnAccount(String email, Integer count, String recordType) {
        accountsMade++;
        UserRole role = new UserRole(Name = 'Customer Portal Test Owner ' + accountsMade);
        User owner = newUser([SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id, 'cpown' + accountsMade, 'cpowner@customer-test.example.com');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert role;
            owner.UserRoleId = role.Id;
            insert owner;
        }
        Id customerProfileId = [SELECT Id FROM Profile WHERE UserType = 'PowerCustomerSuccess' ORDER BY Name LIMIT 1].Id;
        List<User> customers = new List<User>();
        System.runAs(owner) {
            Account account = new Account(
                Name = 'Customer Portal Test',
                RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get(recordType).getRecordTypeId()
            );
            insert account;
            List<Contact> contacts = new List<Contact>();
            for (Integer i = 0; i < count; i++) {
                contacts.add(new Contact(LastName = 'Customer ' + i, AccountId = account.Id, Email = email));
            }
            insert contacts;
            for (Integer i = 0; i < count; i++) {
                User customer = newUser(customerProfileId, 'cpc' + accountsMade + '_' + i, email);
                customer.ContactId = contacts[i].Id;
                customers.add(customer);
            }
            insert customers;
        }
        return [SELECT Username, Email FROM User WHERE Id IN :customers ORDER BY Alias];
    }

    private static User newUser(Id profileId, String alias, String email) {
        return new User(
            ProfileId = profileId,
            LastName = 'Customer Portal Test ' + alias,
            Alias = alias,
            Email = email,
            Username = alias + '.' + UserInfo.getOrganizationId() + '@customer-test.example.com',
            TimeZoneSidKey = 'Asia/Colombo',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }

    @isTest
    static void logsACustomerInAndOpensThePageTheyAskedFor() {
        User customer = customersWithEmail('jane.customer@customer-test.example.com', 1)[0];
        FakeSiteLogin fake = fakeSite();

        Test.startTest();
        String url = CustomerPortalLoginController.login('  ' + customer.Username + ' ', GOOD_PASSWORD, '/SFA/');
        Test.stopTest();

        System.assert(url.contains('frontdoor.jsp') && EncodingUtil.urlDecode(url, 'UTF-8').contains('/SFA/'), url);
        System.assertEquals(customer.Username, fake.username, 'The username is trimmed before logging in');
        System.assertEquals('/SFA/', fake.startUrl);
    }

    @isTest
    static void refusesALoginWhoseAccountIsNotACustomer() {
        User partner = loginsOnAccount('cp.contact@customer-test.example.com', 1, 'Channel_Partner')[0];
        FakeSiteLogin fake = fakeSite();

        Test.startTest();
        String rightPassword = loginError(partner.Username, GOOD_PASSWORD, '/SFA/');
        String wrongPassword = loginError(partner.Username, 'not-it', '/SFA/');
        Test.stopTest();

        System.assertEquals(CustomerPortalLoginController.NOT_A_CUSTOMER, rightPassword, 'Told only after the password was accepted');
        System.assertEquals(LOGIN_FAILED, wrongPassword, 'A wrong password does not reveal the kind of account');
        System.assertEquals(partner.Username, fake.username);
    }

    @isTest
    static void thePortalOpensOnlyForContactsOfCustomerAccounts() {
        User customer = customersWithEmail('open.customer@customer-test.example.com', 1)[0];
        User partner = loginsOnAccount('open.partner@customer-test.example.com', 1, 'Channel_Partner')[0];
        Boolean forCustomer;
        Boolean forPartner;
        Boolean forGuest;

        Test.startTest();
        System.runAs(new User(Id = customer.Id)) {
            forCustomer = CustomerPortalLoginController.isCustomer();
        }
        System.runAs(new User(Id = partner.Id)) {
            forPartner = CustomerPortalLoginController.isCustomer();
        }
        System.runAs(siteGuest()) {
            forGuest = CustomerPortalLoginController.isCustomer();
        }
        Test.stopTest();

        System.assertEquals(true, forCustomer);
        System.assertEquals(false, forPartner);
        System.assertEquals(false, forGuest);
    }

    @isTest
    static void acceptsTheEmailOfACustomerLogin() {
        User customer = customersWithEmail('jane@customer-test.example.com', 1)[0];
        FakeSiteLogin fake = fakeSite();
        String url;

        Test.startTest();
        System.runAs(siteGuest()) {
            url = CustomerPortalLoginController.login(customer.Email, GOOD_PASSWORD, '/SFA/');
        }
        Test.stopTest();

        System.assertNotEquals(null, url);
        System.assertEquals(customer.Username, fake.username, 'Salesforce is given the real username');
    }

    @isTest
    static void triesTheEmailAsTypedWhenItHasSeveralLogins() {
        customersWithEmail('family@customer-test.example.com', 2);
        FakeSiteLogin fake = fakeSite();

        Test.startTest();
        String message = loginError('family@customer-test.example.com', GOOD_PASSWORD, '/SFA/');
        Test.stopTest();

        // Salesforce's own failure, which does not tell whether the email has logins
        System.assertEquals('family@customer-test.example.com', fake.username, 'The email goes to Salesforce as typed');
        System.assert(!message.contains('more than one'), message);
    }

    @isTest
    static void showsSalesforcesMessageForAWrongPassword() {
        fakeSite();

        Test.startTest();
        String message = loginError('jane.customer@example.com', 'not-it', '/SFA/');
        Test.stopTest();

        System.assertEquals(LOGIN_FAILED, message);
    }

    @isTest
    static void refusesALoginThatStartsNoSession() {
        // The real Site.login: it starts no session in a test and returns nothing
        Test.startTest();
        String message = loginError('nobody@customer-test.example.com', 'whatever', '/SFA/');
        Test.stopTest();

        System.assertEquals(LOGIN_FAILED, message);
    }

    @isTest
    static void requiresAUsernameAndPassword() {
        FakeSiteLogin fake = fakeSite();

        Test.startTest();
        String noUsername = loginError('   ', GOOD_PASSWORD, '/SFA/');
        String noPassword = loginError('jane.customer@example.com', '', '/SFA/');
        Test.stopTest();

        System.assertEquals('Enter your username and password.', noUsername);
        System.assertEquals('Enter your username and password.', noPassword);
        System.assertEquals(null, fake.username, 'Salesforce is not asked');
    }

    @isTest
    static void neverRedirectsOffTheSite() {
        String username = customersWithEmail('redirect@customer-test.example.com', 1)[0].Username;
        FakeSiteLogin fake = fakeSite();

        Test.startTest();
        CustomerPortalLoginController.login(username, GOOD_PASSWORD, 'https://elsewhere.example.com/');
        String otherHost = fake.startUrl;
        CustomerPortalLoginController.login(username, GOOD_PASSWORD, '//elsewhere.example.com/');
        String protocolRelative = fake.startUrl;
        CustomerPortalLoginController.login(username, GOOD_PASSWORD, null);
        String none = fake.startUrl;
        Test.stopTest();

        System.assertEquals('/', otherHost);
        System.assertEquals('/', protocolRelative);
        System.assertEquals('/', none);
        System.assertEquals('/SFA/my-properties', CustomerPortalLoginController.safeStartUrl(' /SFA/my-properties '));
        System.assertEquals('/', CustomerPortalLoginController.safeStartUrl('javascript:alert(1)'));
        System.assertEquals('/', CustomerPortalLoginController.safeStartUrl('/\\elsewhere.example.com'));
    }

    @isTest
    static void savesTheIssueAsACaseForCustomerService() {
        Test.startTest();
        System.runAs(siteGuest()) {
            CustomerPortalLoginController.reportIssue(' Praveen@gmail.com ', ' 9978986756 ', '  Unable to login  ');
        }
        Test.stopTest();

        List<Case> saved = issues();
        System.assertEquals(1, saved.size(), 'One Case and nothing else');
        System.assertEquals('Web', saved[0].Origin);
        System.assertEquals('Customer Portal login issue', saved[0].Subject);
        System.assertEquals('Unable to login', saved[0].Description);
        System.assertEquals('praveen@gmail.com', saved[0].Email__c.toLowerCase());
        System.assertEquals('9978986756', saved[0].Phone__c);
    }

    @isTest
    static void savesARepeatedRequestOnceAndLimitsRequestsPerHour() {
        String limitMessage;
        Test.startTest();
        System.runAs(siteGuest()) {
            CustomerPortalLoginController.reportIssue('repeat@example.com', '0771234567', 'Cannot log in');
            // a second click or a dropped connection sends the same request again
            CustomerPortalLoginController.reportIssue('repeat@example.com', '0771234567', 'Cannot log in');
            CustomerPortalLoginController.reportIssue('repeat@example.com', '0771234567', 'Second problem');
            CustomerPortalLoginController.reportIssue('repeat@example.com', '0771234567', 'Third problem');
            try {
                CustomerPortalLoginController.reportIssue('repeat@example.com', '0771234567', 'Fourth problem');
            } catch (AuraHandledException e) {
                limitMessage = e.getMessage();
            }
        }
        Test.stopTest();

        System.assertEquals(3, issues().size(), 'The repeat is saved once; at most three requests an hour');
        System.assertEquals(CustomerPortalLoginController.ISSUE_LIMIT, limitMessage);
    }

    @isTest
    static void acceptsMobileNumbersWrittenWithACountryCode() {
        Test.startTest();
        System.runAs(siteGuest()) {
            CustomerPortalLoginController.reportIssue('praveen@example.com', '+94 (77) 123-4567', 'Forgot my username');
            CustomerPortalLoginController.reportIssue('praveen@example.com', '077 123 4567', 'Forgot my password');
        }
        Test.stopTest();

        System.assertEquals(2, issues().size());
    }

    @isTest
    static void checksTheEmailMobileAndDescriptionBeforeSaving() {
        String tooLong = 'x'.repeat(CustomerPortalLoginController.MAX_DESCRIPTION + 1);
        Map<String, String> errors = new Map<String, String>();

        Test.startTest();
        System.runAs(siteGuest()) {
            errors.put('no email', issueError('  ', '9978986756', 'Unable to login'));
            errors.put('no mobile', issueError('praveen@example.com', null, 'Unable to login'));
            errors.put('no description', issueError('praveen@example.com', '9978986756', '   '));
            errors.put('bad email', issueError('praveen.example.com', '9978986756', 'Unable to login'));
            errors.put('long email', issueError('a'.repeat(75) + '@example.com', '9978986756', 'Unable to login'));
            errors.put('letters', issueError('praveen@example.com', '99789-ABCDE', 'Unable to login'));
            errors.put('short mobile', issueError('praveen@example.com', '0771234', 'Unable to login'));
            errors.put('long mobile', issueError('praveen@example.com', '1234567890123456', 'Unable to login'));
            errors.put('long description', issueError('praveen@example.com', '9978986756', tooLong));
        }
        Test.stopTest();

        System.assertEquals('Enter your email, mobile number and what went wrong.', errors.get('no email'));
        System.assertEquals('Enter your email, mobile number and what went wrong.', errors.get('no mobile'));
        System.assertEquals('Enter your email, mobile number and what went wrong.', errors.get('no description'));
        System.assertEquals('Enter a valid email address.', errors.get('bad email'));
        System.assertEquals('Enter a valid email address.', errors.get('long email'));
        System.assertEquals('Enter a valid mobile number.', errors.get('letters'));
        System.assertEquals('Enter a valid mobile number.', errors.get('short mobile'));
        System.assertEquals('Enter a valid mobile number.', errors.get('long mobile'));
        System.assert(errors.get('long description').contains(String.valueOf(CustomerPortalLoginController.MAX_DESCRIPTION)), errors.get('long description'));
        System.assertEquals(0, issues().size(), 'Nothing is saved');
    }

    @isTest
    static void forgotPasswordSendsTheSitesEmailToACustomer() {
        User customer = customersWithEmail('reset.customer@customer-test.example.com', 1)[0];
        FakeSitePasswords fake = fakePasswords();
        String message;

        Test.startTest();
        System.runAs(siteGuest()) {
            message = resetError('  ' + customer.Username + ' ');
        }
        Test.stopTest();

        System.assertEquals(null, message);
        System.assertEquals(new List<String>{ customer.Username }, fake.forgotFor, 'The trimmed username goes to Site.forgotPassword');
    }

    @isTest
    static void forgotPasswordAcceptsTheEmailOfACustomerLogin() {
        User customer = customersWithEmail('reset.byemail@customer-test.example.com', 1)[0];
        FakeSitePasswords fake = fakePasswords();

        Test.startTest();
        System.runAs(siteGuest()) {
            CustomerPortalLoginController.requestPasswordReset(customer.Email);
        }
        Test.stopTest();

        System.assertEquals(new List<String>{ customer.Username }, fake.forgotFor, 'Salesforce is given the real username');
    }

    @isTest
    static void forgotPasswordSendsNothingForOtherLoginsAndAnswersTheSame() {
        User partner = loginsOnAccount('reset.partner@customer-test.example.com', 1, 'Channel_Partner')[0];
        customersWithEmail('reset.family@customer-test.example.com', 2);
        // The admin running the test: an internal login, which this page never resets
        String internalUsername = UserInfo.getUserName();
        FakeSitePasswords fake = fakePasswords();
        Map<String, String> answers = new Map<String, String>();

        Test.startTest();
        System.runAs(siteGuest()) {
            answers.put('channel partner', resetError(partner.Username));
            answers.put('channel partner email', resetError(partner.Email));
            answers.put('unknown', resetError('nobody@customer-test.example.com'));
            answers.put('unknown name', resetError('nobody'));
            answers.put('email of two logins', resetError('reset.family@customer-test.example.com'));
            answers.put('internal user', resetError(internalUsername));
        }
        Test.stopTest();

        for (String kind : answers.keySet()) {
            System.assertEquals(null, answers.get(kind), 'The same answer as for a customer: ' + kind);
        }
        System.assertEquals(0, fake.forgotFor.size(), 'No site email');
    }

    @isTest
    static void forgotPasswordRequiresAUsername() {
        FakeSitePasswords fake = fakePasswords();

        Test.startTest();
        String blank = resetError('   ');
        String none = resetError(null);
        Test.stopTest();

        System.assertEquals('Enter your username.', blank);
        System.assertEquals('Enter your username.', none);
        System.assertEquals(0, fake.forgotFor.size());
    }

    @isTest
    static void forgotPasswordAsksTheSiteOnceWhateverItAnswers() {
        // Site.forgotPassword answers false outside a Visualforce page even when it sent the email: nothing else is tried
        User customer = customersWithEmail('reset.false@customer-test.example.com', 1)[0];
        FakeSitePasswords fake = fakePasswords();
        fake.siteAnswer = false;
        String message;

        Test.startTest();
        System.runAs(siteGuest()) {
            message = resetError(customer.Username);
        }
        Test.stopTest();

        System.assertEquals(null, message);
        System.assertEquals(new List<String>{ customer.Username }, fake.forgotFor, 'Asked once, and no password reset');
    }

    @isTest
    static void forgotPasswordAnswersNormallyWhenNoEmailCanBeSent() {
        User customer = customersWithEmail('reset.noemail@customer-test.example.com', 1)[0];
        FakeSitePasswords fake = fakePasswords();
        fake.siteFails = true;
        String message;

        Test.startTest();
        System.runAs(siteGuest()) {
            message = resetError(customer.Username);
        }
        Test.stopTest();

        System.assertEquals(null, message, 'The page shows its confirmation; the failure is only in the debug log');
        System.assertEquals(1, fake.forgotFor.size());
    }

    @isTest
    static void forgotPasswordWithTheRealSiteCallsAnswersNormally() {
        // Salesforce's own call: a test has no site, so Site.forgotPassword answers false and sends nothing
        User customer = customersWithEmail('reset.real@customer-test.example.com', 1)[0];
        String message;

        Test.startTest();
        System.runAs(siteGuest()) {
            message = resetError(customer.Username);
        }
        Test.stopTest();

        System.assertEquals(null, message);
    }

    @isTest
    static void masksTheUsernameForTheDebugLog() {
        System.assertEquals('ja***@cu***', CustomerPortalLoginController.masked('jane@customer-test.example.com'));
        System.assertEquals('ja***', CustomerPortalLoginController.masked('jane'));
        System.assertEquals('j***', CustomerPortalLoginController.masked('j'));
        System.assertEquals('', CustomerPortalLoginController.masked('  '));
    }
}