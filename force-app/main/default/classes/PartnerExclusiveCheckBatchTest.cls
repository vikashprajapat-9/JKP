// The nightly check of partners on temporary access (PartnerExclusiveCheckBatch, with PartnerTemporaryAccess and
// PartnerContractService)
@isTest
private class PartnerExclusiveCheckBatchTest {

    // Answers the OneDrive calls of the records the test creates (project folders) with a refusal
    private class OneDriveRefusal implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(503);
            res.setBody('{"error":{"code":"serviceNotAvailable"}}');
            return res;
        }
    }

    // The rules of these tests: 1 conversion or 3 completed visits, denied 2 days after the end; the contract templates
    private static void useSettings() {
        PartnerTemporaryAccess.setting = (Partner_Portal_Setting__mdt) JSON.deserialize(JSON.serialize(new Map<String, Object>{
            'DeveloperName' => 'Default',
            'Exclusive_Converted_Leads__c' => 1,
            'Exclusive_Site_Visits__c' => 3,
            'Completed_Visit_Status__c' => 'Completed',
            'Denial_Grace_Days__c' => 2
        }), Partner_Portal_Setting__mdt.class);
        PartnerContractService.setting = (Partner_Portal_Setting__mdt) JSON.deserialize(JSON.serialize(new Map<String, Object>{
            'DeveloperName' => 'Default',
            'Contract_Template__c' => 'Partner_Agent_Contract',
            'Contract_Ready_Email_Template__c' => 'Partner_Contract_Ready',
            'Contract_Term_Months__c' => 12
        }), Partner_Portal_Setting__mdt.class);
    }

    private static Account temporaryPartner(String name, Integer startDays, Integer endDays) {
        return new Account(Name = name, RecordTypeId = partnerPortalRegistrationController.partnerRecordTypeId(), Document_Id__c = 'test-folder',
            Partner_Type__c = 'Temporary', Temporary_Access_Start_Date__c = Date.today().addDays(startDays),
            Temporary_Access_End_Date__c = Date.today().addDays(endDays));
    }

    // A channel head that met the conditions gets its contract drafted (and stays Temporary until it is signed); one whose
    // access ended more than the grace days ago becomes Access Denied, one that ended within them is left; one with a
    // signed contract becomes Exclusive; one still in its period, and executives (judged with their head), are left
    @isTest
    static void draftsDeniesPromotesAndLeavesPartnersByTheirActivity() {
        useSettings();
        Test.setMock(HttpCalloutMock.class, new OneDriveRefusal());
        Account busy = temporaryPartner('Busy Partner', -40, -10);
        Account idle = temporaryPartner('Idle Partner', -40, -10);
        Account justEnded = temporaryPartner('Just Ended Partner', -31, -1);
        Account fresh = temporaryPartner('Fresh Partner', -5, 25);
        Account signed = temporaryPartner('Signed Partner', -20, 10);
        insert new List<Account>{ busy, idle, justEnded, fresh, signed };
        Account executive = temporaryPartner('Executive of Fresh', -40, -10);
        executive.Channel_Head__c = fresh.Id;
        insert executive;
        insert new List<Contact>{
            new Contact(AccountId = busy.Id, LastName = 'Busy Contact', Email = 'busy@exclusive-check.example.com'),
            new Contact(AccountId = signed.Id, LastName = 'Signed Contact', Email = 'signed@exclusive-check.example.com')
        };
        insert new Contract(AccountId = signed.Id, Status = 'Draft', Contract_Stage__c = 'Signed', Signed_On__c = Date.today());
        Project__c project = TestRecordDefaults.project('Exclusive Check Test Project', true);
        insert project;
        List<Lead> leads = new List<Lead>();
        for (Integer i = 0; i < 3; i++) {
            leads.add(new Lead(LastName = 'Buyer ' + i, Company = 'Buyer ' + i, Email = 'buyer' + i + '@exclusive-check.example.com',
                Phone = '077456780' + i, LeadSource = 'Channel Partner', Channel_Partner__c = busy.Id, Budget_Aligned__c = 'Matching Budget',
                Project__c = project.Id, Status = 'New'));
        }
        insert leads;
        List<Visit__c> visits = new List<Visit__c>();
        for (Lead record : leads) {
            Test.setCreatedDate(record.Id, Datetime.now().addDays(-35));
            visits.add(new Visit__c(Lead__c = record.Id, Status__c = 'Completed', Visit_Date__c = Date.today().addDays(-20)));
        }
        insert visits;

        Test.startTest();
        Database.executeBatch(new PartnerExclusiveCheckBatch(), 20);
        Test.stopTest();

        Map<Id, Account> after = new Map<Id, Account>([SELECT Partner_Type__c FROM Account]);
        System.assertEquals('Temporary', after.get(busy.Id).Partner_Type__c, 'Exclusive only once the contract is signed');
        List<Contract> busyContracts = [SELECT Contract_Stage__c, Draft_Document_Id__c FROM Contract WHERE AccountId = :busy.Id];
        System.assertEquals(1, busyContracts.size(), 'Its contract is drafted');
        System.assertEquals('Draft', busyContracts[0].Contract_Stage__c);
        System.assertEquals(null, busyContracts[0].Draft_Document_Id__c,
            'Its PDF goes to OneDrive once the batch finishes (ContractDocumentService), not to Salesforce Files');
        System.assertEquals('Access Denied', after.get(idle.Id).Partner_Type__c, 'Ended without activity');
        System.assertEquals('Temporary', after.get(justEnded.Id).Partner_Type__c, 'Within the grace days');
        System.assertEquals('Temporary', after.get(fresh.Id).Partner_Type__c, 'Still in its access period');
        System.assertEquals('Exclusive', after.get(signed.Id).Partner_Type__c, 'Its contract is signed');
        System.assertEquals('Temporary', after.get(executive.Id).Partner_Type__c, 'Executives go by their channel head');
        System.assertEquals(0, [SELECT COUNT() FROM Contract WHERE AccountId IN (:idle.Id, :fresh.Id, :executive.Id)]);
    }

    // The portal users of an Access Denied partner, and of its executives, are deactivated
    @isTest
    static void deactivatesThePortalUsersOfADeniedPartner() {
        useSettings();
        User partner = PartnerPortalTestUser.create();
        Id accountId = [SELECT Contact.AccountId FROM User WHERE Id = :partner.Id].Contact.AccountId;
        update new Account(Id = accountId, Partner_Type__c = 'Temporary', Temporary_Access_Start_Date__c = Date.today().addDays(-40),
            Temporary_Access_End_Date__c = Date.today().addDays(-10));

        Test.startTest();
        Database.executeBatch(new PartnerExclusiveCheckBatch(), 20);
        Test.stopTest();

        System.assertEquals('Access Denied', [SELECT Partner_Type__c FROM Account WHERE Id = :accountId].Partner_Type__c);
        System.assertEquals(1, deactivationJobs(), 'Its users are deactivated');
    }

    private static Integer deactivationJobs() {
        return [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'Queueable' AND ApexClass.Name = 'PartnerUserActivationQueueable'];
    }

    // The logins switched off with a partner are its own and those of the executives under it; closing an executive
    // alone leaves the channel head's login
    @isTest
    static void theLoginsOfAPartnerAndOfItsExecutivesAreChosen() {
        User head = PartnerPortalTestUser.create();
        Id headAccountId = [SELECT Contact.AccountId FROM User WHERE Id = :head.Id].Contact.AccountId;
        User executive = PartnerPortalTestUser.createExecutiveOf(headAccountId);
        Id executiveAccountId = [SELECT Contact.AccountId FROM User WHERE Id = :executive.Id].Contact.AccountId;

        Test.startTest();
        Set<Id> withTheHead = PartnerExclusiveCheckBatch.activeUsersOf(new Set<Id>{ headAccountId });
        Set<Id> withTheExecutive = PartnerExclusiveCheckBatch.activeUsersOf(new Set<Id>{ executiveAccountId });
        Test.stopTest();

        System.assertEquals(new Set<Id>{ head.Id, executive.Id }, withTheHead, 'The head and its executive');
        System.assertEquals(new Set<Id>{ executive.Id }, withTheExecutive, 'Only the executive');
    }

    // The job really switches off the logins it is given (an inactive login uses no licence), and no other
    @isTest
    static void theDeactivationJobSwitchesOffTheLoginsItIsGiven() {
        User head = PartnerPortalTestUser.create();
        Id headAccountId = [SELECT Contact.AccountId FROM User WHERE Id = :head.Id].Contact.AccountId;
        User executive = PartnerPortalTestUser.createExecutiveOf(headAccountId);
        User other = PartnerPortalTestUser.createExecutiveOf(headAccountId);

        Test.startTest();
        System.enqueueJob(new PartnerUserActivationQueueable(new Set<Id>{ executive.Id }, false));
        Test.stopTest();

        System.assertEquals(false, [SELECT IsActive FROM User WHERE Id = :executive.Id].IsActive, 'The login it was given');
        System.assertEquals(true, [SELECT IsActive FROM User WHERE Id = :head.Id].IsActive, 'The head was not given');
        System.assertEquals(true, [SELECT IsActive FROM User WHERE Id = :other.Id].IsActive, 'Nor the other executive');
    }

    // End to end: one run of the nightly check closes the partner (or finds it closed) and switches off its login and
    // those of its executives, so none of them keeps a licence. The step of the job is called directly, so that its
    // deactivation job runs when the test stops.
    private static void theCheckSwitchesOffTheHeadAndItsExecutives(Account change, String expectedType) {
        useSettings();
        User head = PartnerPortalTestUser.create();
        Id headAccountId = [SELECT Contact.AccountId FROM User WHERE Id = :head.Id].Contact.AccountId;
        User executive = PartnerPortalTestUser.createExecutiveOf(headAccountId);
        User second = PartnerPortalTestUser.createExecutiveOf(headAccountId);
        Id ownerId = [SELECT OwnerId FROM Account WHERE Id = :headAccountId].OwnerId;
        change.Id = headAccountId;
        update change;

        Test.startTest();
        new PartnerExclusiveCheckBatch().execute((Database.BatchableContext) null, [
            SELECT Id, Name, OwnerId, Partner_Type__c, Temporary_Access_Start_Date__c, Temporary_Access_End_Date__c, Channel_Head__c
            FROM Account WHERE Id = :headAccountId
        ]);
        Test.stopTest();

        System.assertEquals(expectedType, [SELECT Partner_Type__c FROM Account WHERE Id = :headAccountId].Partner_Type__c);
        System.assertEquals(false, [SELECT IsActive FROM User WHERE Id = :head.Id].IsActive, 'The partner\'s login is off');
        System.assertEquals(false, [SELECT IsActive FROM User WHERE Id = :executive.Id].IsActive, 'Its executive\'s login is off');
        System.assertEquals(false, [SELECT IsActive FROM User WHERE Id = :second.Id].IsActive, 'And its other executive\'s');
        System.assertEquals(true, [SELECT IsActive FROM User WHERE Id = :ownerId].IsActive, 'Another user is left alone');
    }

    @isTest
    static void aPartnerDeniedByThisRunLosesItsLoginsWithItsExecutives() {
        theCheckSwitchesOffTheHeadAndItsExecutives(new Account(Partner_Type__c = 'Temporary', Temporary_Access_Start_Date__c = Date.today().addDays(-40),
            Temporary_Access_End_Date__c = Date.today().addDays(-10)), 'Access Denied');
    }

    @isTest
    static void aPartnerTerminatedByHandLosesItsLoginsWithItsExecutives() {
        theCheckSwitchesOffTheHeadAndItsExecutives(new Account(Partner_Type__c = 'Terminated'), 'Terminated');
    }

    @isTest
    static void aPartnerDeniedByHandLosesItsLoginsWithItsExecutives() {
        theCheckSwitchesOffTheHeadAndItsExecutives(new Account(Partner_Type__c = 'Access Denied'), 'Access Denied');
    }

    // A partner that is already Terminated or Access Denied and has an active login (the type set by hand, or the login
    // switched on again by hand) is swept by the next run
    private static void sweepsAClosedPartner(String partnerType) {
        useSettings();
        User partner = PartnerPortalTestUser.create();
        Id accountId = [SELECT Contact.AccountId FROM User WHERE Id = :partner.Id].Contact.AccountId;
        update new Account(Id = accountId, Partner_Type__c = partnerType);

        Test.startTest();
        Database.executeBatch(new PartnerExclusiveCheckBatch(), 20);
        Test.stopTest();

        System.assertEquals(partnerType, [SELECT Partner_Type__c FROM Account WHERE Id = :accountId].Partner_Type__c, 'The partner stays closed');
        System.assertEquals(1, deactivationJobs(), 'Its active login is switched off');
    }

    @isTest
    static void sweepsATerminatedPartnerWithAnActiveLogin() {
        sweepsAClosedPartner('Terminated');
    }

    @isTest
    static void sweepsAnAccessDeniedPartnerWithAnActiveLogin() {
        sweepsAClosedPartner('Access Denied');
    }

    // A closed partner whose logins are all off already needs no job
    @isTest
    static void aClosedPartnerWithoutAnActiveLoginNeedsNoJob() {
        useSettings();
        insert new Account(Name = 'Closed Long Ago Realty', RecordTypeId = partnerPortalRegistrationController.partnerRecordTypeId(),
            Document_Id__c = 'test-folder', Partner_Type__c = 'Terminated');

        Test.startTest();
        Database.executeBatch(new PartnerExclusiveCheckBatch(), 20);
        Test.stopTest();

        System.assertEquals(0, deactivationJobs());
    }

    // The earlier deactivation job still switches a login off when something calls it
    @isTest
    static void theEarlierDeactivationJobSwitchesALoginOff() {
        User partner = PartnerPortalTestUser.create();

        Test.startTest();
        System.enqueueJob(new ParnterUserDeactivationQueueable(new Set<Id>{ partner.Id }));
        Test.stopTest();

        System.assertEquals(false, [SELECT IsActive FROM User WHERE Id = :partner.Id].IsActive);
    }

    // Scheduled, it starts the check
    @isTest
    static void runsFromItsSchedule() {
        Test.startTest();
        String jobId = System.schedule('Partner Exclusive Check Test', '0 0 1 * * ?', new PartnerExclusiveCheckBatch());
        Test.stopTest();

        System.assertNotEquals(null, jobId);
    }
}