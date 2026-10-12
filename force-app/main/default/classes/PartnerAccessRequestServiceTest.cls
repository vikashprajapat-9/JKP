// Requests to change a channel partner's access (PartnerAccessRequestService, partnerWebPortalAccessController,
// PartnerAccessRequestTrigger, PartnerAccessChangeTrigger): extensions approved by the CP Manager, terminations approved
// by the CP Head. The login page offers no extension (partnerPortalLoginController).
@isTest
private class PartnerAccessRequestServiceTest {

    private static void useSettings() {
        PartnerAccessRequestService.setting = (Partner_Portal_Setting__mdt) JSON.deserialize(JSON.serialize(new Map<String, Object>{
            'DeveloperName' => 'Default',
            'Extension_Day_Options__c' => '30, 15, 60, x',
            'Extension_Offer_Days__c' => 7,
            'Extension_Approved_Email_Template__c' => 'Partner_Portal_Access_Extended',
            'Extension_Rejected_Email_Template__c' => 'Partner_Portal_Access_Extension_Rejected',
            'Termination_Email_Template__c' => 'Partner_Portal_Access_Terminated'
        }), Partner_Portal_Setting__mdt.class);
        PartnerTemporaryAccess.setting = (Partner_Portal_Setting__mdt) JSON.deserialize(JSON.serialize(new Map<String, Object>{
            'DeveloperName' => 'Default',
            'Exclusive_Converted_Leads__c' => 1,
            'Exclusive_Site_Visits__c' => 3,
            'Completed_Visit_Status__c' => 'Completed'
        }), Partner_Portal_Setting__mdt.class);
    }

    // The test partner (a channel head) and its account, with this Partner Type and access end date
    private static User partnerWith(String partnerType, Integer endDays) {
        User partner = PartnerPortalTestUser.create();
        partner = [SELECT Id, Username, Contact.AccountId, Contact.Account.OwnerId FROM User WHERE Id = :partner.Id];
        update new Account(Id = partner.Contact.AccountId, Partner_Type__c = partnerType, Temporary_Access_Start_Date__c = Date.today().addDays(endDays - 30),
            Temporary_Access_End_Date__c = Date.today().addDays(endDays));
        return partner;
    }

    private static Partner_Access_Request__c requestOf(Id accountId) {
        return [
            SELECT Id, Type__c, Status__c, Approver__c, Requested_By__c, Requested_Via__c, Extension_Days__c, New_End_Date__c, Reason__c
            FROM Partner_Access_Request__c WHERE Account__c = :accountId ORDER BY CreatedDate DESC LIMIT 1
        ];
    }

    // The approver (or a member of the approving queue) decides the request
    private static void decide(Id requestId, Id decidedBy, String action) {
        ProcessInstanceWorkitem item = [SELECT Id FROM ProcessInstanceWorkitem WHERE ProcessInstance.TargetObjectId = :requestId LIMIT 1];
        Approval.ProcessWorkitemRequest decision = new Approval.ProcessWorkitemRequest();
        decision.setWorkitemId(item.Id);
        decision.setAction(action);
        System.runAs(new User(Id = decidedBy)) {
            Approval.ProcessResult result = Approval.process(decision);
            System.assert(result.isSuccess(), String.valueOf(result.getErrors()));
        }
    }

