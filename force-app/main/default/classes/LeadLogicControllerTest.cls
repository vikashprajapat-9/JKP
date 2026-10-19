// The lead logic LeadTrigger runs (LeadLogicController, LeadTriggerHandler, LeadSystemOperations). Internal leads are
// assigned, scored and followed up, and the team's duplicate check turns a repeat enquiry into a Re-Enquiry. Channel
// partner (CP) leads follow the CP rules, from the portal (partnerWebPortalLeadController.createLead) or any other
// insert, up to the Direct Sales approval of the lead (the CP Lead Approval process).
@isTest
private class LeadLogicControllerTest {

    // Refuses the SharePoint folder call, so the folder jobs of the test project end quietly
    private class SharePointMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(503);
            res.setBody('{"error":{"code":"serviceNotAvailable"}}');
            return res;
        }
    }

    // A channel partner on the portal and another channel partner's account; the Direct Sales user whose customers
    // they may meet; the two managers who approve (the Direct Sales owner's manager, and the JKP CP Manager: the
    // manager of the user who owns the partner's account); a user without a manager; and an active project
    private class Fixture {
        User partner;
        Id partnerAccountId;
        Id otherPartnerAccountId;
        User directOwner;
        User directManager;
        User partnerManager;
        User ownerWithoutManager;
        Id projectId;
    }

    private static Integer leadCount = 0;

    private static Id newProject() {
        return newProject('Lead Logic Test Project');
    }

    private static Id newProject(String name) {
        SharePointService.testDriveId = 'test-drive';
        Test.setMock(HttpCalloutMock.class, new SharePointMock());
        Project__c project = TestRecordDefaults.project(name, true);
        insert project;
        return project.Id;
    }

    private static Fixture newFixture() {
        Fixture fixture = new Fixture();
        fixture.projectId = newProject();
        fixture.partner = PartnerPortalTestUser.create();
        User partner = [SELECT Contact.AccountId, Contact.Account.OwnerId FROM User WHERE Id = :fixture.partner.Id];
        fixture.partnerAccountId = partner.Contact.AccountId;
        Id adminProfileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id;
        // Users in their own context, so the test can still insert records
        System.runAs(new User(Id = UserInfo.getUserId())) {
            fixture.directManager = newUser(adminProfileId, 'dsmgr', null);
            fixture.partnerManager = newUser(adminProfileId, 'cpmgr', null);
            fixture.ownerWithoutManager = newUser(adminProfileId, 'nomgr', null);
            insert new List<User>{ fixture.directManager, fixture.partnerManager, fixture.ownerWithoutManager };
            fixture.directOwner = newUser(adminProfileId, 'dsales', fixture.directManager.Id);
            insert fixture.directOwner;
            update new User(Id = partner.Contact.Account.OwnerId, ManagerId = fixture.partnerManager.Id);
        }
        Account other = new Account(Name = 'Other Channel Partner', RecordTypeId = partnerPortalRegistrationController.partnerRecordTypeId());
        insert other;
        fixture.otherPartnerAccountId = other.Id;
        return fixture;
    }

    // An internal user (a System Administrator, who can approve) with the given manager
    private static User newUser(Id profileId, String alias, Id managerId) {
        return new User(
            ProfileId = profileId,
            ManagerId = managerId,
            LastName = 'Lead Test ' + alias,
            Alias = alias,
            Email = alias + '@lead-logic-test.example.com',
            Username = alias + '.' + UserInfo.getOrganizationId() + '@lead-logic-test.example.com',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }

    // A lead the lead validation rules accept. Its company and email are its own, so the standard duplicate rule
    // never takes it for another lead: only the phone and the project say who the customer is.
    private static Lead newLead(String name, String phone, Id projectId) {
        leadCount++;
        return new Lead(LastName = name, Company = name + ' Holdings ' + leadCount, Phone = phone,
            Email = 'buyer' + leadCount + '@lead-logic-test.example.com', Budget_Aligned__c = 'Matching Budget',
            Project__c = projectId, Status = 'New');
    }

    // A Direct Sales lead (Manual, Warm), owned by the given user
    private static Lead directLead(String name, String phone, Id projectId, Id ownerId) {
        Lead record = newLead(name, phone, projectId);
        record.LeadSource = 'Manual';
        record.Lead_Sub_Source__c = 'Direct Lead';
        record.Lead_Classification__c = 'Warm';
        record.OwnerId = ownerId;
        return record;
    }

    // A channel partner's lead as the portal saves it: the Channel Partner source and account, owned by the given user
    private static Lead channelPartnerLead(String name, String phone, Id projectId, Id channelPartnerId, Id ownerId) {
        Lead record = newLead(name, phone, projectId);
        record.LeadSource = 'Channel Partner';
        record.Channel_Partner__c = channelPartnerId;
        record.OwnerId = ownerId;
        return record;
    }

    // The portal's New Lead form, sent by the logged-in partner
    private static partnerWebPortalLeadController.CreateLeadResult submit(String name, String email, String phone, Id projectId) {
        return partnerWebPortalLeadController.createLead(name, null, email, phone, 'No. 42, Galle Road', projectId, 'Matching Budget',
            'Prefers a sea view');
    }

    // The message the portal shows when the form is refused, or null when it is accepted
    private static String refusal(String name, String email, String phone, Id projectId) {
        try {
            submit(name, email, phone, projectId);
            return null;
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
    }

    // The message that refuses the lead, or null when it is saved
    private static String insertError(Lead record) {
        try {
            insert record;
            return null;
        } catch (DmlException e) {
            return e.getDmlMessage(0);
        }
    }

    // What the CP lead rules did with the lead at this position of the last insert (null: not a CP lead)
    private static String outcomeOf(Integer index) {
        LeadLogicController.ChannelPartnerOutcome outcome = LeadLogicController.channelPartnerOutcomes[index];
        return outcome == null ? null : outcome.status;
    }

    private static List<String> taskSubjectsOf(Id leadId) {
        List<String> subjects = new List<String>();
        for (Task followUp : [SELECT Subject FROM Task WHERE WhoId = :leadId ORDER BY Subject]) {
            subjects.add(followUp.Subject);
        }
        return subjects;
    }

    // How many of the partner's leads they can use (for a site visit); run as the partner
    private static Integer usableLeadsOf(User partner) {
        Map<String, Object> binds = new Map<String, Object>();
        return Database.countQueryWithBinds('SELECT COUNT() FROM Lead WHERE ' + PartnerPortalAccess.current().ownLeads(binds), binds,
            AccessLevel.SYSTEM_MODE);
    }

    // The managers the approval request waits for
    private static Set<Id> approversOf(Id requestId) {
        Set<Id> approvers = new Set<Id>();
        for (ProcessInstanceWorkitem workitem : [SELECT ActorId FROM ProcessInstanceWorkitem WHERE ProcessInstance.TargetObjectId = :requestId]) {
            approvers.add(workitem.ActorId);
        }
        return approvers;
    }

    // The approver answers their part of the request: 'Approve' or 'Reject'
    private static void answer(Id requestId, User approver, String action) {
        ProcessInstanceWorkitem workitem = [
            SELECT Id FROM ProcessInstanceWorkitem WHERE ProcessInstance.TargetObjectId = :requestId AND ActorId = :approver.Id
        ];
        Approval.ProcessWorkitemRequest decision = new Approval.ProcessWorkitemRequest();
        decision.setWorkitemId(workitem.Id);
        decision.setAction(action);
        decision.setComments('Answered by the test');
        System.runAs(approver) {
            Approval.ProcessResult result = Approval.process(decision);
            System.assert(result.isSuccess(), String.valueOf(result.getErrors()));
        }
    }

    // The Partner Portal Setting's site visit statuses and the CP Lead Lost Status
    private static void useVisitSettings() {
        LeadLogicController.portalSetting = new Partner_Portal_Setting__mdt(Completed_Visit_Status__c = 'Completed',
            CP_Lead_Lost_Status__c = 'Site Visit Done by Other Agent', Open_Visit_Statuses__c = 'Upcoming, Rescheduled',
            Cancelled_Visit_Status__c = 'Cancelled');
    }

    // A site visit with the lead's customer, in the lead's project
    private static Visit__c newVisit(Lead visited, String status) {
        return new Visit__c(Lead__c = visited.Id, Project__c = visited.Project__c, Visit_Date__c = Date.today().addDays(1), Status__c = status);
    }

    // Every approver of the request approves their part, whoever they are
    private static void approveAll(Id requestId) {
        for (ProcessInstanceWorkitem workitem : [
            SELECT Id, ActorId FROM ProcessInstanceWorkitem WHERE ProcessInstance.TargetObjectId = :requestId ORDER BY CreatedDate, Id
        ]) {
            Approval.ProcessWorkitemRequest decision = new Approval.ProcessWorkitemRequest();
            decision.setWorkitemId(workitem.Id);
            decision.setAction('Approve');
            System.runAs(new User(Id = workitem.ActorId)) {
                Approval.ProcessResult result = Approval.process(decision);
                System.assert(result.isSuccess(), String.valueOf(result.getErrors()));
            }
        }
    }

    private static Id convert(Lead record) {
        Database.LeadConvert conversion = new Database.LeadConvert();
        conversion.setLeadId(record.Id);
        conversion.setConvertedStatus([SELECT MasterLabel FROM LeadStatus WHERE IsConverted = true LIMIT 1].MasterLabel);
        return Database.convertLead(conversion).getOpportunityId();
    }

    private static Set<String> messagesOf(SObject record) {
        Set<String> messages = new Set<String>();
        for (Database.Error error : record.getErrors()) {
            messages.add(error.getMessage());
        }
        return messages;
    }

    // An Id of the type that no record has
    private static Id fakeId(Schema.SObjectType type, Integer n) {
        return Id.valueOf(type.getDescribe().getKeyPrefix() + String.valueOf(n).leftPad(12, '0'));
    }

    // =====================================================================================================
    // INTERNAL LEADS
    // =====================================================================================================

    // An internal user's own lead is assigned to them as it is saved: Assigned, the pre-sales fields, the normalised
    // phone, the 4-hour follow-up of a Warm lead and the assignment history
    @isTest
    static void anInternalLeadIsAssignedToItsOwner() {
        Id projectId = newProject();
        Lead manual = directLead('Nimal Silva', '+91 98765 43210', projectId, UserInfo.getUserId());

        Test.startTest();
        insert manual;
        Test.stopTest();

        Lead saved = [SELECT Status, Is_User_Assigned__c, Pre_Sales_Team_Member__c, Lead_Assigned_Date_Time__c, Normalised_Phone__c
            FROM Lead WHERE Id = :manual.Id];
        System.assertEquals('Assigned', saved.Status);
        System.assert(saved.Is_User_Assigned__c);
        System.assertEquals(UserInfo.getUserId(), saved.Pre_Sales_Team_Member__c);
        System.assertNotEquals(null, saved.Lead_Assigned_Date_Time__c);
        System.assertEquals('9876543210', saved.Normalised_Phone__c, 'The last 10 digits of the phone');
        Task followUp = [SELECT Subject, OwnerId, Status, ActivityDate FROM Task WHERE WhoId = :manual.Id];
        System.assertEquals('Contact the lead within 4 hrs', followUp.Subject);
        System.assertEquals(UserInfo.getUserId(), followUp.OwnerId);
        System.assertEquals('Not Started', followUp.Status);
        System.assertEquals(saved.Lead_Assigned_Date_Time__c.date(), followUp.ActivityDate);
        List<Lead_Assignment_History__c> history = [SELECT Lead_Assigned_To__c, SLA1__c FROM Lead_Assignment_History__c WHERE Lead__c = :manual.Id];
        System.assertEquals(1, history.size());
        System.assertEquals(UserInfo.getUserId(), history[0].Lead_Assigned_To__c);
        System.assertEquals(false, history[0].SLA1__c);
    }

    // A website form lead is Hot, so its owner is asked to contact it within the hour
    @isTest
    static void aWebsiteFormLeadIsHotAndToBeContactedWithinAnHour() {
        Id projectId = newProject();
        Lead website = newLead('Kumari Dias', '0712345678', projectId);
        website.LeadSource = 'Digital';
        website.Lead_Sub_Source__c = 'Website Forms';

        Test.startTest();
        insert website;
        Test.stopTest();

        System.assertEquals('Hot', [SELECT Lead_Classification__c FROM Lead WHERE Id = :website.Id].Lead_Classification__c);
        System.assertEquals(new List<String>{ 'Contact the lead within 1 hr' }, taskSubjectsOf(website.Id));
    }

    // A Meta lead is scored from the Lead Score Config of its values in the scored fields (the Lead Score Field
    // records), and classified by the active Lead Priority Config its score falls in; a blank field scores nothing
    @isTest
    static void aMetaLeadIsScoredFromTheScoreConfiguration() {
        Id projectId = newProject();
        Map<String, Integer> scoreByField = new Map<String, Integer>{
            'Budget_Aligned__c' => 30, 'Designation__c' => 25, 'Purchase_Type__c' => 20, 'Time_to_Purchase__c' => 15
        };
        insert new List<Lead_Score_Config__c>{
            new Lead_Score_Config__c(Field_API_Name__c = 'Budget_Aligned__c', Picklist_Value__c = 'Premium Buyer', Score__c = 30, Active__c = true),
            new Lead_Score_Config__c(Field_API_Name__c = 'Designation__c', Picklist_Value__c = 'C-Suite', Score__c = 25, Active__c = true),
            new Lead_Score_Config__c(Field_API_Name__c = 'Purchase_Type__c', Picklist_Value__c = 'Investment', Score__c = 20, Active__c = true),
            new Lead_Score_Config__c(Field_API_Name__c = 'Time_to_Purchase__c', Picklist_Value__c = 'Immediate', Score__c = 15, Active__c = true),
            // Not counted: a value the leads do not have, an inactive config and a config without its field
            new Lead_Score_Config__c(Field_API_Name__c = 'Designation__c', Picklist_Value__c = 'Doctor', Score__c = 400, Active__c = true),
            new Lead_Score_Config__c(Field_API_Name__c = 'Purchase_Type__c', Picklist_Value__c = 'Investment', Score__c = 400, Active__c = false),
            new Lead_Score_Config__c(Field_API_Name__c = null, Picklist_Value__c = 'Premium Buyer', Score__c = 400, Active__c = true)
        };
        insert new List<Lead_Priority_Configs__c>{
            new Lead_Priority_Configs__c(Min_Score__c = 1, Max_Score__c = 100, Priority__c = 'Warm', Active__c = true),
            new Lead_Priority_Configs__c(Min_Score__c = 101, Max_Score__c = 1000, Priority__c = 'Hot', Active__c = true),
            new Lead_Priority_Configs__c(Min_Score__c = 0, Max_Score__c = 1000, Priority__c = 'Hot', Active__c = false)
        };
        Integer expected = 0;
        Integer expectedBudgetOnly = 0;
        for (Lead_Score_Field__mdt field : [SELECT Field_API_Name__c FROM Lead_Score_Field__mdt WHERE Active__c = true]) {
            expected += scoreByField.containsKey(field.Field_API_Name__c) ? scoreByField.get(field.Field_API_Name__c) : 0;
            expectedBudgetOnly += field.Field_API_Name__c == 'Budget_Aligned__c' ? scoreByField.get('Budget_Aligned__c') : 0;
        }
        Lead meta = newLead('Dinesh Karunaratne', '0715555555', projectId);
        meta.LeadSource = 'Digital';
        meta.Lead_Sub_Source__c = 'Meta Lead Ads';
        meta.Budget_Aligned__c = 'Premium Buyer';
        meta.Designation__c = 'C-Suite';
        meta.Purchase_Type__c = 'Investment';
        meta.Time_to_Purchase__c = 'Immediate';
        Lead budgetOnly = newLead('Anusha Peiris', '0715555556', projectId);
        budgetOnly.LeadSource = 'Digital';
        budgetOnly.Lead_Sub_Source__c = 'Meta Form Ads';
        budgetOnly.Budget_Aligned__c = 'Premium Buyer';

        Test.startTest();
        insert new List<Lead>{ meta, budgetOnly };
        Test.stopTest();

        Lead scored = [SELECT Lead_Score__c, Lead_Classification__c FROM Lead WHERE Id = :meta.Id];
        System.assert(expected > 0 && expectedBudgetOnly > 0, 'The org scores these fields (Lead Score Field records)');
        System.assertEquals(expected, scored.Lead_Score__c.intValue());
        System.assertEquals('Warm', scored.Lead_Classification__c, 'The active config from 1 to 100');
        scored = [SELECT Lead_Score__c, Lead_Classification__c FROM Lead WHERE Id = :budgetOnly.Id];
        System.assertEquals(expectedBudgetOnly, scored.Lead_Score__c.intValue(), 'Only the budget is filled in');
        System.assertEquals('Warm', scored.Lead_Classification__c);
    }

    // The team's duplicate check: an internal lead for a customer already in the project (the same last 10 digits of
    // the phone) is refused, and the enquiry is recorded as a Re-Enquiry on the first lead
    @isTest
    static void anInternalDuplicateBecomesAReEnquiryOnTheFirstLead() {
        Id projectId = newProject();
        Lead first = directLead('Nimal Silva', '+91 98765 43210', projectId, UserInfo.getUserId());
        insert first;
        Lead again = newLead('Nimal S', '098765-43210', projectId);
        again.LeadSource = 'Digital';
        again.Lead_Sub_Source__c = 'Website Forms';

        Test.startTest();
        String refused = insertError(again);
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assertEquals('Lead already exists. Re-Enquiry has been created.', refused);
        System.assertEquals(1, [SELECT COUNT() FROM Lead], 'The repeat enquiry is not a new lead');
        Re_Enquiry__c reEnquiry = [SELECT Lead__c, Opportunity__c, Re_Enquiry_Source__c, Re_Enquiry_Sub_Source__c, Source_Match__c,
            Sub_Source_Match__c FROM Re_Enquiry__c];
        System.assertEquals(first.Id, reEnquiry.Lead__c);
        System.assertEquals(null, reEnquiry.Opportunity__c);
        System.assertEquals('Digital', reEnquiry.Re_Enquiry_Source__c);
        System.assertEquals('Website Forms', reEnquiry.Re_Enquiry_Sub_Source__c);
        System.assertEquals('New Source', reEnquiry.Source_Match__c);
        System.assertEquals('New Sub Source', reEnquiry.Sub_Source_Match__c);
        System.assert([SELECT Multi_Channel_Engaged__c FROM Lead WHERE Id = :first.Id].Multi_Channel_Engaged__c, 'Engaged on a second channel');
    }

    // A customer who already converted is a duplicate too: the new internal lead is refused
    @isTest
    static void anInternalDuplicateOfAConvertedCustomerIsRefused() {
        Id projectId = newProject();
        Lead first = directLead('Nimal Silva', '0771234567', projectId, UserInfo.getUserId());
        insert first;
        convert(first);
        Lead again = directLead('Nimal S', '077 123 4567', projectId, UserInfo.getUserId());

        Test.startTest();
        String refused = insertError(again);
        Test.stopTest();

        System.assertEquals('Lead already exists. Re-Enquiry has been created.', refused);
        System.assertEquals(1, [SELECT COUNT() FROM Lead], 'Only the converted lead');
    }

    // The team's duplicate check is Phone + Project too: the same number in another project is a new lead, and no
    // Re-Enquiry is made
    @isTest
    static void anInternalLeadWithTheSameNumberInAnotherProjectIsANewLead() {
        Id projectId = newProject();
        Id otherProjectId = newProject('Lead Logic Other Project');
        insert directLead('Nimal Silva', '+91 98765 43210', projectId, UserInfo.getUserId());
        Lead elsewhere = directLead('Nimal S', '098765-43210', otherProjectId, UserInfo.getUserId());

        Test.startTest();
        String refused = insertError(elsewhere);
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assertEquals(null, refused, 'Another project: not a duplicate');
        Lead saved = [SELECT Status, Normalised_Phone__c FROM Lead WHERE Id = :elsewhere.Id];
        System.assertEquals('Assigned', saved.Status);
        System.assertEquals('9876543210', saved.Normalised_Phone__c, 'The same customer number as the first lead');
        System.assertEquals(0, [SELECT COUNT() FROM Re_Enquiry__c], 'No Re-Enquiry');
    }

    // A customer only a channel partner has is locked to them: an internal lead for the customer and project is refused
    // during the CP lock-in (no Re-Enquiry on the partner's lead)
    @isTest
    static void anInternalLeadForAPartnersCustomerIsRefusedDuringTheLockIn() {
        Fixture fixture = newFixture();
        LeadLogicController.portalSetting = new Partner_Portal_Setting__mdt(CP_Lock_In_Days__c = 60);
        insert channelPartnerLead('Chamari Perera', '0770000003', fixture.projectId, fixture.partnerAccountId, fixture.partner.Id);
        Lead walkIn = directLead('Chamari P', '077 000 0003', fixture.projectId, UserInfo.getUserId());

        Test.startTest();
        String refused = insertError(walkIn);
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assertEquals(String.format(LeadLogicController.CP_LEAD_LOCK_IN_ACTIVE, new List<Object>{ Date.today().addDays(60).format() }), refused);
        System.assertEquals(0, [SELECT COUNT() FROM Re_Enquiry__c], 'No Re-Enquiry on the partner\'s lead');
        System.assertEquals(1, [SELECT COUNT() FROM Lead]);
    }

    // After the CP lock-in, the customer is open to others: an internal lead for it is a new lead
    @isTest
    static void aPartnersCustomerIsOpenAfterTheLockIn() {
        Fixture fixture = newFixture();
        LeadLogicController.portalSetting = new Partner_Portal_Setting__mdt(CP_Lock_In_Days__c = 60);
        Lead partners = channelPartnerLead('Chamari Perera', '0770000003', fixture.projectId, fixture.partnerAccountId, fixture.partner.Id);
        insert partners;
        Test.setCreatedDate(partners.Id, Datetime.now().addDays(-61));
        Lead walkIn = directLead('Chamari P', '077 000 0003', fixture.projectId, UserInfo.getUserId());

        Test.startTest();
        String refused = insertError(walkIn);
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assertEquals(null, refused, 'A new lead');
        System.assertEquals(0, [SELECT COUNT() FROM Re_Enquiry__c]);
    }

    // When Direct Sales has the customer as well as a channel partner, a repeat enquiry is a Re-Enquiry on the Direct
    // Sales lead, not on the partner's
    @isTest
    static void aRepeatEnquiryGoesToTheDirectSalesLeadNotThePartners() {
        Fixture fixture = newFixture();
        LeadLogicController.portalSetting = new Partner_Portal_Setting__mdt(CP_Lock_In_Days__c = 60);
        Lead direct = directLead('Sunil Fernando', '0771234567', fixture.projectId, fixture.directOwner.Id);
        insert direct;
        insert channelPartnerLead('Sunil F', '077 123 4567', fixture.projectId, fixture.partnerAccountId, fixture.partner.Id);
        Lead again = newLead('Sunil Fdo', '+94 77 123 4567', fixture.projectId);
        again.LeadSource = 'Digital';
        again.Lead_Sub_Source__c = 'Website Forms';

        Test.startTest();
        String refused = insertError(again);
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assertEquals('Lead already exists. Re-Enquiry has been created.', refused);
        System.assertEquals(direct.Id, [SELECT Lead__c FROM Re_Enquiry__c].Lead__c, 'On the Direct Sales lead');
    }

    // A channel partner's lead the managers rejected was never the partner's (no lead was created for them): an internal
    // lead for that customer is not a duplicate of it
    @isTest
    static void anInternalLeadIgnoresARejectedPartnerLead() {
        Fixture fixture = newFixture();
        Lead rejected = channelPartnerLead('Sunil F', '0771234567', fixture.projectId, fixture.partnerAccountId, fixture.partner.Id);
        insert rejected;
        update new Lead(Id = rejected.Id, CP_Approval_Status__c = 'Rejected');
        Lead walkIn = directLead('Sunil Fernando', '077 123 4567', fixture.projectId, UserInfo.getUserId());

        Test.startTest();
        String refused = insertError(walkIn);
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assertEquals(null, refused, 'A new lead');
        System.assertEquals(2, [SELECT COUNT() FROM Lead]);
        System.assertEquals(0, [SELECT COUNT() FROM Re_Enquiry__c], 'No Re-Enquiry on the rejected lead');
    }

    // =====================================================================================================
    // CHANNEL PARTNER LEADS
    // =====================================================================================================

    // A customer no one has yet: the channel partner's lead is saved as Assigned, with no pre-sales assignment, task or
    // assignment history, whether the portal saves it or another insert does
    @isTest
    static void aChannelPartnersNewCustomerIsCreatedAsAssigned() {
        Fixture fixture = newFixture();
        Lead inserted = channelPartnerLead('Ruwan Jayasinghe', '0770000001', fixture.projectId, fixture.partnerAccountId, fixture.partner.Id);

        Test.startTest();
        insert inserted;
        String insertedOutcome = outcomeOf(0);
        partnerWebPortalLeadController.CreateLeadResult submitted;
        System.runAs(fixture.partner) {
            submitted = submit('Dilani Wickramasinghe', 'dilani@example.com', '077 000 0002', fixture.projectId);
        }
        Test.stopTest();

        System.assertEquals(LeadLogicController.CP_CREATED, insertedOutcome);
        System.assertEquals(LeadLogicController.CP_CREATED, submitted.outcome);
        System.assertEquals(null, submitted.message);
        System.assertNotEquals(null, submitted.leadId);
        List<Id> leadIds = new List<Id>{ inserted.Id, submitted.leadId };
        List<Lead> saved = [SELECT Status, Is_User_Assigned__c, Pre_Sales_Team_Member__c, Lead_Assigned_Date_Time__c, Normalised_Phone__c,
            OwnerId, Channel_Partner__c, LeadSource FROM Lead WHERE Id IN :leadIds];
        System.assertEquals(2, saved.size());
        for (Lead record : saved) {
            System.assertEquals('Assigned', record.Status);
            System.assertEquals(false, record.Is_User_Assigned__c, 'Not a pre-sales assignment');
            System.assertEquals(null, record.Pre_Sales_Team_Member__c);
            System.assertEquals(null, record.Lead_Assigned_Date_Time__c);
            System.assertEquals(fixture.partner.Id, record.OwnerId);
            System.assertEquals(fixture.partnerAccountId, record.Channel_Partner__c);
            System.assertEquals('Channel Partner', record.LeadSource);
        }
        System.assertEquals('770000002', [SELECT Normalised_Phone__c FROM Lead WHERE Id = :submitted.leadId].Normalised_Phone__c,
            'The Sri Lankan national number, without the leading 0');
        System.assertEquals(0, [SELECT COUNT() FROM Task WHERE WhoId IN :leadIds], 'No pre-sales follow-up');
        System.assertEquals(0, [SELECT COUNT() FROM Lead_Assignment_History__c WHERE Lead__c IN :leadIds]);
    }

    // The duplicate check is Phone + Project: a mobile number Direct Sales, another channel partner or the partner
    // itself has in one project does not stop the partner's lead for another project
    @isTest
    static void theSameNumberInAnotherProjectIsANewLead() {
        Fixture fixture = newFixture();
        Id otherProjectId = newProject('Lead Logic Other Project');
        insert new List<Lead>{
            directLead('Sunil Fernando', '0771234567', fixture.projectId, fixture.directOwner.Id),
            channelPartnerLead('Chamari Perera', '0770000003', fixture.projectId, fixture.otherPartnerAccountId, UserInfo.getUserId()),
            channelPartnerLead('Ruwan Jayasinghe', '0770000001', fixture.projectId, fixture.partnerAccountId, fixture.partner.Id)
        };

        Test.startTest();
        Map<String, partnerWebPortalLeadController.CreateLeadResult> results = new Map<String, partnerWebPortalLeadController.CreateLeadResult>();
        System.runAs(fixture.partner) {
            results.put('Direct Sales\'s number', submit('Sunil F', 'sunil.f@example.com', '077 123 4567', otherProjectId));
            results.put('another partner\'s number', submit('Chamari P', 'chamari.p@example.com', '077 000 0003', otherProjectId));
            results.put('their own number', submit('Ruwan J', 'ruwan.j@example.com', '077 000 0001', otherProjectId));
        }
        Test.stopTest();

        for (String whoseNumber : results.keySet()) {
            System.assertEquals(LeadLogicController.CP_CREATED, results.get(whoseNumber).outcome, whoseNumber);
            System.assertEquals(null, results.get(whoseNumber).message, whoseNumber);
        }
        System.assertEquals(3, [SELECT COUNT() FROM Lead WHERE Project__c = :otherProjectId AND Channel_Partner__c = :fixture.partnerAccountId]);
        System.assertEquals(0, [SELECT COUNT() FROM Lead WHERE CP_Approval_Status__c != null], 'Nothing to approve');
    }

    // A channel partner's lead needs the customer's Email ID, whichever way it arrives; other leads do not
    @isTest
    static void aChannelPartnerLeadNeedsAnEmailId() {
        Fixture fixture = newFixture();
        Lead withoutEmail = channelPartnerLead('Hasini Kumari', '0779999999', fixture.projectId, fixture.partnerAccountId, fixture.partner.Id);
        withoutEmail.Email = null;
        Lead manual = directLead('Kasun Herath', '0778888888', fixture.projectId, UserInfo.getUserId());
        manual.Email = null;

        Test.startTest();
        DmlException refused;
        try {
            insert withoutEmail;
        } catch (DmlException e) {
            refused = e;
        }
        String portalRefusal;
        System.runAs(fixture.partner) {
            portalRefusal = refusal('Hasini Kumari', ' ', '0779999999', fixture.projectId);
        }
        insert manual;
        Test.stopTest();

        System.assertNotEquals(null, refused, 'Not saved');
        System.assertEquals(LeadLogicController.CP_LEAD_EMAIL_REQUIRED, refused.getDmlMessage(0));
        System.assertEquals(new List<String>{ 'Email' }, refused.getDmlFieldNames(0), 'On the Email ID field');
        System.assertEquals('Email ID is required', portalRefusal);
        System.assertEquals(0, [SELECT COUNT() FROM Lead WHERE Channel_Partner__c = :fixture.partnerAccountId]);
        System.assertEquals(1, [SELECT COUNT() FROM Lead WHERE Id = :manual.Id], 'An internal lead may have no Email ID');
    }

    // The same channel partner cannot submit a customer twice for a project, whichever way it arrives, even twice in
    // one insert
    @isTest
    static void theSameChannelPartnerCannotSubmitACustomerTwice() {
        Fixture fixture = newFixture();
        insert channelPartnerLead('Ruwan Jayasinghe', '0770000001', fixture.projectId, fixture.partnerAccountId, fixture.partner.Id);

        Test.startTest();
        String refused;
        System.runAs(fixture.partner) {
            refused = refusal('Ruwan J', 'ruwan.j@example.com', '077 000 0001', fixture.projectId);
        }
        String refusedOutcome = outcomeOf(0);
        List<Lead> twice = new List<Lead>{
            channelPartnerLead('Ishara Bandara', '0770000002', fixture.projectId, fixture.partnerAccountId, fixture.partner.Id),
            channelPartnerLead('Ishara B', '077-000-0002', fixture.projectId, fixture.partnerAccountId, fixture.partner.Id)
        };
        List<Database.SaveResult> results = Database.insert(twice, false);
        Test.stopTest();

        System.assertEquals(LeadLogicController.CP_LEAD_ALREADY_SUBMITTED, refused);
        System.assertEquals(LeadLogicController.CP_BLOCKED, refusedOutcome);
        System.assert(results[0].isSuccess(), String.valueOf(results[0].getErrors()));
        System.assert(!results[1].isSuccess(), 'The second lead of the insert is the same customer');
        System.assertEquals(LeadLogicController.CP_LEAD_ALREADY_SUBMITTED, results[1].getErrors()[0].getMessage());
        System.assertEquals(2, [SELECT COUNT() FROM Lead WHERE Channel_Partner__c = :fixture.partnerAccountId], 'One lead per customer');
        System.assertEquals(0, [SELECT COUNT() FROM Lead WHERE CP_Approval_Status__c != null], 'Nothing to approve');
    }

    // A customer another channel partner already submitted: the lead is still created, with the notice that the first
    // successful site visit decides whose customer it is; within one insert too
    @isTest
    static void anotherChannelPartnersCustomerIsCreatedWithANotice() {
        Fixture fixture = newFixture();
        insert channelPartnerLead('Chamari Perera', '0770000003', fixture.projectId, fixture.otherPartnerAccountId, UserInfo.getUserId());

        Test.startTest();
        partnerWebPortalLeadController.CreateLeadResult submitted;
        System.runAs(fixture.partner) {
            submitted = submit('Chamari P', 'chamari.p@example.com', '077 000 0003', fixture.projectId);
        }
        List<Lead> both = new List<Lead>{
            channelPartnerLead('Asanka Silva', '0770000004', fixture.projectId, fixture.otherPartnerAccountId, UserInfo.getUserId()),
            channelPartnerLead('Asanka S', '0770000004', fixture.projectId, fixture.partnerAccountId, fixture.partner.Id)
        };
        insert both;
        List<String> bothOutcomes = new List<String>{ outcomeOf(0), outcomeOf(1) };
        Test.stopTest();

        System.assertEquals(LeadLogicController.CP_CREATED_WITH_NOTICE, submitted.outcome);
        System.assertEquals(LeadLogicController.CP_LEAD_OTHER_CP_NOTICE, submitted.message);
        Lead created = [SELECT Status, OwnerId, Channel_Partner__c FROM Lead WHERE Id = :submitted.leadId];
        System.assertEquals('Assigned', created.Status);
        System.assertEquals(fixture.partner.Id, created.OwnerId);
        System.assertEquals(fixture.partnerAccountId, created.Channel_Partner__c);
        System.assertEquals(new List<String>{ LeadLogicController.CP_CREATED, LeadLogicController.CP_CREATED_WITH_NOTICE }, bothOutcomes);
        System.assertEquals(0, [SELECT COUNT() FROM Lead WHERE CP_Approval_Status__c != null], 'Nothing to approve between channel partners');
    }

    // A channel head and their executives are one channel partner: an executive cannot submit a customer their channel
    // head already submitted for the project, nor one waiting for the managers' approval
    @isTest
    static void aChannelPartnerTeamCannotSubmitACustomerTwice() {
        Fixture fixture = newFixture();
        Account executive = new Account(Name = 'Amal Perera', RecordTypeId = partnerPortalRegistrationController.partnerRecordTypeId(),
            Channel_Head__c = fixture.partnerAccountId);
        insert executive;
        insert directLead('Sunil Fernando', '0771234567', fixture.projectId, fixture.directOwner.Id);
        insert new List<Lead>{
            channelPartnerLead('Ruwan Jayasinghe', '0770000001', fixture.projectId, fixture.partnerAccountId, fixture.partner.Id),
            channelPartnerLead('Sunil F', '077 123 4567', fixture.projectId, fixture.partnerAccountId, fixture.partner.Id)
        };

        Test.startTest();
        String headsCustomer = insertError(channelPartnerLead('Ruwan J', '077 000 0001', fixture.projectId, executive.Id, UserInfo.getUserId()));
        String headsWaitingCustomer = insertError(channelPartnerLead('Sunil Fdo', '0771234567', fixture.projectId, executive.Id, UserInfo.getUserId()));
        Test.stopTest();

        System.assertEquals(LeadLogicController.CP_LEAD_TEAM_ALREADY_SUBMITTED, headsCustomer);
        System.assertEquals(LeadLogicController.CP_LEAD_TEAM_APPROVAL_PENDING, headsWaitingCustomer);
        System.assertEquals(0, [SELECT COUNT() FROM Lead WHERE Channel_Partner__c = :executive.Id], 'Nothing saved for the executive');
    }

    // Once another channel partner has completed a site visit with the customer (or converted the lead), the customer
    // is theirs: a new lead from a partner for the customer and project is refused
    @isTest
    static void aCustomerAnotherPartnerHasWonIsRefused() {
        Fixture fixture = newFixture();
        useVisitSettings();
        Lead visited = channelPartnerLead('Chamari Perera', '0770000003', fixture.projectId, fixture.otherPartnerAccountId, UserInfo.getUserId());
        Lead converted = channelPartnerLead('Asanka Silva', '0770000004', fixture.projectId, fixture.otherPartnerAccountId, UserInfo.getUserId());
        insert new List<Lead>{ visited, converted };
        insert newVisit(visited, 'Completed');
        convert(converted);

        Test.startTest();
        String visitedRefusal;
        String convertedRefusal;
        System.runAs(fixture.partner) {
            visitedRefusal = refusal('Chamari P', 'chamari.p@example.com', '077 000 0003', fixture.projectId);
            convertedRefusal = refusal('Asanka S', 'asanka.s@example.com', '077 000 0004', fixture.projectId);
        }
        Test.stopTest();

        System.assertEquals(LeadLogicController.CP_LEAD_OWNED_BY_OTHER_CP, visitedRefusal);
        System.assertEquals(LeadLogicController.CP_LEAD_OWNED_BY_OTHER_CP, convertedRefusal);
        System.assertEquals(0, [SELECT COUNT() FROM Lead WHERE Channel_Partner__c = :fixture.partnerAccountId]);
    }

    // CP -> CP: the customer goes to whichever channel partner completes the first successful site visit. When the other
    // partner's visit is completed, the partner's lead for the same customer and project gets the CP Lead Lost Status,
    // its visit still to happen is cancelled with the reason and the partner is emailed; the winner's lead is untouched
    @isTest
    static void theFirstCompletedSiteVisitDecidesWhoseCustomerItIs() {
        Fixture fixture = newFixture();
        useVisitSettings();
        Lead winner = channelPartnerLead('Chamari Perera', '0770000003', fixture.projectId, fixture.otherPartnerAccountId, UserInfo.getUserId());
        insert winner;
        Lead loser = channelPartnerLead('Chamari P', '077 000 0003', fixture.projectId, fixture.partnerAccountId, fixture.partner.Id);
        insert loser;
        String loserOutcome = outcomeOf(0);
        Visit__c winnersVisit = newVisit(winner, 'Upcoming');
        Visit__c losersVisit = newVisit(loser, 'Upcoming');
        insert new List<Visit__c>{ winnersVisit, losersVisit };

        Test.startTest();
        update new Visit__c(Id = winnersVisit.Id, Status__c = 'Completed');
        Test.stopTest();

        System.assertEquals(LeadLogicController.CP_CREATED_WITH_NOTICE, loserOutcome, 'Created with the notice');
        System.assertEquals('Site Visit Done by Other Agent', [SELECT Status FROM Lead WHERE Id = :loser.Id].Status);
        System.assertEquals('Assigned', [SELECT Status FROM Lead WHERE Id = :winner.Id].Status, 'The winner\'s lead is untouched');
        Visit__c cancelled = [SELECT Status__c, Reason_of_Cancellation__c FROM Visit__c WHERE Id = :losersVisit.Id];
        System.assertEquals('Cancelled', cancelled.Status__c);
        System.assertEquals(LeadLogicController.CP_LEAD_VISIT_CANCELLED_REASON, cancelled.Reason_of_Cancellation__c);
        System.assertEquals('Completed', [SELECT Status__c FROM Visit__c WHERE Id = :winnersVisit.Id].Status__c);
        System.assertEquals(1, CPLeadOwnershipNotifier.emailsSent, 'The partner who lost the customer is emailed');
        System.runAs(fixture.partner) {
            System.assertEquals(0, usableLeadsOf(fixture.partner), 'No more site visits on the lost lead');
            partnerWebPortalLeadController.LeadsResponse page = partnerWebPortalLeadController.getLeads(null, null, 1, 10);
            System.assertEquals(1, page.totalRecords, 'Still on the partner\'s Leads page');
            System.assertEquals('Site Visit Done by Other Agent', page.leads[0].stage);
        }
    }

    // The first completed visit wins even when it is not the one just completed (here one completed while the rule was
    // off); a lead of another project is another customer and is left
    @isTest
    static void anEarlierCompletedVisitStillWins() {
        Fixture fixture = newFixture();
        Lead first = channelPartnerLead('Chamari Perera', '0770000003', fixture.projectId, fixture.otherPartnerAccountId, UserInfo.getUserId());
        insert first;
        Lead later = channelPartnerLead('Chamari P', '077 000 0003', fixture.projectId, fixture.partnerAccountId, fixture.partner.Id);
        Lead otherProject = channelPartnerLead('Chamari Pe', '077 000 0003', newProject('Lead Logic Other Project'), fixture.partnerAccountId,
            fixture.partner.Id);
        insert new List<Lead>{ later, otherProject };
        // Completed yesterday, without a CP Lead Lost Status (the rule off)
        LeadLogicController.portalSetting = new Partner_Portal_Setting__mdt(Completed_Visit_Status__c = 'Completed');
        Visit__c firstVisit = newVisit(first, 'Completed');
        firstVisit.Completed_At_Date_Time__c = Datetime.now().addDays(-1);
        insert firstVisit;
        System.assertEquals('Assigned', [SELECT Status FROM Lead WHERE Id = :later.Id].Status, 'Nothing decided while the rule is off');
        useVisitSettings();
        Visit__c laterVisit = newVisit(later, 'Upcoming');
        Visit__c otherProjectVisit = newVisit(otherProject, 'Upcoming');
        insert new List<Visit__c>{ laterVisit, otherProjectVisit };

        Test.startTest();
        update new Visit__c(Id = laterVisit.Id, Status__c = 'Completed');
        Test.stopTest();

        System.assertEquals('Site Visit Done by Other Agent', [SELECT Status FROM Lead WHERE Id = :later.Id].Status,
            'The other partner completed a visit first');
        System.assertEquals('Assigned', [SELECT Status FROM Lead WHERE Id = :first.Id].Status);
        System.assertEquals('Assigned', [SELECT Status FROM Lead WHERE Id = :otherProject.Id].Status, 'Another project is another customer');
        System.assertEquals('Upcoming', [SELECT Status__c FROM Visit__c WHERE Id = :otherProjectVisit.Id].Status__c);
    }

    // Once another channel partner has won the customer, a new lead is refused even when Direct Sales also has the
    // customer (no approval is asked for)
    @isTest
    static void aCustomerAnotherPartnerWonIsRefusedEvenWhenDirectSalesHasIt() {
        Fixture fixture = newFixture();
        useVisitSettings();
        LeadLogicController.backupApproversLoaded = true;
        LeadLogicController.backupChannelPartnerApprover = fixture.partnerManager.Id;
        insert directLead('Sunil Fernando', '0771234567', fixture.projectId, fixture.directOwner.Id);
        // The other partner's lead was let through by the managers, and its site visit completed
        Lead won = channelPartnerLead('Sunil P', '0771234567', fixture.projectId, fixture.otherPartnerAccountId, UserInfo.getUserId());
        insert won;
        approveAll(won.Id);
        System.assertEquals('Assigned', [SELECT Status FROM Lead WHERE Id = :won.Id].Status, 'precondition');
        insert newVisit(won, 'Completed');

        Test.startTest();
        String refused;
        System.runAs(fixture.partner) {
            refused = refusal('Sunil F', 'sunil.f@example.com', '077 123 4567', fixture.projectId);
        }
        Test.stopTest();

        System.assertEquals(LeadLogicController.CP_LEAD_OWNED_BY_OTHER_CP, refused);
        System.assertEquals(0, [SELECT COUNT() FROM ProcessInstance WHERE Status = 'Pending'], 'No approval is asked for');
    }

    // A lead waiting for the managers is not closed while it waits; approved after another partner won the customer, it
    // is lost instead of Assigned, and its partner is emailed
    @isTest
    static void aLeadApprovedAfterAnotherPartnerWonIsClosed() {
        Fixture fixture = newFixture();
        useVisitSettings();
        LeadLogicController.backupApproversLoaded = true;
        LeadLogicController.backupChannelPartnerApprover = fixture.partnerManager.Id;
        insert directLead('Sunil Fernando', '0771234567', fixture.projectId, fixture.directOwner.Id);
        partnerWebPortalLeadController.CreateLeadResult waiting;
        System.runAs(fixture.partner) {
            waiting = submit('Sunil F', 'sunil.f@example.com', '077 123 4567', fixture.projectId);
        }
        Lead won = channelPartnerLead('Sunil P', '0771234567', fixture.projectId, fixture.otherPartnerAccountId, UserInfo.getUserId());
        insert won;
        approveAll(won.Id);
        insert newVisit(won, 'Completed');
        System.assertEquals('Pending', [SELECT CP_Approval_Status__c FROM Lead WHERE Id = :waiting.leadId].CP_Approval_Status__c,
            'Left alone while it waits');

        Test.startTest();
        approveAll(waiting.leadId);
        Test.stopTest();

        Lead approved = [SELECT Status, CP_Approval_Status__c FROM Lead WHERE Id = :waiting.leadId];
        System.assertEquals('Approved', approved.CP_Approval_Status__c);
        System.assertEquals('Site Visit Done by Other Agent', approved.Status, 'Not Assigned: the other partner won the customer');
        System.assertEquals(1, CPLeadOwnershipNotifier.emailsSent, 'The partner is emailed');
        System.runAs(fixture.partner) {
            System.assertEquals(0, usableLeadsOf(fixture.partner), 'No site visit for a lost lead');
        }
    }

    // A completed visit to another project is not a visit of the lead's project: the customer is not decided
    @isTest
    static void aVisitToAnotherProjectDoesNotDecideTheCustomer() {
        Fixture fixture = newFixture();
        useVisitSettings();
        Id otherProjectId = newProject('Lead Logic Other Project');
        Lead first = channelPartnerLead('Chamari Perera', '0770000003', fixture.projectId, fixture.otherPartnerAccountId, UserInfo.getUserId());
        insert first;
        Lead second = channelPartnerLead('Chamari P', '077 000 0003', fixture.projectId, fixture.partnerAccountId, fixture.partner.Id);
        insert second;
        Visit__c elsewhere = newVisit(first, 'Upcoming');
        elsewhere.Project__c = otherProjectId;
        insert elsewhere;

        Test.startTest();
        update new Visit__c(Id = elsewhere.Id, Status__c = 'Completed');
        Account third = new Account(Name = 'Third Channel Partner', RecordTypeId = partnerPortalRegistrationController.partnerRecordTypeId());
        insert third;
        String thirdRefusal = insertError(channelPartnerLead('Chamari Pe', '0770000003', fixture.projectId, third.Id, UserInfo.getUserId()));
        Test.stopTest();

        System.assertEquals('Assigned', [SELECT Status FROM Lead WHERE Id = :second.Id].Status, 'Still in the running');
        System.assertEquals(null, thirdRefusal, 'Nobody has won the customer for this project yet');
    }

    // A conversion settles the customer: the other partners' open leads for it are lost, however the phone was typed,
    // with their visits cancelled and their partners emailed
    @isTest
    static void convertingALeadClosesTheOtherPartnersLeads() {
        Fixture fixture = newFixture();
        useVisitSettings();
        Lead winner = channelPartnerLead('Chamari Perera', '0770000003', fixture.projectId, fixture.otherPartnerAccountId, UserInfo.getUserId());
        insert winner;
        Lead loser = channelPartnerLead('Chamari P', '+94 77 000 0003', fixture.projectId, fixture.partnerAccountId, fixture.partner.Id);
        insert loser;
        Visit__c losersVisit = newVisit(loser, 'Upcoming');
        insert losersVisit;

        Test.startTest();
        convert(winner);
        Test.stopTest();

        System.assertEquals('Site Visit Done by Other Agent', [SELECT Status FROM Lead WHERE Id = :loser.Id].Status);
        System.assertEquals('Cancelled', [SELECT Status__c FROM Visit__c WHERE Id = :losersVisit.Id].Status__c);
        System.assertEquals(1, CPLeadOwnershipNotifier.emailsSent);
    }

    // Converting the Direct Sales lead leaves a partner's lead that waits for the managers as it is (it is locked; the
    // managers decide it), and the conversion goes through
    @isTest
    static void convertingADirectSalesLeadLeavesAWaitingPartnerLead() {
        Fixture fixture = newFixture();
        useVisitSettings();
        Lead direct = directLead('Sunil Fernando', '0771234567', fixture.projectId, fixture.directOwner.Id);
        insert direct;
        partnerWebPortalLeadController.CreateLeadResult waiting;
        System.runAs(fixture.partner) {
            waiting = submit('Sunil F', 'sunil.f@example.com', '0771234567', fixture.projectId);
        }

        Test.startTest();
        convert(direct);
        Test.stopTest();

        Lead stillWaiting = [SELECT Status, CP_Approval_Status__c FROM Lead WHERE Id = :waiting.leadId];
        System.assertEquals('Pending', stillWaiting.CP_Approval_Status__c);
        System.assertEquals('New', stillWaiting.Status, 'Left to the managers');
        System.assert([SELECT IsConverted FROM Lead WHERE Id = :direct.Id].IsConverted);
    }

    // A lead whose customer went to another stays closed: completing its site visit (which marks the lead Visited) does
    // not reopen it, and the save goes through
    @isTest
    static void aLostLeadStaysClosedWhenItsVisitIsCompleted() {
        Fixture fixture = newFixture();
        useVisitSettings();
        Lead lost = channelPartnerLead('Chamari P', '0770000003', fixture.projectId, fixture.partnerAccountId, fixture.partner.Id);
        insert lost;
        update new Lead(Id = lost.Id, Status = 'Site Visit Done by Other Agent');

        Test.startTest();
        update new Lead(Id = lost.Id, Status = 'Visited');
        Test.stopTest();

        System.assertEquals('Site Visit Done by Other Agent', [SELECT Status FROM Lead WHERE Id = :lost.Id].Status);
    }

    // A channel partner's Mobile Number holds 9 to 15 digits, whichever way the lead arrives; other leads keep the
    // team's phone rule
    @isTest
    static void aChannelPartnerLeadNeedsAValidMobileNumber() {
        Fixture fixture = newFixture();
        Lead tooShort = channelPartnerLead('Hasini Kumari', '12345', fixture.projectId, fixture.partnerAccountId, fixture.partner.Id);
        Lead manual = directLead('Kasun Herath', '12345', fixture.projectId, UserInfo.getUserId());

        Test.startTest();
        DmlException refused;
        try {
            insert tooShort;
        } catch (DmlException e) {
            refused = e;
        }
        List<String> portalRefusals = new List<String>();
        System.runAs(fixture.partner) {
            for (String phone : new List<String>{ '---', '+', '077 123', '0771234567890123456', '077.123.4567x', '077.123.4567' }) {
                portalRefusals.add(refusal('Hasini Kumari', 'hasini@example.com', phone, fixture.projectId));
            }
        }
        insert manual;
        Test.stopTest();

        System.assertNotEquals(null, refused, 'Not saved');
        System.assertEquals(LeadLogicController.CP_LEAD_PHONE_INVALID, refused.getDmlMessage(0));
        System.assertEquals(new List<String>{ 'Phone' }, refused.getDmlFieldNames(0), 'On the Mobile Number');
        for (String message : portalRefusals) {
            System.assertEquals(partnerWebPortalLeadController.CP_LEAD_PHONE_INVALID, message);
        }
        System.assertEquals(0, [SELECT COUNT() FROM Lead WHERE Channel_Partner__c = :fixture.partnerAccountId]);
        System.assertEquals(1, [SELECT COUNT() FROM Lead WHERE Id = :manual.Id], 'An internal lead keeps the team\'s phone rule');
        System.assert(LeadLogicController.isPhoneNumber('+94 (77) 123-4567'));
        System.assert(!LeadLogicController.isPhoneNumber('077.123.4567'), 'The Lead phone rule allows no dots');
        System.assert(!LeadLogicController.isPhoneNumber(null));
    }

    // A lead saved without a normalised phone (as while LeadTrigger was inactive) is still found, on its phone
    @isTest
    static void aCustomerSavedWithoutANormalisedPhoneIsStillFound() {
        Fixture fixture = newFixture();
        Lead customer = channelPartnerLead('Chamari Perera', '0770000005', fixture.projectId, fixture.otherPartnerAccountId, UserInfo.getUserId());
        Lead someoneElse = channelPartnerLead('Pradeep Silva', '0770000006', fixture.projectId, fixture.otherPartnerAccountId, UserInfo.getUserId());
        insert new List<Lead>{ customer, someoneElse };
        update new List<Lead>{ new Lead(Id = customer.Id, Normalised_Phone__c = null), new Lead(Id = someoneElse.Id, Normalised_Phone__c = null) };

        Test.startTest();
        partnerWebPortalLeadController.CreateLeadResult submitted;
        System.runAs(fixture.partner) {
            submitted = submit('Chamari P', 'chamari.p@example.com', '077-000-0005', fixture.projectId);
        }
        Test.stopTest();

        System.assertEquals(null, [SELECT Normalised_Phone__c FROM Lead WHERE Id = :customer.Id].Normalised_Phone__c);
        System.assertEquals(LeadLogicController.CP_CREATED_WITH_NOTICE, submitted.outcome, 'Matched on the last 10 digits of its phone');
        System.assertEquals(LeadLogicController.CP_LEAD_OTHER_CP_NOTICE, submitted.message);
    }

    // A customer Direct Sales already has: the partner's lead is saved as Pending approval (stage New) with both
    // approvers and the Direct Sales lead, and sent for approval. The partner sees it as Pending approval but cannot
    // use it for a site visit until the Direct Sales owner's manager and the CP account owner's manager both approve;
    // then it is Assigned.
    @isTest
    static void aDirectSalesCustomerIsAssignedOnceBothManagersApprove() {
        Fixture fixture = newFixture();
        Lead direct = directLead('Sunil Fernando', '0771234567', fixture.projectId, fixture.directOwner.Id);
        insert direct;

        Test.startTest();
        partnerWebPortalLeadController.CreateLeadResult submitted;
        partnerWebPortalLeadController.LeadsResponse page;
        Integer usableWhilePending;
        System.runAs(fixture.partner) {
            submitted = submit('Sunil F', 'sunil.f@example.com', '077 123 4567', fixture.projectId);
            page = partnerWebPortalLeadController.getLeads(null, null, 1, 10);
            usableWhilePending = usableLeadsOf(fixture.partner);
        }
        Test.stopTest();

        System.assertEquals(LeadLogicController.CP_APPROVAL_REQUESTED, submitted.outcome);
        System.assertEquals(LeadLogicController.CP_LEAD_APPROVAL_NOTICE, submitted.message);
        System.assertNotEquals(null, submitted.leadId, 'The lead is saved, waiting for approval');
        Lead pending = [SELECT Status, CP_Approval_Status__c, Existing_Direct_Lead__c, Direct_Sales_Approver__c, CP_Approver__c, OwnerId,
            Channel_Partner__c, LeadSource, Email, Normalised_Phone__c, Is_User_Assigned__c FROM Lead WHERE Id = :submitted.leadId];
        System.assertEquals('New', pending.Status, 'Not Assigned until approved');
        System.assertEquals('Pending', pending.CP_Approval_Status__c);
        System.assertEquals(direct.Id, pending.Existing_Direct_Lead__c);
        System.assertEquals(fixture.directManager.Id, pending.Direct_Sales_Approver__c, 'The Direct Sales owner\'s manager');
        System.assertEquals(fixture.partnerManager.Id, pending.CP_Approver__c, 'The CP account owner\'s manager');
        System.assertEquals(fixture.partner.Id, pending.OwnerId);
        System.assertEquals(fixture.partnerAccountId, pending.Channel_Partner__c);
        System.assertEquals('Channel Partner', pending.LeadSource);
        System.assertEquals('sunil.f@example.com', pending.Email);
        System.assertEquals('771234567', pending.Normalised_Phone__c);
        System.assertEquals(false, pending.Is_User_Assigned__c, 'Not a pre-sales assignment');
        System.assertEquals('Pending', [SELECT Status FROM ProcessInstance WHERE TargetObjectId = :pending.Id].Status, 'Sent for approval');
        System.assertEquals(new Set<Id>{ fixture.directManager.Id, fixture.partnerManager.Id }, approversOf(pending.Id), 'One approval per manager');
        System.assertEquals(1, page.totalRecords, 'On the partner\'s Leads page');
        System.assertEquals(partnerWebPortalLeadController.CP_LEAD_PENDING_STAGE, page.leads[0].stage);
        System.assertEquals(0, usableWhilePending, 'No site visit while it waits');

        answer(pending.Id, fixture.directManager, 'Approve');
        pending = [SELECT Status, CP_Approval_Status__c FROM Lead WHERE Id = :pending.Id];
        System.assertEquals('Pending', pending.CP_Approval_Status__c, 'Both must approve');
        System.assertEquals('New', pending.Status);
        answer(pending.Id, fixture.partnerManager, 'Approve');

        Lead approved = [SELECT Status, CP_Approval_Status__c, OwnerId, Channel_Partner__c FROM Lead WHERE Id = :pending.Id];
        System.assertEquals('Approved', approved.CP_Approval_Status__c);
        System.assertEquals('Assigned', approved.Status);
        System.assertEquals(fixture.partner.Id, approved.OwnerId, 'Still the partner\'s lead');
        System.assertEquals('Approved', [SELECT Status FROM ProcessInstance WHERE TargetObjectId = :pending.Id].Status);
        System.runAs(fixture.partner) {
            System.assertEquals(1, usableLeadsOf(fixture.partner), 'Ready for a site visit');
            System.assertEquals('Assigned', partnerWebPortalLeadController.getLeads(null, null, 1, 10).leads[0].stage);
        }
        System.assertEquals(1, [SELECT COUNT() FROM Lead WHERE Channel_Partner__c = :fixture.partnerAccountId], 'The same lead');
    }

    // One manager rejecting is enough: the lead stays Rejected, nothing is left for the other manager, and the partner
    // no longer sees it. Submitting the customer again asks the managers again.
    @isTest
    static void aDirectSalesCustomerStaysRejectedWhenAManagerRejects() {
        Fixture fixture = newFixture();
        insert directLead('Sunil Fernando', '0771234567', fixture.projectId, fixture.directOwner.Id);

        Test.startTest();
        partnerWebPortalLeadController.CreateLeadResult submitted;
        System.runAs(fixture.partner) {
            submitted = submit('Sunil F', 'sunil.f@example.com', '0771234567', fixture.projectId);
        }
        Test.stopTest();

        answer(submitted.leadId, fixture.partnerManager, 'Reject');

        System.assertEquals(LeadLogicController.CP_APPROVAL_REQUESTED, submitted.outcome);
        Lead rejected = [SELECT Status, CP_Approval_Status__c FROM Lead WHERE Id = :submitted.leadId];
        System.assertEquals('Rejected', rejected.CP_Approval_Status__c);
        System.assertEquals('New', rejected.Status, 'Never Assigned');
        System.assertEquals('Rejected', [SELECT Status FROM ProcessInstance WHERE TargetObjectId = :submitted.leadId].Status);
        System.assertEquals(new Set<Id>(), approversOf(submitted.leadId), 'Nothing left for the Direct Sales manager');
        partnerWebPortalLeadController.CreateLeadResult again;
        System.runAs(fixture.partner) {
            System.assertEquals(0, partnerWebPortalLeadController.getLeads(null, null, 1, 10).totalRecords, 'Hidden from the partner');
            System.assertEquals(0, usableLeadsOf(fixture.partner));
            again = submit('Sunil F', 'sunil.f@example.com', '0771234567', fixture.projectId);
        }
        System.assertEquals(LeadLogicController.CP_APPROVAL_REQUESTED, again.outcome, 'A new request');
    }

    // An approval nobody can give is not asked for: the lead is refused when the Direct Sales owner has no manager, or
    // when the owner of the channel partner's account has none, and no backup approver is set either
    @isTest
    static void aDirectSalesCustomerWithoutAnApproverIsRefused() {
        Fixture fixture = newFixture();
        LeadLogicController.backupApproversLoaded = true;
        Account unmanaged = new Account(Name = 'Unmanaged Channel Partner', OwnerId = fixture.ownerWithoutManager.Id,
            RecordTypeId = partnerPortalRegistrationController.partnerRecordTypeId());
        insert unmanaged;
        insert new List<Lead>{
            directLead('Kavindu Rathnayake', '0771111111', fixture.projectId, fixture.ownerWithoutManager.Id),
            directLead('Sachini Gunawardena', '0772222222', fixture.projectId, fixture.directOwner.Id)
        };

        Test.startTest();
        String ownerWithoutManager;
        System.runAs(fixture.partner) {
            ownerWithoutManager = refusal('Kavindu R', 'kavindu.r@example.com', '077 111 1111', fixture.projectId);
        }
        String ownerOutcome = outcomeOf(0);
        String accountWithoutManager = insertError(
            channelPartnerLead('Sachini G', '077 222 2222', fixture.projectId, unmanaged.Id, UserInfo.getUserId()));
        Test.stopTest();

        System.assertEquals(LeadLogicController.CP_LEAD_NO_APPROVER, ownerWithoutManager, 'The Direct Sales owner has no manager');
        System.assertEquals(LeadLogicController.CP_BLOCKED, ownerOutcome);
        System.assertEquals(LeadLogicController.CP_LEAD_NO_APPROVER, accountWithoutManager, 'The CP account\'s owner has no manager');
        System.assertEquals(0, [SELECT COUNT() FROM ProcessInstance], 'No approval is asked for');
        System.assertEquals(2, [SELECT COUNT() FROM Lead], 'Only the Direct Sales leads');
    }

    // A missing manager is replaced by the Partner Portal Setting's backup approver: the Direct Sales Manager for a
    // Direct Sales lead whose owner has no manager, the JKP CP Manager for a CP account whose owner has none
    @isTest
    static void aMissingManagerIsReplacedByTheBackupApprover() {
        Fixture fixture = newFixture();
        Account unmanaged = new Account(Name = 'Unmanaged Channel Partner', OwnerId = fixture.ownerWithoutManager.Id,
            RecordTypeId = partnerPortalRegistrationController.partnerRecordTypeId());
        insert unmanaged;
        insert new List<Lead>{
            directLead('Kavindu Rathnayake', '0771111111', fixture.projectId, fixture.ownerWithoutManager.Id),
            directLead('Sachini Gunawardena', '0772222222', fixture.projectId, fixture.ownerWithoutManager.Id)
        };
        LeadLogicController.portalSetting = new Partner_Portal_Setting__mdt(
            Direct_Sales_Manager_Username__c = fixture.directManager.Username, CP_Manager_Username__c = ' ' + fixture.partnerManager.Username + ' ');
        Lead submitted = channelPartnerLead('Kavindu R', '077 111 1111', fixture.projectId, unmanaged.Id, UserInfo.getUserId());

        Test.startTest();
        insert submitted;
        String outcome = outcomeOf(0);
        // From the portal: the partner user cannot see the backup approver's user record, the rules still find it
        LeadLogicController.backupApproversLoaded = false;
        LeadLogicController.backupDirectSalesApprover = null;
        LeadLogicController.backupChannelPartnerApprover = null;
        partnerWebPortalLeadController.CreateLeadResult fromPortal;
        System.runAs(fixture.partner) {
            fromPortal = submit('Sachini G', 'sachini.g@example.com', '077 222 2222', fixture.projectId);
        }
        Test.stopTest();

        System.assertEquals(LeadLogicController.CP_APPROVAL_REQUESTED, outcome);
        Lead pending = [SELECT CP_Approval_Status__c, Direct_Sales_Approver__c, CP_Approver__c FROM Lead WHERE Id = :submitted.Id];
        System.assertEquals('Pending', pending.CP_Approval_Status__c);
        System.assertEquals(fixture.directManager.Id, pending.Direct_Sales_Approver__c, 'The backup Direct Sales Manager');
        System.assertEquals(fixture.partnerManager.Id, pending.CP_Approver__c, 'The backup JKP CP Manager');
        System.assertEquals(new Set<Id>{ fixture.directManager.Id, fixture.partnerManager.Id }, approversOf(submitted.Id), 'Both are asked');
        System.assertEquals(LeadLogicController.CP_APPROVAL_REQUESTED, fromPortal.outcome);
        System.assertEquals(fixture.directManager.Id, [SELECT Direct_Sales_Approver__c FROM Lead WHERE Id = :fromPortal.leadId].Direct_Sales_Approver__c,
            'The backup Direct Sales Manager, found for a partner user too');
    }

    // While the lead waits for approval, the channel partner cannot submit the same customer again, whichever way the
    // first one arrived
    @isTest
    static void aCustomerWaitingForApprovalCannotBeSubmittedAgain() {
        Fixture fixture = newFixture();
        Lead direct = directLead('Sunil Fernando', '0771234567', fixture.projectId, fixture.directOwner.Id);
        insert direct;
        Lead first = channelPartnerLead('Sunil F', '077 123 4567', fixture.projectId, fixture.partnerAccountId, fixture.partner.Id);

        Test.startTest();
        insert first;
        String firstOutcome = outcomeOf(0);
        String again;
        System.runAs(fixture.partner) {
            again = refusal('Sunil Fernando', 'sunil.again@example.com', '0771234567', fixture.projectId);
        }
        String againOutcome = outcomeOf(0);
        Test.stopTest();

        System.assertEquals(LeadLogicController.CP_APPROVAL_REQUESTED, firstOutcome);
        System.assertEquals('Pending', [SELECT CP_Approval_Status__c FROM Lead WHERE Id = :first.Id].CP_Approval_Status__c);
        System.assertEquals(LeadLogicController.CP_LEAD_APPROVAL_PENDING, again);
        System.assertEquals(LeadLogicController.CP_BLOCKED, againOutcome);
        System.assertEquals(1, [SELECT COUNT() FROM Lead WHERE Channel_Partner__c = :fixture.partnerAccountId], 'Only the first lead');
        System.assertEquals(1, [SELECT COUNT() FROM ProcessInstance], 'Only the first request');
    }

    // A Direct Sales customer already converted still needs the approval, from the converted lead owner's manager
    @isTest
    static void aConvertedDirectSalesCustomerAlsoNeedsTheApproval() {
        Fixture fixture = newFixture();
        Lead direct = directLead('Sunil Fernando', '0771234567', fixture.projectId, fixture.directOwner.Id);
        insert direct;
        convert(direct);
        Lead submitted = channelPartnerLead('Sunil F', '0771234567', fixture.projectId, fixture.partnerAccountId, fixture.partner.Id);

        Test.startTest();
        insert submitted;
        Test.stopTest();

        Lead pending = [SELECT CP_Approval_Status__c, Existing_Direct_Lead__c, Direct_Sales_Approver__c FROM Lead WHERE Id = :submitted.Id];
        System.assertEquals('Pending', pending.CP_Approval_Status__c);
        System.assertEquals(direct.Id, pending.Existing_Direct_Lead__c);
        System.assertEquals(fixture.directManager.Id, pending.Direct_Sales_Approver__c, 'The converted lead owner\'s manager');
    }

    // A lead that cannot be sent for approval (here it was never saved) is not saved, with the reason
    @isTest
    static void aLeadThatCannotBeSentForApprovalIsNotSaved() {
        Lead unsent = new Lead(Id = fakeId(Lead.SObjectType, 1), LeadSource = 'Channel Partner', CP_Approval_Status__c = 'Pending');
        Lead notWaiting = new Lead(Id = fakeId(Lead.SObjectType, 2), LeadSource = 'Channel Partner');

        Test.startTest();
        LeadLogicController.submitChannelPartnerApprovals(new List<Lead>{ unsent, notWaiting });
        Test.stopTest();

        System.assert(unsent.hasErrors(), 'Not saved');
        String reason = unsent.getErrors()[0].getMessage();
        System.assert(reason.startsWith(LeadLogicController.CP_LEAD_APPROVAL_NOT_REQUESTED), reason);
        System.assert(!notWaiting.hasErrors(), 'Nothing to approve');
    }

    // The lead a partner creates is on their Leads page, found by its mobile number as typed, and in the export
    @isTest
    static void aCreatedLeadIsOnThePartnersLeadsPage() {
        Fixture fixture = newFixture();
        insert channelPartnerLead('Other Team Buyer', '0770000009', fixture.projectId, fixture.otherPartnerAccountId, UserInfo.getUserId());
        partnerWebPortalLeadController.filterOverride = (List<Partner_Portal_Lead_Filter__mdt>) JSON.deserialize(
            '[{"DeveloperName":"Active","MasterLabel":"Active","Lead_Statuses__c":"New, Assigned"}]', List<Partner_Portal_Lead_Filter__mdt>.class);

        Test.startTest();
        partnerWebPortalLeadController.CreateLeadResult submitted;
        List<partnerWebPortalLeadController.LeadFilter> chips;
        partnerWebPortalLeadController.LeadsResponse all;
        partnerWebPortalLeadController.LeadsResponse found;
        String csv;
        List<Map<String, String>> projects;
        List<Map<String, String>> budgets;
        System.runAs(fixture.partner) {
            submitted = submit('Gayan Fonseka', 'gayan@example.com', '0770000010', fixture.projectId);
            chips = partnerWebPortalLeadController.getLeadFilters();
            all = partnerWebPortalLeadController.getLeads(null, null, null, null);
            found = partnerWebPortalLeadController.getLeads('Active', '077 000 0010', 1, 10);
            csv = partnerWebPortalLeadController.exportCSV('Active', 'Gayan');
            projects = partnerWebPortalLeadController.getProjectOptions();
            budgets = partnerWebPortalLeadController.getBudgetOptions();
        }
        Test.stopTest();

        System.assertEquals(LeadLogicController.CP_CREATED, submitted.outcome);
        System.assertEquals('Active', chips[0].label);
        System.assertEquals(1, all.totalRecords, 'The partner\'s own lead, not another team\'s');
        System.assertEquals(1, found.leads.size());
        System.assertEquals(submitted.leadId, found.leads[0].leadNo);
        System.assertEquals('Assigned', found.leads[0].stage);
        System.assertEquals(2, csv.trim().split('\r\n').size(), 'The header and the lead: ' + csv);
        System.assert(csv.contains('Gayan Fonseka'), csv);
        System.assertEquals(String.valueOf(fixture.projectId), projects[0].get('value'));
        System.assert(!budgets.isEmpty());
    }

    // =====================================================================================================
    // LATER CHANGES
    // =====================================================================================================

    // A new lead in a queue is assigned when a user takes it: Assigned, the pre-sales fields, the follow-up task and
    // the assignment history
    @isTest
    static void aQueueLeadIsAssignedWhenAUserTakesIt() {
        Id projectId = newProject();
        Group queue = new Group(Name = 'Lead Logic Test Queue', Type = 'Queue');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert queue;
            insert new QueueSobject(QueueId = queue.Id, SobjectType = 'Lead');
        }
        Lead queued = directLead('Kasun Herath', '0777777777', projectId, queue.Id);
        insert queued;
        Lead inQueue = [SELECT Status, Is_User_Assigned__c FROM Lead WHERE Id = :queued.Id];

        Test.startTest();
        update new Lead(Id = queued.Id, OwnerId = UserInfo.getUserId());
        Test.stopTest();

        System.assertEquals('New', inQueue.Status, 'A queue is not an assignment');
        System.assertEquals(false, inQueue.Is_User_Assigned__c);
        Lead taken = [SELECT Status, Is_User_Assigned__c, Pre_Sales_Team_Member__c, Lead_Assigned_Date_Time__c FROM Lead WHERE Id = :queued.Id];
        System.assertEquals('Assigned', taken.Status);
        System.assert(taken.Is_User_Assigned__c);
        System.assertEquals(UserInfo.getUserId(), taken.Pre_Sales_Team_Member__c);
        System.assertNotEquals(null, taken.Lead_Assigned_Date_Time__c);
        System.assertEquals(new List<String>{ 'Contact the lead within 4 hrs' }, taskSubjectsOf(queued.Id));
        List<Lead_Assignment_History__c> history = [SELECT Lead_Assigned_To__c FROM Lead_Assignment_History__c WHERE Lead__c = :queued.Id];
        System.assertEquals(1, history.size(), 'Only the user, not the queue');
        System.assertEquals(UserInfo.getUserId(), history[0].Lead_Assigned_To__c);
    }

    // A lead that comes back to the user it was last assigned to adds no second history row for them
    @isTest
    static void aLeadBackWithItsLastUserAddsNoHistory() {
        Id projectId = newProject();
        Group queue = new Group(Name = 'Lead Logic Test Queue', Type = 'Queue');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert queue;
            insert new QueueSobject(QueueId = queue.Id, SobjectType = 'Lead');
        }
        Lead record = directLead('Ruvini Jayawardena', '0774545454', projectId, UserInfo.getUserId());
        insert record;

        Test.startTest();
        update new Lead(Id = record.Id, OwnerId = queue.Id);
        update new Lead(Id = record.Id, OwnerId = UserInfo.getUserId());
        Test.stopTest();

        List<Lead_Assignment_History__c> history = [SELECT Lead_Assigned_To__c FROM Lead_Assignment_History__c WHERE Lead__c = :record.Id];
        System.assertEquals(1, history.size(), 'Still the first assignment only');
        System.assertEquals(UserInfo.getUserId(), history[0].Lead_Assigned_To__c);
        System.assertEquals('Assigned', [SELECT Status FROM Lead WHERE Id = :record.Id].Status);
    }

    // A lead moving to Qualified gets a 'Schedule a visit' task for its owner
    @isTest
    static void aQualifiedLeadGetsAVisitToSchedule() {
        Id projectId = newProject();
        Lead record = directLead('Lahiru Perera', '0776666666', projectId, UserInfo.getUserId());
        insert record;

        Test.startTest();
        update new Lead(Id = record.Id, Status = 'Qualified');
        Test.stopTest();

        Task visit = [SELECT OwnerId, Status, Priority FROM Task WHERE WhoId = :record.Id AND Subject = 'Schedule a visit'];
        System.assertEquals(UserInfo.getUserId(), visit.OwnerId);
        System.assertEquals('Not Started', visit.Status);
        System.assertEquals('Normal', visit.Priority);
        System.assertEquals(1, [SELECT COUNT() FROM Lead_Assignment_History__c WHERE Lead__c = :record.Id], 'No new assignment without a new owner');
    }

    // A new phone number is normalised again, for the duplicate checks
    @isTest
    static void aNewPhoneNumberIsNormalisedAgain() {
        Id projectId = newProject();
        Lead record = directLead('Malini Fonseka', '0775555555', projectId, UserInfo.getUserId());
        insert record;

        Test.startTest();
        update new Lead(Id = record.Id, Phone = '+91 99999 11111');
        Test.stopTest();

        System.assertEquals('9999911111', [SELECT Normalised_Phone__c FROM Lead WHERE Id = :record.Id].Normalised_Phone__c);
    }

    // =====================================================================================================
    // HELPERS CALLED DIRECTLY
    // =====================================================================================================

    // qualifyLead decides a Contacted lead with its reason; qualifying it schedules a visit
    @isTest
    static void qualifyLeadDecidesAContactedLead() {
        Id projectId = newProject();
        Lead qualified = directLead('Priya Mendis', '0773333333', projectId, UserInfo.getUserId());
        Lead notQualified = directLead('Mahesh Kumara', '0774444444', projectId, UserInfo.getUserId());
        insert new List<Lead>{ qualified, notQualified };
        update new List<Lead>{ new Lead(Id = qualified.Id, Status = 'Contacted'), new Lead(Id = notQualified.Id, Status = 'Contacted') };

        Test.startTest();
        LeadLogicController.qualifyLead(qualified.Id, 'Qualified', 'Budget and timeline confirmed');
        LeadLogicController.qualifyLead(notQualified.Id, 'Not Qualified', 'Looking for a rental');
        Test.stopTest();

        Lead decided = [SELECT Status, Qualification_Status_Reason__c FROM Lead WHERE Id = :qualified.Id];
        System.assertEquals('Qualified', decided.Status);
        System.assertEquals('Budget and timeline confirmed', decided.Qualification_Status_Reason__c);
        System.assert(taskSubjectsOf(qualified.Id).contains('Schedule a visit'));
        decided = [SELECT Status, Qualification_Status_Reason__c FROM Lead WHERE Id = :notQualified.Id];
        System.assertEquals('Not Qualified', decided.Status);
        System.assertEquals('Looking for a rental', decided.Qualification_Status_Reason__c);
        System.assert(!taskSubjectsOf(notQualified.Id).contains('Schedule a visit'));
    }

    // qualifyLead refuses a missing lead, another decision, a missing reason, a lead that is not Contacted and a
    // decision that cannot be saved (here a reason longer than the field holds)
    @isTest
    static void qualifyLeadRefusesWhatItCannotDecide() {
        Id projectId = newProject();
        Lead assigned = directLead('Nadeesha Rajapaksa', '0772222000', projectId, UserInfo.getUserId());
        Lead deleted = directLead('Tharindu Silva', '0772222001', projectId, UserInfo.getUserId());
        Lead contacted = directLead('Sanduni Perera', '0772222002', projectId, UserInfo.getUserId());
        insert new List<Lead>{ assigned, deleted, contacted };
        delete deleted;
        update new Lead(Id = contacted.Id, Status = 'Contacted');
        String tooLong = 'x'.repeat(Lead.Qualification_Status_Reason__c.getDescribe().getLength() + 1);

        Test.startTest();
        List<Boolean> refused = new List<Boolean>{
            refusesToQualify(null, 'Qualified', 'A reason'),
            refusesToQualify(assigned.Id, 'Maybe', 'A reason'),
            refusesToQualify(assigned.Id, 'Qualified', ' '),
            refusesToQualify(assigned.Id, 'Qualified', 'Not contacted yet'),
            refusesToQualify(deleted.Id, 'Qualified', 'A reason'),
            refusesToQualify(contacted.Id, 'Qualified', tooLong)
        };
        Test.stopTest();

        System.assertEquals(new List<Boolean>{ true, true, true, true, true, true }, refused);
        Lead unchanged = [SELECT Status, Qualification_Status_Reason__c FROM Lead WHERE Id = :assigned.Id];
        System.assertEquals('Assigned', unchanged.Status);
        System.assertEquals(null, unchanged.Qualification_Status_Reason__c);
        unchanged = [SELECT Status, Qualification_Status_Reason__c FROM Lead WHERE Id = :contacted.Id];
        System.assertEquals('Contacted', unchanged.Status, 'The decision that could not be saved changes nothing');
        System.assertEquals(null, unchanged.Qualification_Status_Reason__c);
    }

    private static Boolean refusesToQualify(Id leadId, String status, String reason) {
        try {
            LeadLogicController.qualifyLead(leadId, status, reason);
            return false;
        } catch (AuraHandledException e) {
            return true;
        }
    }

    // validateLeads accepts a complete lead and names what is wrong with each of the others (each lead here has one
    // problem: a lead outside a trigger keeps only the last error added to it)
    @isTest
    static void validateLeadsNamesEachProblem() {
        Map<String, Lead> leads = new Map<String, Lead>{
            'complete' => completeLead(),
            'no name' => completeLead(),
            'one letter' => completeLead(),
            'digits only' => completeLead(),
            'no phone' => completeLead(),
            'no budget' => completeLead(),
            'no source' => completeLead(),
            'no project' => completeLead(),
            'manual, not Hot or Warm' => completeLead()
        };
        leads.get('no name').LastName = ' ';
        leads.get('one letter').LastName = 'K';
        leads.get('digits only').LastName = '12345';
        leads.get('no phone').Phone = null;
        leads.get('no budget').Budget_Aligned__c = null;
        leads.get('no source').LeadSource = null;
        leads.get('no source').Lead_Classification__c = null;
        leads.get('no project').Project__c = null;
        leads.get('manual, not Hot or Warm').Lead_Classification__c = null;

        LeadLogicController.validateLeads(leads.values());

        Map<String, String> expected = new Map<String, String>{
            'no name' => 'Please enter a valid Lead Name.',
            'one letter' => 'Please enter a valid Lead Name.',
            'digits only' => 'Please enter a valid Lead Name.',
            'no phone' => 'Please enter a valid phone number.',
            'no budget' => 'Please select a valid Budget Range.',
            'no source' => 'Please select a valid Lead Source.',
            'no project' => 'Please select the Interested Project.',
            'manual, not Hot or Warm' => 'Manually created leads must be classified as Hot or Warm.'
        };
        System.assert(!leads.get('complete').hasErrors(), String.valueOf(leads.get('complete').getErrors()));
        for (String problem : expected.keySet()) {
            System.assertEquals(new Set<String>{ expected.get(problem) }, messagesOf(leads.get(problem)), problem);
        }
    }

    // A Manual lead with every detail validateLeads checks
    private static Lead completeLead() {
        return new Lead(LastName = 'Kamal Perera', Phone = '0771234567', Budget_Aligned__c = 'Matching Budget', LeadSource = 'Manual',
            Lead_Classification__c = 'Hot', Project__c = fakeId(Project__c.SObjectType, 1));
    }

    // The duplicate checks compare the digits of the phone, the last 10 of them
    @isTest
    static void oneNumberMatchesHoweverItIsWritten() {
        // A Sri Lankan number is its 9-digit national number, with or without the 0 or the 94 / 0094 country code
        for (String written : new List<String>{ '(077) 123 4567', '0771234567', '+94 77 123 4567', '94771234567', '0094 77 123 4567', '77 123 4567',
                '+94 077 123 4567', '940771234567', '0094 077 123 4567' }) {
            System.assertEquals('771234567', LeadLogicController.normalisedPhoneOf(written), written);
        }
        // Any other number keeps its last 10 digits
        System.assertEquals('9876543210', LeadLogicController.normalisedPhoneOf('+91 98765-43210'));
        System.assertEquals('9876543210', LeadLogicController.normalisedPhoneOf('9876543210'));
        System.assertEquals('9412345678', LeadLogicController.normalisedPhoneOf('9412345678'), 'A 10-digit number starting 94 is not a country code');
        System.assertEquals('12345', LeadLogicController.normalisedPhoneOf('123-45'), 'A short number keeps all its digits');
        System.assertEquals(null, LeadLogicController.normalisedPhoneOf(' '));
        System.assertEquals(null, LeadLogicController.normalisedPhoneOf(null));

        Lead withoutPhone = new Lead(Normalised_Phone__c = '0771234567');
        LeadLogicController.normalizePhone(new List<Lead>{ withoutPhone });
        System.assertEquals(null, withoutPhone.Normalised_Phone__c, 'No phone, no normalised phone');
    }

    // Nothing to submit, nothing submitted; nothing to record or notify, nothing done
    @isTest
    static void emptyListsDoNothing() {
        System.assertEquals(0, LeadSystemOperations.submitForApproval(new List<Approval.ProcessSubmitRequest>()).size());
        LeadLogicController.createLeadHistory(new List<Lead>(), null, true);
        LeadLogicController.sendEmailToLeadOwnerOnAssignment(null);
        LeadLogicController.calculateLeadScore(new List<Lead>());
        LeadTriggerHandler.beforeInsertUpdate(new List<Lead>(), null, true, false);
        LeadTriggerHandler.afterInsertUpdate(new List<Lead>(), null, true, false);
        System.assertEquals(0, [SELECT COUNT() FROM Lead_Assignment_History__c]);
        System.assertEquals(0, [SELECT COUNT() FROM Task]);
    }
}