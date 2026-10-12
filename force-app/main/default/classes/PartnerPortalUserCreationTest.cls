// Approving a channel partner's registration (Onboarding Status Approved, as the Partner Onboarding Approval sets it)
// gives the partner 30 days of temporary access and a Partner Community user for its contact. An executive gets the
// user only: it works under its channel head's access, so its own Partner Type and dates stay blank.
@isTest
private class PartnerPortalUserCreationTest {

    @isTest
    static void anApprovedPartnerGetsTemporaryAccessAndAUser() {
        String email = 'cp' + String.valueOf(Math.abs(Crypto.getRandomInteger())) + '@partner-user-test.example.com';
        Account partner = new Account(Name = 'Partner User Test Realty', RecordTypeId = partnerPortalRegistrationController.partnerRecordTypeId(),
            Email__c = email, Onboarding_Status__c = 'Pending', Portal_Registration_User__c = true, Document_Id__c = 'test-folder');
        insert partner;
        insert new Contact(AccountId = partner.Id, FirstName = 'Kamal', LastName = 'Perera', Email = email);

        Test.startTest();
        update new Account(Id = partner.Id, Onboarding_Status__c = 'Approved');
        Test.stopTest();

        Account approved = [SELECT IsPartner, Partner_Type__c, Temporary_Access_Start_Date__c, Temporary_Access_End_Date__c FROM Account WHERE Id = :partner.Id];
        System.assertEquals(true, approved.IsPartner);
        System.assertEquals('Temporary', approved.Partner_Type__c);
        System.assertEquals(Date.today(), approved.Temporary_Access_Start_Date__c);
        System.assertEquals(Date.today().addDays(30), approved.Temporary_Access_End_Date__c);
        User created = [SELECT Username, Email, IsActive, Profile.Name FROM User WHERE Contact.AccountId = :partner.Id];
        System.assertEquals(email + '.partner', created.Username);
        System.assertEquals(email, created.Email);
        System.assertEquals(true, created.IsActive);
        System.assertEquals('Partner Community', created.Profile.Name);
        System.assertEquals(1, PartnerPortalUserCreation.accessEmailsSent, 'The partner is told about the temporary access');
        System.assertEquals(0, PartnerPortalUserCreation.executiveAccessEmailsSent, 'With the channel head\'s template, not the executive\'s');
    }

    private static Account registration(String name, String email, Id channelHeadId, String partnerType) {
        Account partner = new Account(Name = name, RecordTypeId = partnerPortalRegistrationController.partnerRecordTypeId(), Email__c = email,
            Onboarding_Status__c = 'Pending', Portal_Registration_User__c = true, Document_Id__c = 'test-folder-' + name.deleteWhitespace(),
            Channel_Head__c = channelHeadId, Partner_Type__c = partnerType);
        insert partner;
        insert new Contact(AccountId = partner.Id, FirstName = 'Kamal', LastName = name, Email = email);
        return partner;
    }

