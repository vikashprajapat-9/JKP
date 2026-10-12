// The Lead Freezing Window and the Lead Ownership Freeze of the Lead Nurturing chart (PartnerLeadFreeze): a channel
// partner lead gets its Freezing Date when it is assigned to the partner; without a site visit done by then the nightly
// job moves it to the Partnership Queue; the partner can ask the CP Manager for more days; a lost lead's owner is frozen.
@isTest
private class PartnerLeadFreezeTest {

    private static Integer leadCount = 0;

    private static User internalUser(String alias, Id managerId) {
        return new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id,
            Alias = alias,
            LastName = 'Freeze ' + alias,
            Email = alias + '@example.com',
            Username = alias + '.' + UserInfo.getOrganizationId() + '@freeze-test.example.com',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'Asia/Colombo',
            ManagerId = managerId
        );
    }

    // The JKP CP Executive and their manager, the CP Manager
    private static List<User> cpTeam() {
        User manager = internalUser('fmanager', null);
        User executive;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert manager;
            executive = internalUser('fexec', manager.Id);
            insert executive;
        }
        return new List<User>{ executive, manager };
    }

    // The Partner Portal Setting of the tests: 60 freezing days, grace periods of 15 or 30 days
    private static void useSetting(String executiveUsername) {
        Partner_Portal_Setting__mdt setting = new Partner_Portal_Setting__mdt(
            Lead_Freeze_Days__c = 60,
            Partnership_Queue__c = 'Partnership_Queue',
            Lead_Grace_Day_Options__c = '15, 30',
            Lead_Frozen_Email_Template__c = 'CP_Lead_Frozen',
            Lead_Grace_Approved_Email_Template__c = 'CP_Lead_Grace_Approved',
            Lead_Grace_Rejected_Email_Template__c = 'CP_Lead_Grace_Rejected',
            CP_Lead_Lost_Status__c = 'Site Visit Done by Other Agent',
            Completed_Visit_Status__c = 'Completed',
            Visit_Status__c = 'Upcoming',
            Open_Visit_Statuses__c = 'Upcoming',
            CP_Executive_Username__c = executiveUsername
        );
        PartnerLeadFreeze.setting = setting;
        PartnerSiteVisitService.setting = setting;
        // No hand-over to the CP team when a visit is completed here
        PartnerLeadHandover.setting = new Partner_Portal_Setting__mdt();
        PartnerSiteVisitService.stageByAction = new Map<String, String>();
    }

    private static Id accountOf(User portalUser) {
        return [SELECT Contact.AccountId FROM User WHERE Id = :portalUser.Id].Contact.AccountId;
    }

    private static Id project() {
        Project__c project = TestRecordDefaults.project('Freeze Project', true);
        insert project;
        return project.Id;
    }

    private static Lead newLead(Id channelPartnerId, Id ownerId, Id projectId) {
        leadCount++;
        return new Lead(LastName = 'Freeze Buyer ' + leadCount, Company = 'Freeze Buyer Holdings ' + leadCount,
            Phone = '07712388' + String.valueOf(leadCount).leftPad(2, '0'), Email = 'freeze.buyer' + leadCount + '@example.com',
            LeadSource = 'Channel Partner', Budget_Aligned__c = 'Matching Budget', Project__c = projectId,
            Channel_Partner__c = channelPartnerId, OwnerId = ownerId);
    }

    private static Lead leadOf(Id leadId) {
        return [
            SELECT Id, Name, Status, OwnerId, IsConverted, CP_Approval_Status__c, Channel_Partner__c, Project__c, CP_Freeze_Date__c
            FROM Lead WHERE Id = :leadId
        ];
    }

    private static Id queueId() {
        return [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = 'Partnership_Queue'].Id;
    }

    private static String graceError(User partner, Lead record, Integer days, String reason) {
        String message;
        System.runAs(partner) {
            try {
                PartnerLeadFreeze.requestGrace(record, days, reason);
            } catch (PartnerLeadFreeze.FreezeException e) {
                message = e.getMessage();
            }
        }
        return message;
    }

    private static void decide(User approver, Id requestId, String action) {
        Id workItemId = [SELECT Id FROM ProcessInstanceWorkitem WHERE ProcessInstance.TargetObjectId = :requestId LIMIT 1].Id;
        System.runAs(approver) {
            Approval.ProcessWorkitemRequest decision = new Approval.ProcessWorkitemRequest();
            decision.setWorkitemId(workItemId);
            decision.setAction(action);
            decision.setComments(action + ' in a test');
            Approval.ProcessResult result = Approval.process(decision);
            System.assert(result.isSuccess(), String.valueOf(result.getErrors()));
        }
    }

    // A lead saved for a channel partner gets its Freezing Date (60 days on); a lead held for the managers' approval gets
    // it when approved; a lead given to a partner later gets it then
    @isTest
    static void theFreezingWindowStartsAtAssignment() {
        useSetting(null);
        User partner = PartnerPortalTestUser.create();
        Id accountId = accountOf(partner);
        Id projectId = project();
        Lead forPartner = newLead(accountId, partner.Id, projectId);
        // Not a channel partner source: kept out of the CP lead approval, waiting as it would
        Lead waiting = newLead(accountId, UserInfo.getUserId(), projectId);
        waiting.LeadSource = 'Manual';
        waiting.CP_Approval_Status__c = 'Pending';
        Lead internal = newLead(null, UserInfo.getUserId(), projectId);
        internal.LeadSource = 'Manual';
        insert new List<Lead>{ forPartner, waiting, internal };

        System.assertEquals(Date.today().addDays(60), leadOf(forPartner.Id).CP_Freeze_Date__c);
        System.assertEquals(null, leadOf(waiting.Id).CP_Freeze_Date__c, 'Not assigned while waiting for approval');
        System.assertEquals(null, leadOf(internal.Id).CP_Freeze_Date__c, 'Not a channel partner lead');

        Test.startTest();
        update new Lead(Id = waiting.Id, CP_Approval_Status__c = 'Approved');
        update new Lead(Id = internal.Id, Channel_Partner__c = accountId);
        Test.stopTest();
        System.assertEquals(Date.today().addDays(60), leadOf(waiting.Id).CP_Freeze_Date__c);
        System.assertEquals(Date.today().addDays(60), leadOf(internal.Id).CP_Freeze_Date__c);
    }

    // The nightly job: a lead past its Freezing Date without a site visit done moves to the Partnership Queue (the
    // partner is emailed and sees it read-only as Frozen); a lead with a completed visit, or still in its window, stays
    @isTest
    static void theJobFreezesLeadsWithoutASiteVisit() {
        useSetting(null);
        User partner = PartnerPortalTestUser.create();
        Id accountId = accountOf(partner);
        Id projectId = project();
        Lead lapsed = newLead(accountId, partner.Id, projectId);
        Lead visited = newLead(accountId, partner.Id, projectId);
        Lead inWindow = newLead(accountId, partner.Id, projectId);
        insert new List<Lead>{ lapsed, visited, inWindow };
        update new List<Lead>{
            new Lead(Id = lapsed.Id, CP_Freeze_Date__c = Date.today().addDays(-1)),
            new Lead(Id = visited.Id, CP_Freeze_Date__c = Date.today()),
            new Lead(Id = inWindow.Id, CP_Freeze_Date__c = Date.today().addDays(1))
        };
        insert new Visit__c(Lead__c = visited.Id, Project__c = projectId, Visit_Date__c = Date.today().addDays(-2),
            Visit_Time__c = Time.newInstance(10, 0, 0, 0), Status__c = 'Completed');

        PartnerLeadFreezeJob job = new PartnerLeadFreezeJob();
        List<Lead> due = new List<Lead>();
        Database.QueryLocatorIterator found = job.start(null).iterator();
        while (found.hasNext()) {
            due.add((Lead) found.next());
        }
        Test.startTest();
        job.execute(null, due);
        // Scheduled, it runs as a batch (nothing is left to freeze)
        job.execute((SchedulableContext) null);
        Test.stopTest();

        Id queue = queueId();
        System.assertEquals(queue, leadOf(lapsed.Id).OwnerId, 'No site visit within the window: the Partnership Queue takes it');
        System.assertEquals(partner.Id, leadOf(visited.Id).OwnerId, 'A site visit was done');
        System.assertEquals(partner.Id, leadOf(inWindow.Id).OwnerId, 'Still in its window');
        System.assertEquals(2, due.size(), 'Past or at their Freezing Date');
        System.assertEquals(1, PartnerLeadFreeze.emailsWritten, 'The partner is told');
        Lead frozen = leadOf(lapsed.Id);
        System.runAs(partner) {
            System.assertEquals(Label.Partner_Lead_Read_Only_Frozen,
                partnerWebPortalLeadEditController.readOnlyReasonOf(frozen, PartnerPortalAccess.current()));
        }

        // JKP gives the frozen lead back to the partner: a new window starts
        update new Lead(Id = lapsed.Id, OwnerId = partner.Id);
        System.assertEquals(Date.today().addDays(60), leadOf(lapsed.Id).CP_Freeze_Date__c);
    }

    // Grace period: the partner asks for more days from the Edit popup; the CP Manager approves and the Freezing Date
    // moves on (from the old date); the partner is emailed
    @isTest
    static void theCpManagerApprovesAGracePeriod() {
        List<User> team = cpTeam();
        useSetting(team[0].Username);
        User partner = PartnerPortalTestUser.create();
        Lead created = newLead(accountOf(partner), partner.Id, project());
        insert created;
        update new Lead(Id = created.Id, CP_Freeze_Date__c = Date.today().addDays(10));
        Lead record = leadOf(created.Id);

        PartnerLeadFreeze.FreezeInfo before;
        System.runAs(partner) {
            before = PartnerLeadFreeze.infoOf(record);
            PartnerLeadFreeze.requestGrace(record, 30, '  The customer is abroad until next month  ');
        }
        Partner_Access_Request__c request = [
            SELECT Id, Type__c, Status__c, Lead__c, Account__c, Extension_Days__c, Reason__c, Approver__c, Requested_By__c, Requested_Via__c
            FROM Partner_Access_Request__c WHERE Lead__c = :record.Id
        ];
        PartnerLeadFreeze.FreezeInfo waiting = PartnerLeadFreeze.infoOf(record);
        Test.startTest();
        decide(team[1], request.Id, 'Approve');
        Test.stopTest();

        System.assert(before.inWindow && before.canRequest && !before.pending, String.valueOf(before));
        System.assertEquals(new List<Integer>{ 15, 30 }, before.graceOptions);
        System.assertEquals(String.format(Label.Partner_Lead_Freeze_Note, new List<Object>{ PartnerSiteVisitService.dateText(Date.today().addDays(10)) }),
            before.note);
        System.assertEquals(PartnerLeadFreeze.GRACE, request.Type__c);
        System.assertEquals('Pending', request.Status__c);
        System.assertEquals(record.Channel_Partner__c, request.Account__c);
        System.assertEquals(30, request.Extension_Days__c);
        System.assertEquals('The customer is abroad until next month', request.Reason__c);
        System.assertEquals(team[1].Id, request.Approver__c, 'The CP Manager approves');
        System.assertEquals(partner.Id, request.Requested_By__c);
        System.assertEquals('Portal', request.Requested_Via__c);
        System.assert(waiting.pending && !waiting.canRequest, String.valueOf(waiting));
        System.assertEquals(String.format(Label.Partner_Lead_Grace_Pending, new List<Object>{ '30' }), waiting.pendingNote);
        System.assertEquals(Date.today().addDays(40), leadOf(record.Id).CP_Freeze_Date__c);
        Partner_Access_Request__c decided = [SELECT Status__c, New_End_Date__c FROM Partner_Access_Request__c WHERE Id = :request.Id];
        System.assertEquals('Approved', decided.Status__c);
        System.assertEquals(Date.today().addDays(40), decided.New_End_Date__c);
        System.assertEquals(1, PartnerLeadFreeze.emailsWritten, 'The partner is told');
    }

    // A rejected grace period leaves the Freezing Date; the partner is emailed and can ask again
    @isTest
    static void theCpManagerRejectsAGracePeriod() {
        List<User> team = cpTeam();
        useSetting(team[0].Username);
        User partner = PartnerPortalTestUser.create();
        Lead created = newLead(accountOf(partner), partner.Id, project());
        insert created;
        Lead record = leadOf(created.Id);
        System.runAs(partner) {
            PartnerLeadFreeze.requestGrace(record, 15, 'Needs more time');
        }
        Id requestId = [SELECT Id FROM Partner_Access_Request__c WHERE Lead__c = :record.Id].Id;
        Test.startTest();
        decide(team[1], requestId, 'Reject');
        Test.stopTest();

        System.assertEquals(Date.today().addDays(60), leadOf(record.Id).CP_Freeze_Date__c);
        System.assertEquals('Rejected', [SELECT Status__c FROM Partner_Access_Request__c WHERE Id = :requestId].Status__c);
        System.assertEquals(1, PartnerLeadFreeze.emailsWritten);
        System.assert(PartnerLeadFreeze.infoOf(record).canRequest, 'May ask again');
    }

    // What a grace period request needs: the lead in its window, a day option, a reason, no request waiting, a CP Manager
    @isTest
    static void refusesWhatTheGracePeriodDoesNotAllow() {
        List<User> team = cpTeam();
        useSetting(team[0].Username);
        User partner = PartnerPortalTestUser.create();
        Id accountId = accountOf(partner);
        Lead created = newLead(accountId, partner.Id, project());
        insert created;
        Lead record = leadOf(created.Id);

        System.assertEquals(Label.Partner_Lead_Grace_Days, graceError(partner, record, 20, 'Reason'));
        System.assertEquals(Label.Partner_Lead_Grace_Days, graceError(partner, record, null, 'Reason'));
        System.assertEquals(Label.Partner_Lead_Grace_Reason, graceError(partner, record, 15, '  '));
        System.assertEquals(null, graceError(partner, record, 15, 'Reason'));
        System.assertEquals(Label.Partner_Lead_Grace_Already_Asked, graceError(partner, record, 30, 'Again'));

        Lead outOfWindow = record.clone(true);
        outOfWindow.CP_Freeze_Date__c = null;
        System.assertEquals(Label.Partner_Lead_Grace_Not_Available, graceError(partner, outOfWindow, 15, 'Reason'));
        Lead lost = record.clone(true);
        lost.Status = 'Site Visit Done by Other Agent';
        System.assertEquals(Label.Partner_Lead_Grace_Not_Available, graceError(partner, lost, 15, 'Reason'));

        // Without a CP Manager (the CP Executive has none, and no CP Manager Username)
        PartnerSiteVisitService.setting = new Partner_Portal_Setting__mdt(CP_Executive_Username__c = team[1].Username);
        Lead another = newLead(accountId, partner.Id, record.Project__c);
        insert another;
        System.assertEquals(Label.Partner_Lead_Grace_No_Approver, graceError(partner, leadOf(another.Id), 15, 'Reason'));
    }

    // Lead Ownership Freeze: the owner of a lead marked as lost to another agent cannot be changed by hand
    @isTest
    static void aLostLeadKeepsItsOwner() {
        useSetting(null);
        User partner = PartnerPortalTestUser.create();
        Lead created = newLead(accountOf(partner), partner.Id, project());
        insert created;
        update new Lead(Id = created.Id, Status = 'Site Visit Done by Other Agent');

        String refused;
        try {
            update new Lead(Id = created.Id, OwnerId = UserInfo.getUserId());
        } catch (DmlException e) {
            refused = e.getDmlMessage(0);
        }
        System.assertEquals(String.format(Label.CP_Lead_Owner_Frozen, new List<Object>{ 'Site Visit Done by Other Agent' }), refused);
        System.assertEquals(partner.Id, leadOf(created.Id).OwnerId);
        update new Lead(Id = created.Id, Description = 'Other fields can still change');
    }
}