// The "Site visit done & transition from agent to JKP team" lane (PartnerLeadHandover): a partner's lead that reaches
// Visited goes to the JKP CP Executive with a task and an email; the partner then sees it read-only but can still upload
// documents; a converted lead's documents follow the customer.
@isTest
private class PartnerLeadHandoverTest {

    private static Integer leadCount = 0;

    // The JKP CP Executive (whose manager is the CP Manager), named in the settings
    private static User cpExecutive() {
        Id adminProfileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id;
        User manager = internalUser(adminProfileId, 'homgr', null);
        User executive;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert manager;
            executive = internalUser(adminProfileId, 'hoexec', manager.Id);
            insert executive;
        }
        PartnerSiteVisitService.setting = new Partner_Portal_Setting__mdt(CP_Executive_Username__c = executive.Username);
        PartnerLeadHandover.setting = new Partner_Portal_Setting__mdt(Hand_Over_Lead_Status__c = 'Visited',
            Hand_Over_Email_Template__c = 'CP_Lead_Hand_Over');
        return executive;
    }

    private static User internalUser(Id profileId, String alias, Id managerId) {
        return new User(ProfileId = profileId, Alias = alias, LastName = 'Hand Over ' + alias, Email = alias + '@example.com',
            Username = alias + '.' + UserInfo.getOrganizationId() + '@hand-over-test.example.com', EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US', TimeZoneSidKey = 'Asia/Colombo', ManagerId = managerId);
    }

    private static Id accountOf(User portalUser) {
        return [SELECT Contact.AccountId FROM User WHERE Id = :portalUser.Id].Contact.AccountId;
    }

    private static Id project() {
        Project__c project = TestRecordDefaults.project('Hand Over Test Project', true);
        insert project;
        return project.Id;
    }

    private static Lead leadOf(Id channelPartnerId, Id ownerId, Id projectId) {
        leadCount++;
        Lead record = new Lead(LastName = 'Hand Over Buyer ' + leadCount, Company = 'Hand Over Holdings ' + leadCount,
            Phone = '07712366' + String.valueOf(leadCount).leftPad(2, '0'), Email = 'hand.over' + leadCount + '@example.com',
            LeadSource = 'Channel Partner', Budget_Aligned__c = 'Matching Budget', Project__c = projectId,
            Channel_Partner__c = channelPartnerId, OwnerId = ownerId);
        insert record;
        return record;
    }

    // Visited: the lead goes to the JKP CP Executive, who gets a task and an email; the partner sees it read-only with
    // the reason, and can still upload documents
    @isTest
    static void aVisitedLeadGoesToTheJkpCpTeam() {
        User executive = cpExecutive();
        User partner = PartnerPortalTestUser.create();
        Lead record = leadOf(accountOf(partner), partner.Id, project());

        Test.startTest();
        update new Lead(Id = record.Id, Status = 'Visited');
        Test.stopTest();
        partnerWebPortalLeadEditController.EditOptions options;
        partnerWebPortalLeadDocuments.LeadDocuments documents;
        System.runAs(partner) {
            options = partnerWebPortalLeadEditController.getEditOptions(record.Id);
            documents = partnerWebPortalLeadDocuments.getLeadDocuments(record.Id);
        }

        Lead saved = [SELECT OwnerId, Status, Name FROM Lead WHERE Id = :record.Id];
        System.assertEquals(executive.Id, saved.OwnerId, 'The JKP CP Executive takes the lead over');
        System.assertEquals('Visited', saved.Status);
        List<Task> tasks = [SELECT OwnerId, Subject, Priority, ActivityDate, Description FROM Task WHERE WhoId = :record.Id AND Priority = 'High'];
        System.assertEquals(1, tasks.size(), String.valueOf(tasks));
        System.assertEquals(executive.Id, tasks[0].OwnerId);
        System.assertEquals(String.format(PartnerLeadHandover.PARTNER_LEAD_HAND_OVER_SUBJECT, new List<Object>{ saved.Name }), tasks[0].Subject);
        System.assertEquals(Date.today().addDays(1), tasks[0].ActivityDate);
        System.assert(tasks[0].Description.contains('Hand Over Test Project'), tasks[0].Description);
        System.assert(tasks[0].Description.contains('check the customer\'s documents'), tasks[0].Description);
        System.assertEquals(1, PartnerLeadHandover.emailsWritten, 'The CP team is emailed');
        System.assertEquals(false, options.canEdit);
        System.assertEquals(partnerWebPortalLeadEditController.PARTNER_LEAD_READ_ONLY_TAKEN_OVER, options.readOnlyReason);
        System.assertEquals(true, documents.canUpload, 'The partner can still upload the customer\'s documents');
    }

    // A lead JKP already owns, and a stage that is not the hand-over stage, are left alone
    @isTest
    static void onlyAPartnersLeadAtTheHandOverStageMoves() {
        User executive = cpExecutive();
        User partner = PartnerPortalTestUser.create();
        Id projectId = project();
        Lead jkps = leadOf(accountOf(partner), UserInfo.getUserId(), projectId);
        Lead qualified = leadOf(accountOf(partner), partner.Id, projectId);

        Test.startTest();
        update new List<Lead>{ new Lead(Id = jkps.Id, Status = 'Visited'), new Lead(Id = qualified.Id, Status = 'Qualified') };
        Test.stopTest();

        System.assertEquals(UserInfo.getUserId(), [SELECT OwnerId FROM Lead WHERE Id = :jkps.Id].OwnerId);
        System.assertEquals(partner.Id, [SELECT OwnerId FROM Lead WHERE Id = :qualified.Id].OwnerId);
        System.assertEquals(0, [SELECT COUNT() FROM Task WHERE WhoId IN (:jkps.Id, :qualified.Id) AND Priority = 'High']);
        System.assertEquals(0, PartnerLeadHandover.emailsWritten);
    }

    // A converted lead's documents follow the customer: the new account and opportunity get them
    @isTest
    static void aConvertedLeadsDocumentsFollowTheCustomer() {
        cpExecutive();
        User partner = PartnerPortalTestUser.create();
        Lead record = leadOf(accountOf(partner), UserInfo.getUserId(), project());
        Document__c document = new Document__c(Name = 'NIC / Passport', Lead__c = record.Id, Document_Id__c = 'FOLDER-1');
        insert document;

        Test.startTest();
        Database.LeadConvert conversion = new Database.LeadConvert();
        conversion.setLeadId(record.Id);
        conversion.setConvertedStatus([SELECT MasterLabel FROM LeadStatus WHERE IsConverted = true LIMIT 1].MasterLabel);
        Database.LeadConvertResult result = Database.convertLead(conversion);
        Test.stopTest();

        Document__c moved = [SELECT Account__c, Opportunity__c, Lead__c FROM Document__c WHERE Id = :document.Id];
        System.assertEquals(result.getAccountId(), moved.Account__c);
        System.assertEquals(result.getOpportunityId(), moved.Opportunity__c);
        System.assertEquals(record.Id, moved.Lead__c, 'Still linked to the lead');
    }
}