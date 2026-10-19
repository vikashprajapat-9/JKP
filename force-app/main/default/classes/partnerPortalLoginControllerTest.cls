@isTest
private class partnerPortalLoginControllerTest {

    private static final String GOOD_PASSWORD = 'Correct#Horse9';

    // Stands in for Site.login: accepts GOOD_PASSWORD, refuses anything else, and records what it was given (Apex names
    // ignore case, so the constant must not be called PASSWORD next to a "password" parameter)
    private class FakeSiteLogin extends partnerPortalLoginController.SiteLogin {
        public String lockedFor;
        public String username;
        public String startUrl;

        public override PageReference login(String username, String password, String startUrl) {
            this.username = username;
            this.startUrl = startUrl;
            if (username == lockedFor) {
                throw new SecurityException('Your login is locked. Contact your administrator.');
            }
            if (password != GOOD_PASSWORD) {
                throw new SecurityException('Your login attempt has failed. Make sure the username and password are correct.');
            }
            return new PageReference('https://portal.example.com/secur/frontdoor.jsp?retURL=' + startUrl);
        }
    }

    private static FakeSiteLogin fakeSite() {
        FakeSiteLogin fake = new FakeSiteLogin();
        partnerPortalLoginController.sites = fake;
        return fake;
    }

    // The error shown to the user; a login that was not refused reports its status instead
    private static String errorOf(String username, String password) {
        try {
            return 'Not refused: ' + partnerPortalLoginController.login(username, password, '/PartnerPortal/').status;
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
    }

    @isTest
    static void logsAPartnerInWithTheirUsernameAndPassword() {
        User partner = PartnerPortalTestUser.create();
        partner = [SELECT Username FROM User WHERE Id = :partner.Id];
        FakeSiteLogin fake = fakeSite();

        Test.startTest();
        partnerPortalLoginController.LoginResult result = partnerPortalLoginController.login('  ' + partner.Username + ' ', GOOD_PASSWORD, '/PartnerPortal/');
        Test.stopTest();

        System.assertEquals(partnerPortalLoginController.LOGGED_IN, result.status);
        System.assert(result.url.contains('frontdoor.jsp') && EncodingUtil.urlDecode(result.url, 'UTF-8').contains('/PartnerPortal/'), result.url);
        System.assertEquals(partner.Username, fake.username, 'The username is trimmed before logging in');
    }

    @isTest
    static void acceptsThePartnersEmailInsteadOfTheirUsername() {
        User partner = PartnerPortalTestUser.create();
        partner = [SELECT Username, Email FROM User WHERE Id = :partner.Id];
        FakeSiteLogin fake = fakeSite();

        Test.startTest();
        partnerPortalLoginController.LoginResult result = partnerPortalLoginController.login(partner.Email, GOOD_PASSWORD, '/PartnerPortal/');
        Test.stopTest();

        System.assertEquals(partnerPortalLoginController.LOGGED_IN, result.status);
        System.assertEquals(partner.Username, fake.username, 'Salesforce is given the real username');
    }

    @isTest
    static void refusesAWrongPasswordAndExplainsALockedLogin() {
        User partner = PartnerPortalTestUser.create();
        partner = [SELECT Username FROM User WHERE Id = :partner.Id];
        FakeSiteLogin fake = fakeSite();

        Test.startTest();
        String wrongPassword = errorOf(partner.Username, 'not-it');
        fake.lockedFor = partner.Username;
        String locked = errorOf(partner.Username, GOOD_PASSWORD);
        Test.stopTest();

        System.assert(wrongPassword.contains('Incorrect username or password'), wrongPassword);
        System.assert(locked.contains('locked'), locked);
    }

    @isTest
    static void sendsUsernamesThatBelongToNoPartnerToSignUp() {
        fakeSite();
        User guest = [SELECT Id FROM User WHERE UserType = 'Guest' AND Profile.Name = 'Partner Portal Profile' AND IsActive = true LIMIT 1];
        partnerPortalLoginController.LoginResult result;

        Test.startTest();
        System.runAs(guest) {
            result = partnerPortalLoginController.login('new.partner@example.com', 'whatever', '/PartnerPortal/');
        }
        Test.stopTest();

        System.assertEquals(partnerPortalLoginController.NOT_REGISTERED, result.status, 'The login page runs as the site guest user');
        System.assertEquals(null, result.url);
    }

    // Executives are added by their channel partner: without a login yet they wait for the one JKP releases after
    // approving them, and are never sent to sign-up; the page stops offering registration once it knows them
    @isTest
    static void tellsAnExecutiveWithoutALoginToWaitForApproval() {
        Id partnerType = partnerPortalRegistrationController.partnerRecordTypeId();
        Account head = new Account(Name = 'Nazir Partner', RecordTypeId = partnerType);
        insert head;
        Account executive = new Account(Name = 'Amal Perera', Email__c = 'amal@executive.example.com', RecordTypeId = partnerType,
            Channel_Head__c = head.Id, Onboarding_Status__c = partnerPortalRegistrationController.registrationStatus());
        insert executive;
        insert new Contact(LastName = 'Perera', AccountId = executive.Id, Email = 'amal.contact@executive.example.com');
        fakeSite();

        Test.startTest();
        String byAccountEmail = partnerPortalLoginController.login('amal@executive.example.com', 'x', '/').status;
        String byContactEmail = partnerPortalLoginController.login('AMAL.CONTACT@executive.example.com', 'x', '/').status;
        Test.stopTest();

        System.assertEquals(partnerPortalLoginController.EXECUTIVE, byAccountEmail, 'Not Registration Under Review: they never registered');
        System.assertEquals(partnerPortalLoginController.EXECUTIVE, byContactEmail, 'Emails match in any case');
        System.assertEquals(true, partnerPortalLoginController.isExecutiveUsername(' amal@executive.example.com '));
        System.assertEquals(false, partnerPortalLoginController.isExecutiveUsername('someone@else.example.com'), 'Anyone else may register');
        System.assertEquals(false, partnerPortalLoginController.isExecutiveUsername('amal'), 'Not a username or email of theirs');
        System.assertEquals(false, partnerPortalLoginController.isExecutiveUsername(null));
    }

    // An executive JKP rejected is not waiting for a login any more: the page treats the email like any other, so the
    // person can be added again or register
    @isTest
    static void aRejectedExecutiveIsNotToldToWait() {
        Id partnerType = partnerPortalRegistrationController.partnerRecordTypeId();
        String rejected = partnerPortalRegistrationController.rejectedStatus();
        System.assertNotEquals(null, rejected, 'The Partner Registration Setting names the rejected status');
        Account head = new Account(Name = 'Nazir Partner', RecordTypeId = partnerType);
        insert head;
        Account executive = new Account(Name = 'Amal Perera', Email__c = 'amal@executive.example.com', RecordTypeId = partnerType,
            Channel_Head__c = head.Id, Onboarding_Status__c = rejected);
        insert executive;
        insert new Contact(LastName = 'Perera', AccountId = executive.Id, Email = 'amal.contact@executive.example.com');

        Test.startTest();
        Boolean byAccountEmail = partnerPortalLoginController.isExecutiveUsername('amal@executive.example.com');
        Boolean byContactEmail = partnerPortalLoginController.isExecutiveUsername('amal.contact@executive.example.com');
        Test.stopTest();

        System.assertEquals(false, byAccountEmail);
        System.assertEquals(false, byContactEmail);
    }

    @isTest
    static void executivesWithALoginLogInAsUsual() {
        User partner = PartnerPortalTestUser.create();
        partner = [SELECT Username, Contact.AccountId FROM User WHERE Id = :partner.Id];
        Account head = new Account(Name = 'Nazir Partner', RecordTypeId = partnerPortalRegistrationController.partnerRecordTypeId());
        insert head;
        update new Account(Id = partner.Contact.AccountId, Channel_Head__c = head.Id);
        fakeSite();

        Test.startTest();
        partnerPortalLoginController.LoginResult result = partnerPortalLoginController.login(partner.Username, GOOD_PASSWORD, '/PartnerPortal/');
        Test.stopTest();

        System.assertEquals(partnerPortalLoginController.LOGGED_IN, result.status);
        System.assertEquals(true, partnerPortalLoginController.isExecutiveUsername(partner.Username), 'The page hides Register here for them');
    }

    @isTest
    static void showsUnderReviewForARegistrationWaitingForApproval() {
        String pending = partnerPortalRegistrationController.registrationStatus();
        Id partnerType = partnerPortalRegistrationController.partnerRecordTypeId();
        Account company = new Account(Name = 'Harbour Realty', Email__c = 'hello@harbour-realty.example.com', Onboarding_Status__c = pending,
            RecordTypeId = partnerType);
        Account person = new Account(Name = 'Perera Homes', Onboarding_Status__c = pending, RecordTypeId = partnerType);
        insert new List<Account>{ company, person };
        insert new Contact(LastName = 'Perera', AccountId = person.Id, Email = 'perera@example.com');
        fakeSite();

        Test.startTest();
        String byAccountEmail = partnerPortalLoginController.login('hello@harbour-realty.example.com', 'x', '/').status;
        String byContactEmail = partnerPortalLoginController.login('PERERA@example.com', 'x', '/').status;
        Test.stopTest();

        System.assertEquals(partnerPortalLoginController.UNDER_REVIEW, byAccountEmail);
        System.assertEquals(partnerPortalLoginController.UNDER_REVIEW, byContactEmail, 'Emails match in any case');
    }

    @isTest
    static void onlyChannelPartnerRegistrationsAreUnderReview() {
        String pending = partnerPortalRegistrationController.registrationStatus();
        Id customerType;
        for (Schema.RecordTypeInfo info : Schema.SObjectType.Account.getRecordTypeInfos()) {
            if (info.isActive() && !info.isMaster() && info.getRecordTypeId() != partnerPortalRegistrationController.partnerRecordTypeId()) {
                customerType = info.getRecordTypeId();
            }
        }
        System.assertNotEquals(null, customerType, 'The org has a second Account record type (Customer) to compare with');
        Account customer = new Account(Name = 'Pending Customer', Email__c = 'customer@harbour-realty.example.com',
            Onboarding_Status__c = pending, RecordTypeId = customerType);
        insert customer;
        insert new Contact(LastName = 'Silva', AccountId = customer.Id, Email = 'silva@harbour-realty.example.com');
        fakeSite();

        Test.startTest();
        String byAccountEmail = partnerPortalLoginController.login('customer@harbour-realty.example.com', 'x', '/').status;
        String byContactEmail = partnerPortalLoginController.login('silva@harbour-realty.example.com', 'x', '/').status;
        Test.stopTest();

        System.assertEquals(partnerPortalLoginController.NOT_REGISTERED, byAccountEmail, 'A customer account is not a partner registration');
        System.assertEquals(partnerPortalLoginController.NOT_REGISTERED, byContactEmail);
    }

    @isTest
    static void showsAccessRestrictedForADeactivatedPartner() {
        User partner = PartnerPortalTestUser.create();
        partner = [SELECT Username FROM User WHERE Id = :partner.Id];
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = partner.Id, IsActive = false);
        }
        FakeSiteLogin fake = fakeSite();