    // In the last days of its temporary access the channel head sees the banner and asks on the portal; the CP Manager (the
    // account owner's manager, else the owner) approves, and the access end date moves on by the days asked
    @isTest
    static void aPortalExtensionApprovedByTheCpManagerMovesTheEndDate() {
        useSettings();
        User partner = partnerWith('Temporary', 3);
        Id accountId = partner.Contact.AccountId;
        Id ownerId = partner.Contact.Account.OwnerId;

        Test.startTest();
        partnerWebPortalAccessController.AccessStatus before;
        partnerWebPortalAccessController.AccessStatus after;
        System.runAs(partner) {
            before = partnerWebPortalAccessController.getAccessStatus();
            after = partnerWebPortalAccessController.requestExtension(30, 'Two bookings are close');
        }
        Partner_Access_Request__c request = requestOf(accountId);
        String processStatus = [SELECT Status FROM ProcessInstance WHERE TargetObjectId = :request.Id].Status;
        decide(request.Id, ownerId, 'Approve');
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assertEquals(true, before.canRequest, before.message);
        System.assertEquals(3, before.daysLeft);
        System.assertEquals(new List<Integer>{ 15, 30, 60 }, before.options, 'The setting\'s periods, in order');
        System.assert(before.message.contains(before.accessEnd), before.message);
        System.assertEquals(true, after.pending);
        System.assertEquals(30, after.pendingDays);
        System.assertEquals(false, after.canRequest);
        System.assertEquals('Extension', request.Type__c);
        System.assertEquals('Portal', request.Requested_Via__c);
        System.assertEquals(partner.Id, request.Requested_By__c);
        System.assertEquals(ownerId, request.Approver__c, 'The owner has no manager: the owner approves');
        System.assertEquals('Pending', processStatus);
        Partner_Access_Request__c decided = requestOf(accountId);
        System.assertEquals('Approved', decided.Status__c);
        System.assertEquals(Date.today().addDays(33), decided.New_End_Date__c);
        Account extended = [SELECT Partner_Type__c, Temporary_Access_End_Date__c FROM Account WHERE Id = :accountId];
        System.assertEquals('Temporary', extended.Partner_Type__c);
        System.assertEquals(Date.today().addDays(33), extended.Temporary_Access_End_Date__c);
    }