    // An executive approved after its channel head was terminated or denied gets no access, no login (which would use a
    // licence until the nightly job switched it off) and no email. An executive of an Exclusive head approved in the same
    // save gets its login and its email, so one closed head does not hold back the others.
    @isTest
    static void anExecutiveOfAClosedHeadGetsNoLogin() {
        String stamp = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        Account terminatedHead = registration('Terminated Head', 'th' + stamp + '@partner-user-test.example.com', null, 'Terminated');
        Account deniedHead = registration('Denied Head', 'dh' + stamp + '@partner-user-test.example.com', null, 'Access Denied');
        Account exclusiveHead = registration('Exclusive Head', 'xh' + stamp + '@partner-user-test.example.com', null, 'Exclusive');
        Account first = registration('Late Executive One', 'e1' + stamp + '@partner-user-test.example.com', terminatedHead.Id, null);
        Account second = registration('Late Executive Two', 'e2' + stamp + '@partner-user-test.example.com', deniedHead.Id, null);
        Account inTime = registration('Executive In Time', 'e3' + stamp + '@partner-user-test.example.com', exclusiveHead.Id, null);

        Test.startTest();
        update new List<Account>{ new Account(Id = first.Id, Onboarding_Status__c = 'Approved'), new Account(Id = second.Id, Onboarding_Status__c = 'Approved'),
            new Account(Id = inTime.Id, Onboarding_Status__c = 'Approved') };
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM User WHERE Contact.AccountId IN (:first.Id, :second.Id)], 'No login under a closed head');
        for (Account executive : [SELECT Name, Partner_Type__c, Temporary_Access_End_Date__c FROM Account WHERE Id IN (:first.Id, :second.Id)]) {
            System.assertEquals(null, executive.Partner_Type__c, executive.Name + ' gets no access');
            System.assertEquals(null, executive.Temporary_Access_End_Date__c);
        }
        User created = [SELECT IsActive FROM User WHERE Contact.AccountId = :inTime.Id];
        System.assertEquals(true, created.IsActive, 'The executive of the Exclusive head gets its login');
        System.assertEquals(null, [SELECT Partner_Type__c FROM Account WHERE Id = :inTime.Id].Partner_Type__c, 'An executive has no type of its own');
        System.assertEquals(1, PartnerPortalUserCreation.accessEmailsSent, 'Only that executive is emailed');
        System.assertEquals(1, PartnerPortalUserCreation.executiveAccessEmailsSent);
    }

    private static Account approved(Id accountId) {
        return [
            SELECT Name, IsPartner, Partner_Type__c, Temporary_Access_Start_Date__c, Temporary_Access_End_Date__c
            FROM Account WHERE Id = :accountId
        ];
    }

    // An executive has no access of its own: the approval gives it a login and the executive email, and leaves its Partner
    // Type and temporary access dates blank, also where they were filled before. A channel head approved in the same
    // save still gets Temporary and 30 days, and the email with the dates.
    @isTest
    static void anApprovedExecutiveKeepsItsTypeAndDatesBlank() {
        String stamp = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        Account head = registration('Exclusive Head', 'xh' + stamp + '@partner-user-test.example.com', null, 'Exclusive');
        Account executive = registration('New Executive', 'ne' + stamp + '@partner-user-test.example.com', head.Id, null);
        Account filled = registration('Earlier Executive', 'ee' + stamp + '@partner-user-test.example.com', head.Id, 'Temporary');
        update new Account(Id = filled.Id, Temporary_Access_Start_Date__c = Date.today().addDays(-40),
            Temporary_Access_End_Date__c = Date.today().addDays(-10));
        Account newHead = registration('New Head', 'nh' + stamp + '@partner-user-test.example.com', null, null);

        Test.startTest();
        update new List<Account>{ new Account(Id = executive.Id, Onboarding_Status__c = 'Approved'),
            new Account(Id = filled.Id, Onboarding_Status__c = 'Approved'), new Account(Id = newHead.Id, Onboarding_Status__c = 'Approved') };
        Test.stopTest();

        for (Id executiveId : new List<Id>{ executive.Id, filled.Id }) {
            Account result = approved(executiveId);
            System.assertEquals(true, result.IsPartner, result.Name);
            System.assertEquals(null, result.Partner_Type__c, result.Name + ' has no type of its own');
            System.assertEquals(null, result.Temporary_Access_Start_Date__c, result.Name);
            System.assertEquals(null, result.Temporary_Access_End_Date__c, result.Name);
        }
        System.assertEquals(2, [SELECT COUNT() FROM User WHERE Contact.AccountId IN (:executive.Id, :filled.Id) AND IsActive = true],
            'Both executives get their login');
        Account headResult = approved(newHead.Id);
        System.assertEquals('Temporary', headResult.Partner_Type__c, 'A channel head still gets temporary access');
        System.assertEquals(Date.today(), headResult.Temporary_Access_Start_Date__c);
        System.assertEquals(Date.today().addDays(30), headResult.Temporary_Access_End_Date__c);
        System.assertEquals('Exclusive', approved(head.Id).Partner_Type__c, 'The executives\' own channel head is untouched');
        System.assertEquals(3, PartnerPortalUserCreation.accessEmailsSent);
        System.assertEquals(2, PartnerPortalUserCreation.executiveAccessEmailsSent, 'The executives get the email without dates');
    }

    // Without a template in the setting there is no access email, for a channel head or an executive: both still get
    // their login (and the site's welcome email with it)
    @isTest
    static void noAccessEmailWithoutATemplate() {
        PartnerPortalUserCreation.setting = (Partner_Registration_Setting__mdt) JSON.deserialize(JSON.serialize(new Map<String, Object>{
            'DeveloperName' => 'Default',
            'MasterLabel' => 'Default',
            'Access_Email_Template__c' => 'No_Such_Email_Template',
            'Executive_Access_Email_Template__c' => null
        }), Partner_Registration_Setting__mdt.class);
        String stamp = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        Account head = registration('Exclusive Head', 'xh' + stamp + '@partner-user-test.example.com', null, 'Exclusive');
        Account executive = registration('New Executive', 'ne' + stamp + '@partner-user-test.example.com', head.Id, null);
        Account newHead = registration('New Head', 'nh' + stamp + '@partner-user-test.example.com', null, null);

        Test.startTest();
        update new List<Account>{ new Account(Id = executive.Id, Onboarding_Status__c = 'Approved'),
            new Account(Id = newHead.Id, Onboarding_Status__c = 'Approved') };
        Test.stopTest();

        System.assertEquals(2, [SELECT COUNT() FROM User WHERE Contact.AccountId IN (:executive.Id, :newHead.Id) AND IsActive = true]);
        System.assertEquals(0, PartnerPortalUserCreation.accessEmailsSent);
        System.assertEquals(0, PartnerPortalUserCreation.executiveAccessEmailsSent);
    }

    // A partner that is itself Terminated stays so when its registration is approved again
    @isTest
    static void aTerminatedPartnerApprovedAgainStaysTerminated() {
        String email = 'tp' + String.valueOf(Math.abs(Crypto.getRandomInteger())) + '@partner-user-test.example.com';
        Account partner = registration('Terminated Partner', email, null, 'Terminated');

        Test.startTest();
        update new Account(Id = partner.Id, Onboarding_Status__c = 'Approved');
        Test.stopTest();

        System.assertEquals('Terminated', [SELECT Partner_Type__c FROM Account WHERE Id = :partner.Id].Partner_Type__c);
        System.assertEquals(0, [SELECT COUNT() FROM User WHERE Contact.AccountId = :partner.Id]);
        System.assertEquals(0, PartnerPortalUserCreation.accessEmailsSent);
    }
}