        Test.startTest();
        partnerPortalLoginController.LoginResult result = partnerPortalLoginController.login(partner.Username, GOOD_PASSWORD, '/PartnerPortal/');
        Test.stopTest();

        System.assertEquals(partnerPortalLoginController.RESTRICTED, result.status);
        System.assertEquals(null, fake.username, 'No login is attempted');
    }

    @isTest
    static void refusesAPartnerWhoseAccountIsNotAChannelPartner() {
        Id customerType;
        for (Schema.RecordTypeInfo info : Schema.SObjectType.Account.getRecordTypeInfos()) {
            if (info.isActive() && !info.isMaster() && info.getRecordTypeId() != partnerPortalRegistrationController.partnerRecordTypeId()) {
                customerType = info.getRecordTypeId();
            }
        }
        System.assertNotEquals(null, customerType, 'The org has a second Account record type (Customer) to compare with');
        // Created on a customer account from the start: updating an account would start the org's approval flow
        User partner = PartnerPortalTestUser.create(customerType);
        partner = [SELECT Username FROM User WHERE Id = :partner.Id];
        FakeSiteLogin fake = fakeSite();

        Test.startTest();
        String error = errorOf(partner.Username, GOOD_PASSWORD);
        Test.stopTest();

        System.assertEquals('This login does not belong to a channel partner account. Please contact the JKP CP team.', error);
        System.assertEquals(null, fake.username, 'No login is attempted');
    }

    @isTest
    static void refusesEveryLoginWhenNoChannelPartnerTypeIsSetUp() {
        User partner = PartnerPortalTestUser.create();
        partner = [SELECT Username FROM User WHERE Id = :partner.Id];
        partnerPortalRegistrationController.setting = (Partner_Registration_Setting__mdt) JSON.deserialize(
            JSON.serialize(new Map<String, Object>{ 'DeveloperName' => 'Default', 'Account_Record_Type__c' => null }),
            Partner_Registration_Setting__mdt.class
        );
        FakeSiteLogin fake = fakeSite();

        Test.startTest();
        String error = errorOf(partner.Username, GOOD_PASSWORD);
        Test.stopTest();

        System.assertEquals('The portal login is not available right now. Please contact the JKP CP team.', error);
        System.assertEquals(null, fake.username, 'No login is attempted');
    }

    @isTest
    static void neverRedirectsOffTheSite() {
        User partner = PartnerPortalTestUser.create();
        partner = [SELECT Username FROM User WHERE Id = :partner.Id];
        FakeSiteLogin fake = fakeSite();

        Test.startTest();
        partnerPortalLoginController.login(partner.Username, GOOD_PASSWORD, 'https://evil.example.com/');
        String external = fake.startUrl;
        partnerPortalLoginController.login(partner.Username, GOOD_PASSWORD, '//evil.example.com');
        String protocolRelative = fake.startUrl;
        Test.stopTest();

        System.assertEquals('/', external);
        System.assertEquals('/', protocolRelative);
        System.assertEquals('/PartnerPortal/leads', partnerPortalLoginController.safeStartUrl('/PartnerPortal/leads'));
    }

    @isTest
    static void requiresAUsernameAndPassword() {
        fakeSite();
        System.assertEquals('Enter your username and password.', errorOf('', GOOD_PASSWORD));
        System.assertEquals('Enter your username and password.', errorOf('someone@example.com', ''));
        System.assertEquals('Enter your username and password.', errorOf(null, null));
    }

    // ---------- temporary access (PartnerTemporaryAccess) ----------

    // Answers the SharePoint calls of the records these tests create (project and account folders) with a refusal
    private class SharePointRefusal implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(503);
            res.setBody('{"error":{"code":"serviceNotAvailable"}}');
            return res;
        }
    }

    // The refusal, with a test token and library (no sign-in, no site lookup)
    private static void useSharePointRefusal() {
        SharePointService.testDriveId = 'test-drive';
        Test.setMock(HttpCalloutMock.class, new SharePointRefusal());
    }

    private static Integer leadCount = 0;

    // The rules of these tests: 1 conversion or 3 completed visits
    private static void useRules() {
        PartnerTemporaryAccess.setting = (Partner_Portal_Setting__mdt) JSON.deserialize(JSON.serialize(new Map<String, Object>{
            'DeveloperName' => 'Default',
            'Exclusive_Converted_Leads__c' => 1,
            'Exclusive_Site_Visits__c' => 3,
            'Completed_Visit_Status__c' => 'Completed'
        }), Partner_Portal_Setting__mdt.class);
    }

    private static User siteGuest() {
        return [SELECT Id FROM User WHERE UserType = 'Guest' AND Profile.Name = 'Partner Portal Profile' AND IsActive = true LIMIT 1];
    }

    // The partner's account on temporary access from today + startDays to today + endDays
    private static Account onTemporaryAccess(User partner, Integer startDays, Integer endDays) {
        Id accountId = [SELECT Contact.AccountId FROM User WHERE Id = :partner.Id].Contact.AccountId;
        update new Account(Id = accountId, Partner_Type__c = 'Temporary', Temporary_Access_Start_Date__c = Date.today().addDays(startDays),
            Temporary_Access_End_Date__c = Date.today().addDays(endDays));
        return [SELECT Id, Partner_Type__c, Temporary_Access_Start_Date__c, Temporary_Access_End_Date__c, Channel_Head__c FROM Account WHERE Id = :accountId];
    }

    // Leads of the account created the given number of days ago, each with a completed site visit dated visitDaysAgo
    private static List<Lead> visitedLeads(Id accountId, Integer howMany, Integer createdDaysAgo, Integer visitDaysAgo) {
        useSharePointRefusal();
        Project__c project = TestRecordDefaults.project('Temporary Access Test Project ' + leadCount, true);
        insert project;
        List<Lead> leads = new List<Lead>();
        for (Integer i = 0; i < howMany; i++) {
            leadCount++;
            leads.add(new Lead(LastName = 'Visitor ' + leadCount, Company = 'Visitor ' + leadCount, Email = 'visitor' + leadCount + '@temporary-access.example.com',
                Phone = '07712300' + String.valueOf(leadCount).leftPad(2, '0'), LeadSource = 'Channel Partner', Channel_Partner__c = accountId,
                Budget_Aligned__c = 'Matching Budget', Project__c = project.Id, Status = 'New'));
        }
        insert leads;
        List<Visit__c> visits = new List<Visit__c>();
        for (Lead record : leads) {
            Test.setCreatedDate(record.Id, Datetime.now().addDays(-createdDaysAgo));
            visits.add(new Visit__c(Lead__c = record.Id, Status__c = 'Completed', Visit_Date__c = Date.today().addDays(-visitDaysAgo)));
        }
        insert visits;
        return leads;
    }

    // After the end date, a temporary partner without a converted lead or 3 completed site visits on leads created in
    // the access period may not log in; visits on leads created before it do not count
    @isTest
    static void refusesATemporaryPartnerWhoseAccessEndedWithoutMeetingItsConditions() {
        useRules();
        User partner = PartnerPortalTestUser.create();
        partner = [SELECT Username FROM User WHERE Id = :partner.Id];
        Account account = onTemporaryAccess(partner, -40, -10);
        visitedLeads(account.Id, 3, 45, 20);
        FakeSiteLogin fake = fakeSite();

        Test.startTest();
        partnerPortalLoginController.LoginResult result;
        System.runAs(siteGuest()) {
            result = partnerPortalLoginController.login(partner.Username, GOOD_PASSWORD, '/PartnerPortal/');
        }
        Test.stopTest();

        System.assertEquals(partnerPortalLoginController.ACCESS_DENIED, result.status);
        System.assertEquals(null, fake.username, 'No login is attempted');
    }

    // The end date is the last day of the access: the partner logs in on it and is refused from the day after (days of the
    // org's time zone). Access Denied is all the answer says: the login page offers no extension of the access.
    @isTest
    static void refusesAPartnerFromTheDayAfterTheEndDate() {
        useRules();
        User partner = PartnerPortalTestUser.create();
        partner = [SELECT Username, Contact.AccountId FROM User WHERE Id = :partner.Id];
        Date today = PartnerTemporaryAccess.today();
        update new Account(Id = partner.Contact.AccountId, Partner_Type__c = 'Temporary', Temporary_Access_Start_Date__c = today.addDays(-30),
            Temporary_Access_End_Date__c = today);
        FakeSiteLogin fake = fakeSite();

        Test.startTest();
        partnerPortalLoginController.LoginResult onTheEndDate;
        partnerPortalLoginController.LoginResult dayAfter;
        System.runAs(siteGuest()) {
            onTheEndDate = partnerPortalLoginController.login(partner.Username, GOOD_PASSWORD, '/PartnerPortal/');
        }
        update new Account(Id = partner.Contact.AccountId, Temporary_Access_Start_Date__c = today.addDays(-31),
            Temporary_Access_End_Date__c = today.addDays(-1));
        fake.username = null;
        System.runAs(siteGuest()) {
            dayAfter = partnerPortalLoginController.login(partner.Username, GOOD_PASSWORD, '/PartnerPortal/');
        }
        Test.stopTest();

        System.assertEquals(partnerPortalLoginController.LOGGED_IN, onTheEndDate.status, 'The end date is still part of the access');
        System.assertEquals(partnerPortalLoginController.ACCESS_DENIED, dayAfter.status);
        System.assertEquals(null, fake.username, 'No login is attempted');
        System.assertEquals(new Set<String>{ 'status', 'url' },
            ((Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(dayAfter))).keySet(),
            'Nothing is offered with Access Denied, such as an extension request');
    }

    // The executives of a channel head lose the portal on the same day as their head
    @isTest
    static void refusesAnExecutiveFromTheDayAfterTheirHeadsEndDate() {
        useRules();
        User partner = PartnerPortalTestUser.createExecutive(new List<Id>());
        partner = [SELECT Username, Contact.Account.Channel_Head__c FROM User WHERE Id = :partner.Id];
        Id headId = partner.Contact.Account.Channel_Head__c;
        Date today = PartnerTemporaryAccess.today();
        update new Account(Id = headId, Partner_Type__c = 'Temporary', Temporary_Access_Start_Date__c = today.addDays(-30),
            Temporary_Access_End_Date__c = today);
        fakeSite();

        Test.startTest();
        String onTheEndDate = partnerPortalLoginController.login(partner.Username, GOOD_PASSWORD, '/PartnerPortal/').status;
        update new Account(Id = headId, Temporary_Access_Start_Date__c = today.addDays(-31), Temporary_Access_End_Date__c = today.addDays(-1));
        String dayAfter = partnerPortalLoginController.login(partner.Username, GOOD_PASSWORD, '/PartnerPortal/').status;
        Test.stopTest();

        System.assertEquals(partnerPortalLoginController.LOGGED_IN, onTheEndDate);
        System.assertEquals(partnerPortalLoginController.ACCESS_DENIED, dayAfter);
    }

    // Three completed site visits, on leads created in the access period, keep the partner's login after it ends
    @isTest
    static void aTemporaryPartnerWhoMetTheConditionsKeepsLoggingIn() {
        useRules();
        User partner = PartnerPortalTestUser.create();
        partner = [SELECT Username FROM User WHERE Id = :partner.Id];
        Account account = onTemporaryAccess(partner, -40, -10);
        visitedLeads(account.Id, 3, 35, 20);
        fakeSite();

        Test.startTest();
        partnerPortalLoginController.LoginResult result = partnerPortalLoginController.login(partner.Username, GOOD_PASSWORD, '/PartnerPortal/');
        Test.stopTest();

        System.assertEquals(partnerPortalLoginController.LOGGED_IN, result.status);
    }

    // During the temporary access the partner logs in as usual
    @isTest
    static void aTemporaryPartnerLogsInWhileTheAccessLasts() {
        useRules();
        User partner = PartnerPortalTestUser.create();
        partner = [SELECT Username FROM User WHERE Id = :partner.Id];
        onTemporaryAccess(partner, -5, 25);
        fakeSite();

        Test.startTest();
        partnerPortalLoginController.LoginResult result = partnerPortalLoginController.login(partner.Username, GOOD_PASSWORD, '/PartnerPortal/');
        Test.stopTest();

        System.assertEquals(partnerPortalLoginController.LOGGED_IN, result.status);
    }

    // An account marked Access Denied (the nightly check) is refused, also once its login is deactivated
    @isTest
    static void showsAccessDeniedForAnAccountMarkedAccessDenied() {
        useRules();
        User partner = PartnerPortalTestUser.create();
        partner = [SELECT Username, Contact.AccountId FROM User WHERE Id = :partner.Id];
        update new Account(Id = partner.Contact.AccountId, Partner_Type__c = 'Access Denied');
        FakeSiteLogin fake = fakeSite();

        Test.startTest();
        String whileActive = partnerPortalLoginController.login(partner.Username, GOOD_PASSWORD, '/PartnerPortal/').status;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = partner.Id, IsActive = false);
        }
        String onceDeactivated = partnerPortalLoginController.login(partner.Username, GOOD_PASSWORD, '/PartnerPortal/').status;
        Test.stopTest();

        System.assertEquals(partnerPortalLoginController.ACCESS_DENIED, whileActive);
        System.assertEquals(partnerPortalLoginController.ACCESS_DENIED, onceDeactivated);
        System.assertEquals(null, fake.username, 'No login is attempted');
    }

    // A lead converted in the access period meets the conditions; before that, nothing does
    @isTest
    static void aConvertedLeadInTheAccessPeriodMeetsTheConditions() {
        useRules();
        User partner = PartnerPortalTestUser.create();
        Account account = onTemporaryAccess(partner, -29, 1);
        Lead customer = visitedLeads(account.Id, 1, 2, 1)[0];
        Boolean beforeConversion = PartnerTemporaryAccess.metConditions(account);

        Test.startTest();
        Database.LeadConvert conversion = new Database.LeadConvert();
        conversion.setLeadId(customer.Id);
        conversion.setConvertedStatus([SELECT MasterLabel FROM LeadStatus WHERE IsConverted = true LIMIT 1].MasterLabel);
        Database.convertLead(conversion);
        Boolean afterConversion = PartnerTemporaryAccess.metConditions(account);
        Test.stopTest();

        System.assertEquals(false, beforeConversion, 'One completed visit is not enough');
        System.assertEquals(true, afterConversion);
        System.assertEquals(false, PartnerTemporaryAccess.isDenied(account), 'The access has not ended yet');
    }

    // A disabled partner user has no contact any more: it is not taken for an Access Denied account (and does not break
    // the login), while a deactivated user on an Access Denied account is
    @isTest
    static void readsTheAccountOfDeactivatedLoginsSafely() {
        User disabled = new User();
        User denied = new User();
        Contact deniedContact = new Contact();
        deniedContact.putSObject('Account', new Account(Partner_Type__c = 'Access Denied'));
        denied.putSObject('Contact', deniedContact);
        User restricted = new User();
        Contact restrictedContact = new Contact();
        restrictedContact.putSObject('Account', new Account(Partner_Type__c = 'Temporary'));
        restricted.putSObject('Contact', restrictedContact);

        System.assertEquals(false, partnerPortalLoginController.anyAccessDenied(new List<User>{ disabled }));
        System.assertEquals(false, partnerPortalLoginController.anyAccessDenied(new List<User>{ disabled, restricted }));
        System.assertEquals(true, partnerPortalLoginController.anyAccessDenied(new List<User>{ disabled, denied }));
    }

    // An executive goes by their channel head: in while the head is Exclusive (whatever the executive's own dates), out
    // once the head's temporary access has ended without its conditions met
    @isTest
    static void anExecutiveGoesByTheirChannelHead() {
        useRules();
        User partner = PartnerPortalTestUser.createExecutive(new List<Id>());
        partner = [SELECT Username, Contact.AccountId, Contact.Account.Channel_Head__c FROM User WHERE Id = :partner.Id];
        Id headId = partner.Contact.Account.Channel_Head__c;
        update new List<Account>{
            new Account(Id = partner.Contact.AccountId, Partner_Type__c = 'Temporary', Temporary_Access_Start_Date__c = Date.today().addDays(-60),
                Temporary_Access_End_Date__c = Date.today().addDays(-30)),
            new Account(Id = headId, Partner_Type__c = 'Exclusive')
        };
        fakeSite();

        Test.startTest();
        String underExclusiveHead = partnerPortalLoginController.login(partner.Username, GOOD_PASSWORD, '/PartnerPortal/').status;
        update new Account(Id = headId, Partner_Type__c = 'Temporary', Temporary_Access_Start_Date__c = Date.today().addDays(-40),
            Temporary_Access_End_Date__c = Date.today().addDays(-10));
        String underEndedHead = partnerPortalLoginController.login(partner.Username, GOOD_PASSWORD, '/PartnerPortal/').status;
        Test.stopTest();

        System.assertEquals(partnerPortalLoginController.LOGGED_IN, underExclusiveHead);
        System.assertEquals(partnerPortalLoginController.ACCESS_DENIED, underEndedHead);
    }

    // The reason the site's guest user is given for this login, with the session key the login's own portal holds
    private static String reasonFor(Id userId) {
        String key = partnerPortalLoginController.sessionKeyOf(userId);
        partnerPortalLoginController.SessionState state;
        System.runAs(siteGuest()) {
            state = partnerPortalLoginController.sessionState(userId, key);
        }
        System.assertEquals(true, state.sessionEnded, 'The guest user has no partner session');
        return state.reason;
    }

    // The portal's shell asks why a session that was open is over. A partner whose login was switched off is the site's
    // guest user from then on, and is told why: terminated, access ended, login switched off, or merely logged out.
    @isTest
    static void tellsThePortalWhyAPartnersSessionIsOver() {
        User partner = PartnerPortalTestUser.create();
        Id accountId = [SELECT Contact.AccountId FROM User WHERE Id = :partner.Id].Contact.AccountId;
        update new Account(Id = accountId, Partner_Type__c = 'Exclusive');
        Map<String, String> reasons = new Map<String, String>();

        Test.startTest();
        reasons.put('logged out', reasonFor(partner.Id));
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = partner.Id, IsActive = false);
        }
        reasons.put('switched off', reasonFor(partner.Id));
        update new Account(Id = accountId, Partner_Type__c = 'Access Denied');
        reasons.put('Access Denied', reasonFor(partner.Id));
        update new Account(Id = accountId, Partner_Type__c = 'Terminated');
        reasons.put('Terminated', reasonFor(partner.Id));
        Test.stopTest();

        System.assertEquals(partnerPortalLoginController.SIGNED_OUT, reasons.get('logged out'), 'The login is fine: only the session is over');
        System.assertEquals(partnerPortalLoginController.INACTIVE, reasons.get('switched off'));
        System.assertEquals(partnerPortalLoginController.ACCESS_DENIED, reasons.get('Access Denied'));
        System.assertEquals(partnerPortalLoginController.TERMINATED, reasons.get('Terminated'));
    }

    // An executive is told of a termination when their own account or their channel head's is terminated
    @isTest
    static void tellsAnExecutiveOfTheirChannelHeadsTermination() {
        User executive = PartnerPortalTestUser.createExecutive(new List<Id>());
        Account own = [SELECT Contact.Account.Id, Contact.Account.Channel_Head__c FROM User WHERE Id = :executive.Id].Contact.Account;
        update new Account(Id = own.Channel_Head__c, Partner_Type__c = 'Exclusive');

        Test.startTest();
        String withAccess = reasonFor(executive.Id);
        update new Account(Id = own.Id, Partner_Type__c = 'Terminated');
        String ownTermination = reasonFor(executive.Id);
        update new List<Account>{ new Account(Id = own.Id, Partner_Type__c = null), new Account(Id = own.Channel_Head__c, Partner_Type__c = 'Terminated') };
        String headsTermination = reasonFor(executive.Id);
        Test.stopTest();

        System.assertEquals(partnerPortalLoginController.SIGNED_OUT, withAccess);
        System.assertEquals(partnerPortalLoginController.TERMINATED, ownTermination);
        System.assertEquals(partnerPortalLoginController.TERMINATED, headsTermination);
    }

    // Only the guest user is answered, and only about partner logins: a partner who is still logged in learns nothing
    // (their portal stays as it is), and an id that is no partner login gets no reason
    @isTest
    static void tellsOnlyTheGuestUserAndOnlyAboutPartnerLogins() {
        User partner = PartnerPortalTestUser.create();
        Id accountId = [SELECT Contact.AccountId FROM User WHERE Id = :partner.Id].Contact.AccountId;
        update new Account(Id = accountId, Partner_Type__c = 'Terminated');

        String key = partnerPortalLoginController.sessionKeyOf(partner.Id);
        String shortId = String.valueOf(partner.Id).left(15);

        Test.startTest();
        partnerPortalLoginController.SessionState loggedIn;
        System.runAs(partner) {
            loggedIn = partnerPortalLoginController.sessionState(partner.Id, key);
        }
        partnerPortalLoginController.SessionState internalCaller = partnerPortalLoginController.sessionState(partner.Id, key);
        String internalUser = reasonFor(UserInfo.getUserId());
        String account = reasonFor(accountId);
        Map<String, partnerPortalLoginController.SessionState> asGuest = new Map<String, partnerPortalLoginController.SessionState>();
        System.runAs(siteGuest()) {
            asGuest.put('with the key', partnerPortalLoginController.sessionState(partner.Id, key));
            asGuest.put('15 characters', partnerPortalLoginController.sessionState(shortId, key));
            asGuest.put('no key', partnerPortalLoginController.sessionState(partner.Id, null));
            asGuest.put('wrong key', partnerPortalLoginController.sessionState(partner.Id, key.reverse()));
            asGuest.put('no id', partnerPortalLoginController.sessionState(null, key));
            asGuest.put('not an id', partnerPortalLoginController.sessionState('not an id', key));
        }
        Test.stopTest();

        System.assertEquals(false, loggedIn.sessionEnded, 'A logged-in partner still has a session');
        System.assertEquals(null, loggedIn.reason);
        System.assertEquals(false, internalCaller.sessionEnded, 'An internal user is no guest');
        System.assertEquals(null, internalCaller.reason);
        System.assertEquals(null, internalUser, 'Not a partner login');
        System.assertEquals(null, account, 'Not a user');
        System.assertEquals(partnerPortalLoginController.TERMINATED, asGuest.get('with the key').reason);
        System.assertEquals(partnerPortalLoginController.TERMINATED, asGuest.get('15 characters').reason, 'The same login, by its short id');
        for (String without : new List<String>{ 'no key', 'wrong key', 'no id', 'not an id' }) {
            System.assertEquals(true, asGuest.get(without).sessionEnded, without);
            System.assertEquals(null, asGuest.get(without).reason, 'A user id alone tells a stranger nothing: ' + without);
        }
        System.assertNotEquals(key, partnerPortalLoginController.sessionKeyOf(UserInfo.getUserId()), 'Every login has its own key');
        System.assertEquals(null, partnerPortalLoginController.sessionKeyOf(accountId), 'No key for what is no user');
    }

    // A temporary access that ended without its conditions met is Access Denied for the channel head and for their
    // executive, worked out as the guest user; a frozen login is switched off, not merely logged out
    @isTest
    static void tellsOfAnAccessThatEndedAndOfAFrozenLogin() {
        useRules();
        User executive = PartnerPortalTestUser.createExecutive(new List<Id>());
        Id headId = [SELECT Contact.Account.Channel_Head__c FROM User WHERE Id = :executive.Id].Contact.Account.Channel_Head__c;
        Date today = PartnerTemporaryAccess.today();
        update new Account(Id = headId, Partner_Type__c = 'Temporary', Temporary_Access_Start_Date__c = today.addDays(-10),
            Temporary_Access_End_Date__c = today.addDays(20));

        Test.startTest();
        String whileItLasts = reasonFor(executive.Id);
        update new Account(Id = headId, Temporary_Access_Start_Date__c = today.addDays(-31), Temporary_Access_End_Date__c = today.addDays(-1));
        String afterItEnded = reasonFor(executive.Id);
        update new Account(Id = headId, Partner_Type__c = 'Exclusive');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            UserLogin login = [SELECT Id, IsFrozen FROM UserLogin WHERE UserId = :executive.Id];
            login.IsFrozen = true;
            update login;
        }
        String frozen = reasonFor(executive.Id);
        Test.stopTest();

        System.assertEquals(partnerPortalLoginController.SIGNED_OUT, whileItLasts);
        System.assertEquals(partnerPortalLoginController.ACCESS_DENIED, afterItEnded, 'The channel head\'s access ended without its conditions met');
        System.assertEquals(partnerPortalLoginController.INACTIVE, frozen);
    }

    // A Terminated partner is told their access was revoked
    @isTest
    static void aTerminatedPartnerGetsAccessRestricted() {
        User partner = PartnerPortalTestUser.create();
        partner = [SELECT Username, Contact.AccountId FROM User WHERE Id = :partner.Id];
        update new Account(Id = partner.Contact.AccountId, Partner_Type__c = 'Terminated');
        FakeSiteLogin fake = fakeSite();

        Test.startTest();
        partnerPortalLoginController.LoginResult result = partnerPortalLoginController.login(partner.Username, GOOD_PASSWORD, '/PartnerPortal/');
        Test.stopTest();

        System.assertEquals(partnerPortalLoginController.RESTRICTED, result.status);
        System.assertEquals(null, fake.username, 'No login is attempted');
    }

    // A partner without access sees no records on any portal page, however they got in
    @isTest
    static void aDeniedPartnerSeesNoPortalData() {
        useRules();
        User partner = PartnerPortalTestUser.create();
        Id accountId = [SELECT Contact.AccountId FROM User WHERE Id = :partner.Id].Contact.AccountId;
        update new Account(Id = accountId, Partner_Type__c = 'Access Denied');

        PartnerPortalAccess access;
        Map<String, Object> binds = new Map<String, Object>();
        Test.startTest();
        System.runAs(partner) {
            access = PartnerPortalAccess.current();
        }
        Test.stopTest();

        System.assertEquals(null, access.accountId);
        System.assertEquals('Id = null', access.leads(binds));
        System.assertEquals('Id = null', access.visits(binds));
    }

    // A visit counts when it was completed in the access period, even if it was planned for a later date
    @isTest
    static void aVisitCompletedInThePeriodCountsWhateverItsPlannedDate() {
        useRules();
        User partner = PartnerPortalTestUser.create();
        partner = [SELECT Username FROM User WHERE Id = :partner.Id];
        Account account = onTemporaryAccess(partner, -40, -10);
        List<Lead> leads = visitedLeads(account.Id, 3, 35, 20);
        List<Visit__c> visits = [SELECT Id FROM Visit__c WHERE Lead__c IN :leads];
        for (Visit__c visit : visits) {
            visit.Visit_Date__c = Date.today().addDays(5);
            visit.Completed_At_Date_Time__c = Datetime.now().addDays(-20);
        }
        update visits;
        fakeSite();

        Test.startTest();
        partnerPortalLoginController.LoginResult result = partnerPortalLoginController.login(partner.Username, GOOD_PASSWORD, '/PartnerPortal/');
        Test.stopTest();

        System.assertEquals(partnerPortalLoginController.LOGGED_IN, result.status);
    }
}