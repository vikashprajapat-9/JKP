@isTest
private class partnerWebPortalMyTeamControllerTest {

    // Answers the OneDrive token request and refuses the folder, so the folder job of the test project ends quietly
    private class OneDriveMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            if (req.getEndpoint().contains('/oauth2/')) {
                res.setStatusCode(200);
                res.setBody('{"access_token":"test-token"}');
            } else {
                res.setStatusCode(503);
                res.setBody('{"error":{"code":"serviceNotAvailable"}}');
            }
            return res;
        }
    }

    // Graph's token and folder calls, giving every new folder an id, so an executive gets their OneDrive folders
    private class GraphMock implements HttpCalloutMock {
        Integer created = 0;

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            if (req.getEndpoint().contains('/oauth2/')) {
                res.setStatusCode(200);
                res.setBody('{"access_token":"test-token"}');
            } else {
                res.setStatusCode(201);
                res.setBody(JSON.serialize(new Map<String, Object>{ 'id' => 'folder-' + (++created) }));
            }
            return res;
        }
    }

    private static Integer leadCount = 0;

    // Bookings as the org's Default setting counts them: the stages after SPA Signing, except Cancelled
    private static void countBookingsAfterSpaSigning() {
        partnerWebPortalMyTeamController.setting = new Partner_Portal_Setting__mdt(
            Bookings_After_Stage__c = 'SPA Signing', Stages_Not_Counted_As_Bookings__c = 'Cancelled');
    }

    private static Id partnerAccountOf(User partner) {
        return [SELECT Contact.AccountId FROM User WHERE Id = :partner.Id].Contact.AccountId;
    }

    private static Account channelPartner(String name, Id channelHeadId) {
        return new Account(Name = name, RecordTypeId = partnerPortalRegistrationController.partnerRecordTypeId(),
            Channel_Head__c = channelHeadId);
    }

    private static Id otherAccountTypeId() {
        for (Schema.RecordTypeInfo info : Schema.SObjectType.Account.getRecordTypeInfos()) {
            if (info.isActive() && !info.isMaster() && info.getRecordTypeId() != partnerPortalRegistrationController.partnerRecordTypeId()) {
                return info.getRecordTypeId();
            }
        }
        return null;
    }

    // A lead queue, so test leads get no assignment email, task or history
    private static Id leadQueue() {
        Group queue = new Group(Name = 'My Team Test Leads', Type = 'Queue');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert queue;
            insert new QueueSobject(QueueId = queue.Id, SobjectType = 'Lead');
        }
        return queue.Id;
    }

    // Leads the lead validation rules accept, each with its own phone so none is a duplicate
    private static List<Lead> leadsOf(Id channelPartnerId, Integer howMany, Id projectId, Id queueId) {
        List<Lead> leads = new List<Lead>();
        for (Integer i = 0; i < howMany; i++) {
            leadCount++;
            leads.add(new Lead(LastName = 'Buyer ' + leadCount, Company = 'My Team Test', Phone = '07712345' + String.valueOf(leadCount).leftPad(2, '0'),
                LeadSource = 'Channel Partner', Budget_Aligned__c = 'Matching Budget', Project__c = projectId,
                Channel_Partner__c = channelPartnerId, OwnerId = queueId, Email = 'team' + leadCount + '@example.com'));
        }
        return leads;
    }

    private static Opportunity opportunityOf(Id channelPartnerId, String stage) {
        return new Opportunity(Name = 'My Team ' + stage, StageName = stage, CloseDate = Date.today().addDays(30),
            Channel_Partner__c = channelPartnerId);
    }

    private static Id newProject() {
        Project__c project = TestRecordDefaults.project('My Team Test Project', false);
        insert project;
        return project.Id;
    }

    // A channel head adds executives once their partnership is Exclusive (their contract is signed)
    private static void makeExclusive(Id partnerAccountId) {
        update new Account(Id = partnerAccountId, Partner_Type__c = PartnerTemporaryAccess.EXCLUSIVE);
    }

    private static partnerWebPortalMyTeamController.MyTeamResponse teamAs(User partner) {
        partnerWebPortalMyTeamController.MyTeamResponse team;
        Test.setMock(HttpCalloutMock.class, new OneDriveMock());
        Test.startTest();
        System.runAs(partner) {
            team = partnerWebPortalMyTeamController.getMyTeam();
        }
        Test.stopTest();
        return team;
    }

    @isTest
    static void countsThePartnersOwnAndTheirExecutivesLeadsAndBookings() {
        countBookingsAfterSpaSigning();
        User partner = PartnerPortalTestUser.create();
        Id partnerAccountId = partnerAccountOf(partner);
        Account otherHead = channelPartner('Other Channel Head', null);
        insert otherHead;
        Account amal = channelPartner('Amal Perera', partnerAccountId);
        Account zara = channelPartner('M/s Zara Holdings', partnerAccountId);
        Account outsider = channelPartner('Another Teams Executive', otherHead.Id);
        Account customer = new Account(Name = 'A Customer', RecordTypeId = otherAccountTypeId(), Channel_Head__c = partnerAccountId);
        insert new List<Account>{ amal, zara, outsider, customer };

        Id projectId = newProject();
        Id queueId = leadQueue();
        List<Lead> leads = new List<Lead>();
        leads.addAll(leadsOf(partnerAccountId, 2, projectId, queueId));
        leads.addAll(leadsOf(amal.Id, 3, projectId, queueId));
        leads.addAll(leadsOf(zara.Id, 1, projectId, queueId));
        leads.addAll(leadsOf(outsider.Id, 2, projectId, queueId));
        insert leads;
        insert new List<Opportunity>{
            opportunityOf(partnerAccountId, 'Tranche Payment'),
            opportunityOf(partnerAccountId, 'SPA Signing'),
            opportunityOf(partnerAccountId, 'Cancelled'),
            opportunityOf(amal.Id, 'Handover'),
            opportunityOf(amal.Id, 'DLP-Active'),
            opportunityOf(zara.Id, 'Negotiation'),
            opportunityOf(outsider.Id, 'Handover')
        };

        partnerWebPortalMyTeamController.MyTeamResponse team = teamAs(partner);

        System.assertEquals(6, team.stats.totalLeads, 'The partner\'s 2 leads and their executives\' 4');
        System.assertEquals(3, team.stats.totalBookings, 'Opportunities after SPA Signing, without the cancelled one');
        System.assertEquals(2, team.stats.totalExecutives, 'Only channel partner accounts whose Channel Head is the partner');
        System.assertEquals([SELECT Name FROM User WHERE Id = :partner.Id].Name, team.partnerName);
        System.assertEquals(2, team.members.size());

        partnerWebPortalMyTeamController.TeamMember first = team.members[0];
        System.assertEquals(amal.Id, first.accountId);
        System.assertEquals('Amal Perera', first.fullName, 'Executives are in name order');
        System.assertEquals('AP', first.initials);
        System.assertEquals(3, first.leads);
        System.assertEquals(2, first.bookings);

        partnerWebPortalMyTeamController.TeamMember second = team.members[1];
        System.assertEquals('M/s Zara Holdings', second.fullName);
        System.assertEquals('MZ', second.initials, 'The first letters of the first two words, as in the portal\'s top bar');
        System.assertEquals(1, second.leads);
        System.assertEquals(0, second.bookings, 'Negotiation is before SPA Signing');
        System.assertNotEquals(first.avatarColorClass, second.avatarColorClass, 'Neighbouring cards get different colours');
    }

    @isTest
    static void aPartnerWithoutExecutivesSeesTheirOwnFigures() {
        countBookingsAfterSpaSigning();
        User partner = PartnerPortalTestUser.create();
        Id partnerAccountId = partnerAccountOf(partner);
        insert leadsOf(partnerAccountId, 1, newProject(), leadQueue());
        insert opportunityOf(partnerAccountId, 'Internal QC');

        partnerWebPortalMyTeamController.MyTeamResponse team = teamAs(partner);

        System.assertEquals(1, team.stats.totalLeads);
        System.assertEquals(1, team.stats.totalBookings);
        System.assertEquals(0, team.stats.totalExecutives);
        System.assertEquals(0, team.members.size());
    }

    @isTest
    static void aUserWithoutAPartnerAccountHasNoTeam() {
        partnerWebPortalMyTeamController.MyTeamResponse team = partnerWebPortalMyTeamController.getMyTeam();

        System.assertEquals(UserInfo.getName(), team.partnerName);
        System.assertEquals(0, team.stats.totalLeads);
        System.assertEquals(0, team.stats.totalBookings);
        System.assertEquals(0, team.stats.totalExecutives);
        System.assertEquals(0, team.members.size());
        System.assertEquals(false, team.canAddExecutive, 'No Add Executive without a partner account');
    }

    @isTest
    static void bookingsAreTheStagesAfterTheConfiguredStage() {
        countBookingsAfterSpaSigning();
        Set<String> stages = partnerWebPortalMyTeamController.bookingStages();
        System.assert(stages.contains('Tranche Payment'), String.valueOf(stages));
        System.assert(stages.contains('DLP-In-Progress'), String.valueOf(stages));
        System.assert(!stages.contains('SPA Signing'), 'The configured stage itself is not a booking yet');
        System.assert(!stages.contains('Negotiation'), 'Earlier stages are not bookings');
        System.assert(!stages.contains('Cancelled'), 'Stages not counted as bookings are left out');

        partnerWebPortalMyTeamController.setting = new Partner_Portal_Setting__mdt(
            Bookings_After_Stage__c = '  spa signing ', Stages_Not_Counted_As_Bookings__c = 'cancelled; Handover');
        stages = partnerWebPortalMyTeamController.bookingStages();
        System.assert(stages.contains('Tranche Payment'), 'Stages match in any capitals');
        System.assert(!stages.contains('Handover') && !stages.contains('Cancelled'), String.valueOf(stages));

        partnerWebPortalMyTeamController.setting = new Partner_Portal_Setting__mdt(Bookings_After_Stage__c = 'No Such Stage');
        System.assertEquals(0, partnerWebPortalMyTeamController.bookingStages().size(), 'An unknown stage counts nothing');
        partnerWebPortalMyTeamController.setting = null;
        System.assertEquals(0, partnerWebPortalMyTeamController.bookingStages().size(), 'Without the setting nothing counts');
    }

    private static List<Project__c> activeProjects(Integer howMany) {
        List<Project__c> projects = new List<Project__c>();
        for (Integer i = 1; i <= howMany; i++) {
            projects.add(TestRecordDefaults.project('Executive Project ' + i, true));
        }
        insert projects;
        return projects;
    }

    // The Partner Registration Setting of a test: who is a channel partner, the waiting and rejected statuses, and the
    // approval process executives are sent to (null: none)
    private static void useRegistrationSetting(String approvalProcess) {
        partnerPortalRegistrationController.setting = (Partner_Registration_Setting__mdt) JSON.deserialize(JSON.serialize(new Map<String, Object>{
            'DeveloperName' => 'Default',
            'MasterLabel' => 'Default',
            'Account_Record_Type__c' => 'Channel_Partner',
            'Registration_Status__c' => 'Pending',
            'Rejected_Status__c' => 'Rejected',
            'Approval_Process__c' => approvalProcess
        }), Partner_Registration_Setting__mdt.class);
    }

    // The tests that send an executive for approval need the org's approval process of channel partner accounts
    private static void useTheApprovalProcess() {
        useRegistrationSetting('Partner_Onboarding_Approval');
        System.assertEquals(1, [SELECT COUNT() FROM ProcessDefinition WHERE DeveloperName = 'Partner_Onboarding_Approval' AND TableEnumOrId = 'Account'
            AND State = 'Active'], 'These tests need the active approval process Partner Onboarding Approval on Account');
    }

    // The approver of the account's waiting request decides it
    private static void decide(Id accountId, String action, String comments) {
        ProcessInstanceWorkitem item = [SELECT Id, ActorId FROM ProcessInstanceWorkitem WHERE ProcessInstance.TargetObjectId = :accountId LIMIT 1];
        Approval.ProcessWorkitemRequest decision = new Approval.ProcessWorkitemRequest();
        decision.setWorkitemId(item.Id);
        decision.setAction(action);
        decision.setComments(comments);
        System.runAs(new User(Id = item.ActorId)) {
            Approval.ProcessResult result = Approval.process(decision);
            System.assert(result.isSuccess(), String.valueOf(result.getErrors()));
        }
    }

    // The error a partner sees for these details, or null when the executive is added
    private static String addError(String fullName, String reportingTo, String email, String phone, List<Id> projectIds) {
        try {
            partnerWebPortalMyTeamController.addExecutive(fullName, reportingTo, email, phone, projectIds);
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
        return null;
    }

    @isTest
    static void addsAnExecutiveReportingToTheLoggedInPartner() {
        useTheApprovalProcess();
        User partner = PartnerPortalTestUser.create();
        Id partnerAccountId = partnerAccountOf(partner);
        makeExclusive(partnerAccountId);
        List<Project__c> projects = activeProjects(2);
        Test.setMock(HttpCalloutMock.class, new OneDriveMock());

        Id executiveId;
        partnerWebPortalMyTeamController.MyTeamResponse team;
        System.runAs(partner) {
            Test.startTest();
            executiveId = partnerWebPortalMyTeamController.addExecutive('  Kamal   Perera ', ' Saman Silva ', ' kamal@example.com ',
                '+94771234567', new List<Id>{ projects[0].Id, projects[1].Id });
            Test.stopTest();
            team = partnerWebPortalMyTeamController.getMyTeam();
        }

        Account executive = [SELECT Name, RecordTypeId, Channel_Head__c, Field_Reporting_To__c, Email__c, Phone, OwnerId, Onboarding_Status__c
            FROM Account WHERE Id = :executiveId];
        System.assertEquals('Kamal Perera', executive.Name);
        System.assertEquals(partnerPortalRegistrationController.partnerRecordTypeId(), executive.RecordTypeId, 'A channel partner account');
        System.assertEquals(partnerAccountId, executive.Channel_Head__c, 'The partner who adds the executive is their Channel Head');
        System.assertEquals('Saman Silva', executive.Field_Reporting_To__c);
        System.assertEquals('kamal@example.com', executive.Email__c);
        System.assertEquals('+94771234567', executive.Phone);
        System.assertEquals([SELECT OwnerId FROM Account WHERE Id = :partnerAccountId].OwnerId, executive.OwnerId, 'Owned like the partner\'s own account');
        System.assertEquals(partnerPortalRegistrationController.registrationStatus(), executive.Onboarding_Status__c,
            'The executive waits for approval like a registration; no login is made');
        System.assertEquals(0, [SELECT COUNT() FROM User WHERE Contact.AccountId = :executiveId]);
        ProcessInstance request = [SELECT Status, SubmittedById, ProcessDefinition.DeveloperName FROM ProcessInstance WHERE TargetObjectId = :executiveId];
        System.assertEquals('Pending', request.Status, 'Sent for the CP Manager\'s approval, like a registration');
        System.assertEquals('Partner_Onboarding_Approval', request.ProcessDefinition.DeveloperName);
        System.assertEquals(executive.OwnerId, request.SubmittedById, 'On behalf of the account owner');

        Contact contact = [SELECT FirstName, LastName, Email, Phone, OwnerId FROM Contact WHERE AccountId = :executiveId];
        System.assertEquals('Kamal', contact.FirstName);
        System.assertEquals('Perera', contact.LastName);
        System.assertEquals('kamal@example.com', contact.Email);
        System.assertEquals('+94771234567', contact.Phone);
        System.assertEquals(executive.OwnerId, contact.OwnerId);

        Set<Id> projectsWithAccess = new Set<Id>();
        for (Project_Access__c access : [SELECT Project__c FROM Project_Access__c WHERE Account__c = :executiveId]) {
            projectsWithAccess.add(access.Project__c);
        }
        System.assertEquals(new Set<Id>{ projects[0].Id, projects[1].Id }, projectsWithAccess, 'One Project Access per chosen project');

        System.assertEquals(1, team.stats.totalExecutives, 'My Team shows the new executive');
        System.assertEquals('Kamal Perera', team.members[0].fullName);
        System.assertEquals(true, team.canAddExecutive, 'An Exclusive channel head is offered Add Executive');
    }

    // A channel head whose portal access ended (Access Denied or Terminated) cannot add executives
    @isTest
    static void aPartnerWithoutAccessCannotAddExecutives() {
        User partner = PartnerPortalTestUser.create();
        Id partnerAccountId = partnerAccountOf(partner);
        List<Project__c> projects = activeProjects(1);
        Test.setMock(HttpCalloutMock.class, new OneDriveMock());
        update new Account(Id = partnerAccountId, Partner_Type__c = 'Terminated');

        partnerWebPortalMyTeamController.MyTeamResponse team;
        String refused;
        System.runAs(partner) {
            team = partnerWebPortalMyTeamController.getMyTeam();
            refused = addError('Kamal Perera', 'Saman Silva', 'kamal@example.com', '0771234567', new List<Id>{ projects[0].Id });
        }

        System.assertEquals(false, team.canAddExecutive);
        System.assertEquals(Label.Partner_Portal_No_Access, refused);
        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Name = 'Kamal Perera']);
    }

    // During the temporary access a channel head cannot add executives: My Team offers no Add Executive and the server
    // refuses. Once the contract is signed the partnership is Exclusive, and My Team offers it.
    @isTest
    static void aChannelHeadOnTemporaryAccessCannotAddExecutives() {
        User partner = PartnerPortalTestUser.create();
        Id partnerAccountId = partnerAccountOf(partner);
        List<Project__c> projects = activeProjects(1);
        Test.setMock(HttpCalloutMock.class, new OneDriveMock());
        // Approved 5 days ago: 25 days of temporary access left
        update new Account(Id = partnerAccountId, Partner_Type__c = PartnerTemporaryAccess.TEMPORARY,
            Temporary_Access_Start_Date__c = Date.today().addDays(-5), Temporary_Access_End_Date__c = Date.today().addDays(25));

        partnerWebPortalMyTeamController.MyTeamResponse team;
        String refused;
        System.runAs(partner) {
            team = partnerWebPortalMyTeamController.getMyTeam();
            refused = addError('Kamal Perera', 'Saman Silva', 'kamal@example.com', '0771234567', new List<Id>{ projects[0].Id });
        }

        System.assertEquals(false, team.canAddExecutive, 'No Add Executive during the temporary access');
        System.assertEquals(Label.Partner_Team_Exclusive_Only, refused);
        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Name = 'Kamal Perera'], 'Nothing is saved');

        makeExclusive(partnerAccountId);
        System.runAs(partner) {
            team = partnerWebPortalMyTeamController.getMyTeam();
        }
        System.assertEquals(true, team.canAddExecutive, 'Exclusive: Add Executive is offered');
    }

    // A channel head without a Partner Type is not Exclusive either
    @isTest
    static void aChannelHeadWithoutAPartnerTypeCannotAddExecutives() {
        User partner = PartnerPortalTestUser.create();
        Id partnerAccountId = partnerAccountOf(partner);
        List<Project__c> projects = activeProjects(1);
        Test.setMock(HttpCalloutMock.class, new OneDriveMock());
        System.assertEquals(null, [SELECT Partner_Type__c FROM Account WHERE Id = :partnerAccountId].Partner_Type__c);

        partnerWebPortalMyTeamController.MyTeamResponse team;
        String refused;
        System.runAs(partner) {
            team = partnerWebPortalMyTeamController.getMyTeam();
            refused = addError('Kamal Perera', 'Saman Silva', 'kamal@example.com', '0771234567', new List<Id>{ projects[0].Id });
        }

        System.assertEquals(false, team.canAddExecutive);
        System.assertEquals(Label.Partner_Team_Exclusive_Only, refused);
        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Name = 'Kamal Perera']);
    }

    @isTest
    static void refusesExecutiveDetailsThatBreakTheRules() {
        User partner = PartnerPortalTestUser.create();
        makeExclusive(partnerAccountOf(partner));
        Project__c active = activeProjects(1)[0];
        Project__c closed = TestRecordDefaults.project('Closed Project', false);
        insert closed;
        Account existing = channelPartner('Existing Partner', null);
        existing.Email__c = 'taken@example.com';
        insert existing;
        List<Id> projectIds = new List<Id>{ active.Id };
        Test.setMock(HttpCalloutMock.class, new OneDriveMock());

        System.runAs(partner) {
            System.assertEquals('Enter the executive\'s full name.', addError('  ', 'Saman', 'kamal@example.com', '0771234567', projectIds));
            System.assertEquals('Enter who the executive reports to in the field.', addError('Kamal Perera', ' ', 'kamal@example.com', '0771234567', projectIds));
            System.assertEquals('Enter a valid email address.', addError('Kamal Perera', 'Saman', 'kamal.example.com', '0771234567', projectIds));
            System.assertEquals('Enter a valid phone number.', addError('Kamal Perera', 'Saman', 'kamal@example.com', '12345', projectIds));
            System.assertEquals('Select at least one project.', addError('Kamal Perera', 'Saman', 'kamal@example.com', '0771234567', new List<Id>()));
            System.assertEquals('A selected project is no longer available. Please choose the projects again.',
                addError('Kamal Perera', 'Saman', 'kamal@example.com', '0771234567', new List<Id>{ active.Id, closed.Id }));
            System.assertEquals('A partner or executive with this email already exists.',
                addError('Kamal Perera', 'Saman', 'TAKEN@example.com', '0771234567', projectIds));
        }
        System.assertEquals('Only channel partners can add executives.',
            addError('Kamal Perera', 'Saman', 'kamal@example.com', '0771234567', projectIds), 'An internal user has no partner account');
        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Name = 'Kamal Perera'], 'Nothing is saved');
    }

    // The OneDrive folder job runs as the partner who added the executive, who cannot see Document categories or the
    // new account: the executive must still get a folder and a Document per category
    @isTest
    static void anExecutiveAddedByAPartnerGetsTheirDocuments() {
        useTheApprovalProcess();
        User partner = PartnerPortalTestUser.create();
        makeExclusive(partnerAccountOf(partner));
        Project__c project = activeProjects(1)[0];
        Document_Master__c master = new Document_Master__c(Name = 'Account', Record_Type__c = 'Channel partner');
        insert master;
        insert new List<Document_category__c>{
            new Document_category__c(Name = 'BR, VAT Certificate', Document_Master__c = master.Id),
            new Document_category__c(Name = 'NIC, TIN and passport', Document_Master__c = master.Id)
        };
        Test.setMock(HttpCalloutMock.class, new GraphMock());

        Id executiveId;
        System.runAs(partner) {
            Test.startTest();
            executiveId = partnerWebPortalMyTeamController.addExecutive('Kamal Perera', 'Saman Silva', 'kamal@example.com', '0771234567',
                new List<Id>{ project.Id });
            Test.stopTest();
        }

        System.assertNotEquals(null, [SELECT Document_Id__c FROM Account WHERE Id = :executiveId].Document_Id__c, 'The executive got a OneDrive folder');
        System.assertEquals(2, [SELECT COUNT() FROM Document__c WHERE Account__c = :executiveId], 'and a Document per category');
        System.assertEquals('Pending', [SELECT Status FROM ProcessInstance WHERE TargetObjectId = :executiveId].Status,
            'The approval request locks the account, and the folders are still made');
    }

    // Without an approval process in the settings the executive is added as before, with nothing to approve
    @isTest
    static void anExecutiveIsAddedWithoutARequestWhenNoApprovalIsSetUp() {
        useRegistrationSetting(null);
        User partner = PartnerPortalTestUser.create();
        makeExclusive(partnerAccountOf(partner));
        Project__c project = activeProjects(1)[0];
        Test.setMock(HttpCalloutMock.class, new OneDriveMock());

        Id executiveId;
        System.runAs(partner) {
            Test.startTest();
            executiveId = partnerWebPortalMyTeamController.addExecutive('Kamal Perera', 'Saman Silva', 'kamal@example.com', '0771234567',
                new List<Id>{ project.Id });
            Test.stopTest();
        }

        System.assertEquals('Pending', [SELECT Onboarding_Status__c FROM Account WHERE Id = :executiveId].Onboarding_Status__c);
        System.assertEquals(0, [SELECT COUNT() FROM ProcessInstance WHERE TargetObjectId = :executiveId]);
    }

    // If the approval cannot be asked for, the partner is told and nothing of the executive is saved
    @isTest
    static void nothingIsSavedWhenTheApprovalCannotBeAskedFor() {
        useRegistrationSetting('No_Such_Approval_Process');
        User partner = PartnerPortalTestUser.create();
        Id partnerAccountId = partnerAccountOf(partner);
        makeExclusive(partnerAccountId);
        Project__c project = activeProjects(1)[0];
        Test.setMock(HttpCalloutMock.class, new OneDriveMock());

        String error;
        System.runAs(partner) {
            Test.startTest();
            error = addError('Kamal Perera', 'Saman Silva', 'kamal@example.com', '0771234567', new List<Id>{ project.Id });
            Test.stopTest();
        }

        System.assertEquals(Label.Partner_Team_Approval_Not_Sent, error);
        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Channel_Head__c = :partnerAccountId], 'No executive account');
        System.assertEquals(0, [SELECT COUNT() FROM Contact WHERE Email = 'kamal@example.com']);
        System.assertEquals(0, [SELECT COUNT() FROM Project_Access__c WHERE Project__c = :project.Id]);
    }

    // With Document categories, the executive's folder comes first: if OneDrive cannot make it, the partner is told and
    // nothing is saved (a later job could not give a locked account its folder)
    @isTest
    static void anExecutiveIsNotAddedWhenTheirFolderCannotBeMade() {
        useRegistrationSetting(null);
        User partner = PartnerPortalTestUser.create();
        Id partnerAccountId = partnerAccountOf(partner);
        makeExclusive(partnerAccountId);
        Project__c project = activeProjects(1)[0];
        Document_Master__c master = new Document_Master__c(Name = 'Account', Record_Type__c = 'Channel partner');
        insert master;
        insert new Document_category__c(Name = 'BR, VAT Certificate', Document_Master__c = master.Id);
        Test.setMock(HttpCalloutMock.class, new OneDriveMock());

        String error;
        System.runAs(partner) {
            Test.startTest();
            error = addError('Kamal Perera', 'Saman Silva', 'kamal@example.com', '0771234567', new List<Id>{ project.Id });
            Test.stopTest();
        }

        System.assertEquals(Label.Partner_Team_Documents_Not_Ready, error);
        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Channel_Head__c = :partnerAccountId]);
    }

    // With Document categories, the executive's Documents and their folder job are part of what is undone when the
    // approval cannot be asked for. The OneDrive folder made before anything was saved stays, empty.
    @isTest
    static void theDocumentsAreUndoneWhenTheApprovalCannotBeAskedFor() {
        useRegistrationSetting('No_Such_Approval_Process');
        User partner = PartnerPortalTestUser.create();
        Id partnerAccountId = partnerAccountOf(partner);
        makeExclusive(partnerAccountId);
        Project__c project = activeProjects(1)[0];
        Document_Master__c master = new Document_Master__c(Name = 'Account', Record_Type__c = 'Channel partner');
        insert master;
        insert new Document_category__c(Name = 'BR, VAT Certificate', Document_Master__c = master.Id);
        Test.setMock(HttpCalloutMock.class, new GraphMock());

        String error;
        System.runAs(partner) {
            Test.startTest();
            error = addError('Kamal Perera', 'Saman Silva', 'kamal@example.com', '0771234567', new List<Id>{ project.Id });
            Test.stopTest();
        }

        System.assertEquals(Label.Partner_Team_Approval_Not_Sent, error);
        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Channel_Head__c = :partnerAccountId]);
        System.assertEquals(0, [SELECT COUNT() FROM Document__c WHERE Name = 'BR, VAT Certificate']);
    }

    // The CP Manager approves the executive's request: the executive gets a login. It has no access of its own (it works
    // under its channel head's), so its Partner Type and temporary access dates stay blank.
    @isTest
    static void theCpManagerApprovesAnExecutiveWhoThenGetsALogin() {
        useTheApprovalProcess();
        User partner = PartnerPortalTestUser.create();
        makeExclusive(partnerAccountOf(partner));
        Project__c project = activeProjects(1)[0];
        Test.setMock(HttpCalloutMock.class, new OneDriveMock());
        Id executiveId;
        System.runAs(partner) {
            executiveId = partnerWebPortalMyTeamController.addExecutive('Kamal Perera', 'Saman Silva', 'kamal.approved@example.com', '0771234567',
                new List<Id>{ project.Id });
        }

        Test.startTest();
        decide(executiveId, 'Approve', null);
        Test.stopTest();

        Account executive = [
            SELECT Onboarding_Status__c, Partner_Type__c, Temporary_Access_Start_Date__c, Temporary_Access_End_Date__c
            FROM Account WHERE Id = :executiveId
        ];
        System.assertEquals('Approved', executive.Onboarding_Status__c);
        System.assertEquals(null, executive.Partner_Type__c, 'No type of its own: an executive goes by its channel head');
        System.assertEquals(null, executive.Temporary_Access_Start_Date__c);
        System.assertEquals(null, executive.Temporary_Access_End_Date__c);
        User login = [SELECT IsActive, Username FROM User WHERE Contact.AccountId = :executiveId];
        System.assertEquals(true, login.IsActive, 'The approval releases the executive\'s login');
        System.assertEquals('kamal.approved@example.com.partner', login.Username);
    }

    // The CP Manager rejects the executive's request: the executive is emailed, leaves the team, and the head can add
    // the same person again, for a new approval
    @isTest
    static void theCpManagerRejectsAnExecutiveWhoCanThenBeAddedAgain() {
        useTheApprovalProcess();
        User partner = PartnerPortalTestUser.create();
        makeExclusive(partnerAccountOf(partner));
        Project__c project = activeProjects(1)[0];
        Test.setMock(HttpCalloutMock.class, new OneDriveMock());
        Id rejectedId;
        System.runAs(partner) {
            rejectedId = partnerWebPortalMyTeamController.addExecutive('Kamal Perera', 'Saman Silva', 'kamal.rejected@example.com', '0771234567',
                new List<Id>{ project.Id });
        }

        Test.startTest();
        decide(rejectedId, 'Reject', 'Not in the field team');
        Test.stopTest();

        System.assertEquals('Rejected', [SELECT Onboarding_Status__c FROM Account WHERE Id = :rejectedId].Onboarding_Status__c);
        System.assertEquals('Rejected', [SELECT Status FROM ProcessInstance WHERE TargetObjectId = :rejectedId].Status);
        System.assertEquals(0, [SELECT COUNT() FROM User WHERE Contact.AccountId = :rejectedId], 'No login');

        partnerWebPortalMyTeamController.MyTeamResponse team;
        Id addedAgainId;
        System.runAs(partner) {
            team = partnerWebPortalMyTeamController.getMyTeam();
            addedAgainId = partnerWebPortalMyTeamController.addExecutive('Kamal Perera', 'Saman Silva', 'kamal.rejected@example.com', '0771234567',
                new List<Id>{ project.Id });
        }
        System.assertEquals(0, team.stats.totalExecutives, 'The rejected executive is no longer on the team');
        System.assertNotEquals(rejectedId, addedAgainId);
        System.assertEquals('Pending', [SELECT Status FROM ProcessInstance WHERE TargetObjectId = :addedAgainId].Status, 'Sent for approval again');
    }

    // A rejected executive leaves the team and does not keep the email: the head can add the person again
    @isTest
    static void aRejectedExecutiveLeavesTheTeamAndCanBeAddedAgain() {
        useRegistrationSetting(null);
        User partner = PartnerPortalTestUser.create();
        Id partnerAccountId = partnerAccountOf(partner);
        makeExclusive(partnerAccountId);
        Project__c project = activeProjects(1)[0];
        Test.setMock(HttpCalloutMock.class, new OneDriveMock());
        Id rejectedId;
        System.runAs(partner) {
            rejectedId = partnerWebPortalMyTeamController.addExecutive('Kamal Perera', 'Saman Silva', 'kamal@example.com', '0771234567',
                new List<Id>{ project.Id });
        }
        update new Account(Id = rejectedId, Onboarding_Status__c = 'Rejected');

        partnerWebPortalMyTeamController.MyTeamResponse afterRejection;
        partnerWebPortalMyTeamController.MyTeamResponse afterAddingAgain;
        Id addedAgainId;
        System.runAs(partner) {
            Test.startTest();
            afterRejection = partnerWebPortalMyTeamController.getMyTeam();
            addedAgainId = partnerWebPortalMyTeamController.addExecutive('Kamal Perera', 'Saman Silva', 'kamal@example.com', '0771234567',
                new List<Id>{ project.Id });
            afterAddingAgain = partnerWebPortalMyTeamController.getMyTeam();
            Test.stopTest();
        }

        System.assertEquals(0, afterRejection.stats.totalExecutives, 'The rejected executive is no longer on the team');
        System.assertNotEquals(rejectedId, addedAgainId, 'Added again as a new account');
        System.assertEquals(1, afterAddingAgain.stats.totalExecutives);
        System.assertEquals('Rejected', [SELECT Onboarding_Status__c FROM Account WHERE Id = :rejectedId].Onboarding_Status__c, 'The earlier one stays rejected');
    }

    // An executive is onboarded by their channel head: they have no team and cannot add executives, even when they and
    // their channel head are Exclusive
    @isTest
    static void anExecutiveHasNoTeamAndCannotAddExecutives() {
        Test.setMock(HttpCalloutMock.class, new OneDriveMock());
        List<Project__c> projects = activeProjects(2);
        Project__c given = projects[0];
        User executive = PartnerPortalTestUser.createExecutive(new List<Id>{ given.Id });
        Id executiveAccountId = partnerAccountOf(executive);
        makeExclusive([SELECT Channel_Head__c FROM Account WHERE Id = :executiveAccountId].Channel_Head__c);
        makeExclusive(executiveAccountId);

        partnerWebPortalMyTeamController.MyTeamResponse team;
        List<partnerWebPortalProjectController.ProjectTile> projectChoices;
        String refused;
        System.runAs(executive) {
            team = partnerWebPortalMyTeamController.getMyTeam();
            projectChoices = partnerWebPortalProjectController.getProjects();
            refused = addError('Kamal Perera', 'Saman Silva', 'kamal@example.com', '0771234567', new List<Id>{ given.Id });
        }

        System.assertEquals(0, team.stats.totalExecutives);
        System.assertEquals(0, team.members.size());
        System.assertEquals(false, team.canAddExecutive, 'No Add Executive for an executive');
        System.assertEquals(1, projectChoices.size(), 'The Add Executive form\'s projects: only their own');
        System.assertEquals(given.Id, projectChoices[0].id);
        System.assertEquals('Only channel heads can add executives.', refused);
        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Name = 'Kamal Perera']);
    }
}