    // A channel head whose access was denied (and its login deactivated) is only told on the login page whom to contact.
    // An extension asked for in Salesforce, once approved, makes it Temporary again, from today, and reactivates its
    // portal users; one request at a time
    @isTest
    static void aDeniedHeadWhoseExtensionIsApprovedIsLetBackIn() {
        useSettings();
        User partner = partnerWith('Access Denied', -10);
        Id accountId = partner.Contact.AccountId;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = partner.Id, IsActive = false);
        }

        Test.startTest();
        partnerPortalLoginController.LoginResult denied = partnerPortalLoginController.login(partner.Username, 'anything', '/PartnerPortal/');
        PartnerAccessRequestService.requestExtension(accountId, 15, 'Back from leave', PartnerAccessRequestService.VIA_SALESFORCE, UserInfo.getUserId());
        String again;
        try {
            PartnerAccessRequestService.requestExtension(accountId, 30, 'Again', PartnerAccessRequestService.VIA_SALESFORCE, UserInfo.getUserId());
        } catch (PartnerAccessRequestService.RequestException e) {
            again = e.getMessage();
        }
        Partner_Access_Request__c request = requestOf(accountId);
        decide(request.Id, partner.Contact.Account.OwnerId, 'Approve');
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assertEquals(partnerPortalLoginController.ACCESS_DENIED, denied.status);
        System.assertEquals(Label.Partner_Access_Request_Pending, again, 'One request at a time');
        System.assertEquals('Salesforce', request.Requested_Via__c);
        Account extended = [SELECT Partner_Type__c, Temporary_Access_End_Date__c FROM Account WHERE Id = :accountId];
        System.assertEquals('Temporary', extended.Partner_Type__c, 'Let back in');
        System.assertEquals(Date.today().addDays(15), extended.Temporary_Access_End_Date__c, 'Counted from today');
        System.assertEquals(1, [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'PartnerUserActivationQueueable'],
            'Its portal users are reactivated');
    }

    // A rejected extension changes nothing
    @isTest
    static void aRejectedExtensionChangesNothing() {
        useSettings();
        User partner = partnerWith('Temporary', 2);
        Id accountId = partner.Contact.AccountId;

        Test.startTest();
        System.runAs(partner) {
            partnerWebPortalAccessController.requestExtension(60, 'More time please');
        }
        decide(requestOf(accountId).Id, partner.Contact.Account.OwnerId, 'Reject');
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assertEquals('Rejected', requestOf(accountId).Status__c);
        System.assertEquals(Date.today().addDays(2), [SELECT Temporary_Access_End_Date__c FROM Account WHERE Id = :accountId].Temporary_Access_End_Date__c);
    }

    // The portal offers an extension only in the last days, to channel heads, for the offered periods and with a reason
    @isTest
    static void extensionsAreOfferedOnlyWhenTheyMakeSense() {
        useSettings();
        User partner = partnerWith('Temporary', 20);

        Test.startTest();
        partnerWebPortalAccessController.AccessStatus early;
        String tooEarly;
        System.runAs(partner) {
            early = partnerWebPortalAccessController.getAccessStatus();
            try {
                partnerWebPortalAccessController.requestExtension(30, 'Just in case');
            } catch (AuraHandledException e) {
                tooEarly = e.getMessage();
            }
        }
        update new Account(Id = partner.Contact.AccountId, Temporary_Access_End_Date__c = Date.today().addDays(5));
        List<String> refusals = new List<String>();
        for (Object[] attempt : new List<Object[]>{ new Object[]{ 10, 'Wrong period' }, new Object[]{ 30, ' ' } }) {
            try {
                PartnerAccessRequestService.requestExtension(partner.Contact.AccountId, (Integer) attempt[0], (String) attempt[1],
                    PartnerAccessRequestService.VIA_SALESFORCE, UserInfo.getUserId());
            } catch (PartnerAccessRequestService.RequestException e) {
                refusals.add(e.getMessage());
            }
        }
        Test.stopTest();

        System.assertEquals(false, early.canRequest);
        System.assertEquals(null, early.message, 'Nothing to show yet');
        System.assertEquals(Label.Partner_Access_Extension_Not_Available, tooEarly);
        System.assertEquals(new List<String>{ Label.Partner_Access_Extension_Days, Label.Partner_Access_Reason_Required }, refusals);
    }

    // The CP Manager asks to terminate a channel head; the CP Head (role Manager Sales Partnerships) approves: Terminated,
    // portal users deactivated, nothing more to ask
    @isTest
    static void aTerminationApprovedByTheCpHeadEndsTheAccess() {
        useSettings();
        User partner = partnerWith('Exclusive', 100);
        Id accountId = partner.Contact.AccountId;
        Id cpHeadRole = [SELECT Id FROM UserRole WHERE DeveloperName = 'Manager_Sales_Partnerships' LIMIT 1].Id;
        User cpHead = new User(ProfileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id, UserRoleId = cpHeadRole,
            LastName = 'Access Test CP Head', Alias = 'acchead', Email = 'cphead@access-test.example.com',
            Username = 'cphead.' + UserInfo.getOrganizationId() + '@access-test.example.com', TimeZoneSidKey = 'Asia/Colombo',
            LocaleSidKey = 'en_US', EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert cpHead;
        }

        Test.startTest();
        PartnerAccessRequestService.TerminationInfo info = PartnerAccessRequestService.getTerminationInfo(accountId);
        String reply = PartnerAccessRequestService.requestTermination(accountId, 'Breach of the channel partner terms');
        String again;
        try {
            PartnerAccessRequestService.requestTermination(accountId, 'Again');
        } catch (AuraHandledException e) {
            again = e.getMessage();
        }
        Partner_Access_Request__c request = requestOf(accountId);
        decide(request.Id, cpHead.Id, 'Approve');
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assertEquals(true, info.canRequest, info.message);
        System.assertEquals(true, info.isChannelHead);
        System.assertEquals(Label.Partner_Access_Termination_Info, info.message);
        System.assertEquals(Label.Partner_Access_Termination_Requested, reply);
        System.assertEquals(Label.Partner_Access_Request_Pending, again);
        System.assertEquals('Termination', request.Type__c);
        System.assertEquals('Approved', requestOf(accountId).Status__c);
        System.assertEquals('Terminated', [SELECT Partner_Type__c FROM Account WHERE Id = :accountId].Partner_Type__c);
        System.assertEquals(1, [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'PartnerUserActivationQueueable'],
            'Its portal users are deactivated');
        PartnerAccessRequestService.TerminationInfo after = PartnerAccessRequestService.getTerminationInfo(accountId);
        System.assertEquals(false, after.canRequest);
        System.assertEquals(Label.Partner_Access_Already_Terminated, after.message);
    }

    // The logins a termination switches off (and an extension after a denial switches on again): the partner's and
    // those of the executives under it
    @isTest
    static void aTerminationCoversTheLoginsOfTheExecutives() {
        User partner = partnerWith('Exclusive', 100);
        Id accountId = partner.Contact.AccountId;
        User executive = PartnerPortalTestUser.createExecutiveOf(accountId);
        Id executiveAccountId = [SELECT Contact.AccountId FROM User WHERE Id = :executive.Id].Contact.AccountId;

        Test.startTest();
        Set<Id> active = PartnerAccessRequestService.portalUsers(new Set<Id>{ accountId }, true);
        Set<Id> inactive = PartnerAccessRequestService.portalUsers(new Set<Id>{ accountId }, false);
        Set<Id> ofTheExecutive = PartnerAccessRequestService.portalUsers(new Set<Id>{ executiveAccountId }, true);
        Test.stopTest();

        System.assertEquals(new Set<Id>{ partner.Id, executive.Id }, active, 'Terminating the head switches both logins off');
        System.assertEquals(new Set<Id>(), inactive);
        System.assertEquals(new Set<Id>{ executive.Id }, ofTheExecutive, 'Terminating one executive leaves the head');
    }

    // An extension after a denial switches the logins on again, but not that of an executive that is itself Terminated
    @isTest
    static void anExtensionLeavesAClosedExecutiveOff() {
        User partner = partnerWith('Temporary', 10);
        Id accountId = partner.Contact.AccountId;
        User executive = PartnerPortalTestUser.createExecutiveOf(accountId);
        User terminated = PartnerPortalTestUser.createExecutiveOf(accountId);
        Id terminatedAccountId = [SELECT Contact.AccountId FROM User WHERE Id = :terminated.Id].Contact.AccountId;
        update new Account(Id = terminatedAccountId, Partner_Type__c = 'Terminated');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new List<User>{ new User(Id = partner.Id, IsActive = false), new User(Id = executive.Id, IsActive = false),
                new User(Id = terminated.Id, IsActive = false) };
        }

        Test.startTest();
        Set<Id> toSwitchOn = PartnerAccessRequestService.portalUsers(new Set<Id>{ accountId }, false);
        Test.stopTest();

        System.assertEquals(new Set<Id>{ partner.Id, executive.Id }, toSwitchOn, 'The terminated executive stays off');
    }

    // Only channel partner accounts can be terminated, and a reason is needed
    @isTest
    static void terminationNeedsAChannelPartnerAndAReason() {
        useSettings();
        Account customer = new Account(Name = 'Not A Partner',
            RecordTypeId = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND DeveloperName = 'Customer' LIMIT 1].Id);
        insert customer;
        User partner = partnerWith('Temporary', 10);

        Test.startTest();
        PartnerAccessRequestService.TerminationInfo info = PartnerAccessRequestService.getTerminationInfo(customer.Id);
        List<String> refusals = new List<String>();
        for (Id accountId : new List<Id>{ customer.Id, partner.Contact.AccountId }) {
            try {
                PartnerAccessRequestService.requestTermination(accountId, accountId == customer.Id ? 'Reason' : '  ');
            } catch (AuraHandledException e) {
                refusals.add(e.getMessage());
            }
        }
        PartnerUserActivationQueueable nothing = new PartnerUserActivationQueueable(new Set<Id>(), false);
        nothing.execute(null);
        Test.stopTest();

        System.assertEquals(false, info.canRequest);
        System.assertEquals(Label.Partner_Access_Termination_Not_Partner, info.message);
        System.assertEquals(new List<String>{ Label.Partner_Access_Termination_Not_Partner, Label.Partner_Access_Reason_Required }, refusals);
    }

    // The emails of these decisions go out only when the templates named in the settings exist: a name that matches no
    // template sends nothing, without an error. Both the names these tests use and the ones the org's Partner Portal
    // Setting holds must be templates in the John Keells design (custom HTML), ready to send.
    @isTest
    static void theSettingsNameEmailTemplatesThatExist() {
        useSettings();
        Partner_Portal_Setting__mdt live = Partner_Portal_Setting__mdt.getInstance('Default');
        Set<String> names = new Set<String>();
        for (Partner_Portal_Setting__mdt record : new List<Partner_Portal_Setting__mdt>{ PartnerAccessRequestService.setting, live }) {
            if (record == null) {
                continue;
            }
            for (String name : new List<String>{ record.Extension_Approved_Email_Template__c, record.Extension_Rejected_Email_Template__c,
                    record.Termination_Email_Template__c }) {
                if (String.isNotBlank(name)) {
                    names.add(name.trim());
                }
            }
        }
        System.assert(names.size() >= 3, 'An email for each decision: ' + names);

        Set<String> ready = new Set<String>();
        for (EmailTemplate template : [SELECT DeveloperName FROM EmailTemplate WHERE DeveloperName IN :names AND IsActive = true AND TemplateType = 'custom']) {
            ready.add(template.DeveloperName);
        }
        names.removeAll(ready);
        System.assertEquals(new Set<String>(), names, 'Named in the settings, but no active HTML template of that name');
    }
}