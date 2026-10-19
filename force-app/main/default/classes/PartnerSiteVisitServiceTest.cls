// Site visit requests of the Lead Nurturing chart (PartnerSiteVisitService), as the portal and the approvers run them:
// a partner's request (for the lead's project) goes to the JKP CP Executive; approved, it is scheduled and the lead
// moves to Site Visit Scheduled; rejected, it goes to the CP Manager, whose rejection ends it; and the partner marks a
// scheduled visit completed, which moves the lead to Visited.
@isTest
private class PartnerSiteVisitServiceTest {

    private static Integer leadCount = 0;

    // The JKP CP Executive and their manager, the CP Manager
    private class Approvers {
        User executive;
        User manager;
    }

    private static Approvers approvers() {
        Approvers result = new Approvers();
        result.manager = internalUser('vmanager', null);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert result.manager;
            result.executive = internalUser('vexec', result.manager.Id);
            insert result.executive;
        }
        return result;
    }

    private static User internalUser(String alias, Id managerId) {
        return new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id,
            Alias = alias,
            LastName = 'Visit ' + alias,
            Email = alias + '@example.com',
            Username = alias + '.' + UserInfo.getOrganizationId() + '@visit-test.example.com',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'Asia/Colombo',
            ManagerId = managerId
        );
    }

    // The Partner Portal Setting of the tests: the CP Executive is the given user (null: the partner account's owner)
    private static void useSetting(String executiveUsername, String managerUsername) {
        PartnerSiteVisitService.setting = new Partner_Portal_Setting__mdt(
            Visit_Status__c = 'Upcoming',
            Visit_Request_Status__c = 'Requested',
            Visit_Rejected_Status__c = 'Rejected',
            Open_Visit_Statuses__c = 'Upcoming',
            Completed_Visit_Status__c = 'Completed',
            Cancelled_Visit_Status__c = 'Cancelled',
            CP_Lead_Lost_Status__c = 'Site Visit Done by Other Agent',
            Visit_Confirmed_Email_Template__c = 'Partner_Portal_Site_Visit_Confirmed',
            Visit_Rejected_Email_Template__c = 'Partner_Portal_Site_Visit_Rejected',
            CP_Executive_Username__c = executiveUsername,
            CP_Manager_Username__c = managerUsername
        );
        // Keyed in small letters, as the class reads its records
        PartnerSiteVisitService.stageByAction = new Map<String, String>{ 'request' => 'Site Visit Scheduled', 'complete' => 'Visited' };
    }

    private static Id accountOf(User portalUser) {
        return [SELECT Contact.AccountId FROM User WHERE Id = :portalUser.Id].Contact.AccountId;
    }

    private static Id project() {
        Project__c project = TestRecordDefaults.project('Visit Request Project', true);
        insert project;
        return project.Id;
    }

    // A channel partner lead of the account, owned by the partner
    private static Lead leadOf(Id channelPartnerId, Id ownerId, Id projectId) {
        leadCount++;
        Lead record = new Lead(LastName = 'Visit Buyer ' + leadCount, Company = 'Visit Buyer Holdings ' + leadCount,
            Phone = '07712377' + String.valueOf(leadCount).leftPad(2, '0'), Email = 'visit.buyer' + leadCount + '@example.com',
            LeadSource = 'Channel Partner', Budget_Aligned__c = 'Matching Budget', Project__c = projectId,
            Channel_Partner__c = channelPartnerId, OwnerId = ownerId);
        insert record;
        return [SELECT Id, Status, OwnerId, IsConverted, CP_Approval_Status__c, Channel_Partner__c, Project__c FROM Lead WHERE Id = :record.Id];
    }

    private static String requirementType() {
        return PartnerSiteVisitService.requirementTypes()[0].get('value');
    }

    // The partner asks for a visit of the lead on the day, late in the evening (a time still ahead today)
    private static Visit__c request(User partner, Lead record, Date day) {
        Visit__c visit;
        System.runAs(partner) {
            visit = PartnerSiteVisitService.request(record, record.Project__c, requirementType(), day, LATE, ' Family of 4 ');
        }
        return visit;
    }

    private static final Time LATE = Time.newInstance(23, 59, 0, 0);

    // The visit's time has come (it is moved to midnight of its day)
    private static void timeHasCome(Id visitId) {
        update new Visit__c(Id = visitId, Visit_Time__c = Time.newInstance(0, 0, 0, 0));
    }

    // The approver's decision on the visit's open approval request
    private static void decide(User approver, Id visitId, String action) {
        Id workItemId = [SELECT Id FROM ProcessInstanceWorkitem WHERE ProcessInstance.TargetObjectId = :visitId LIMIT 1].Id;
        System.runAs(approver) {
            Approval.ProcessWorkitemRequest decision = new Approval.ProcessWorkitemRequest();
            decision.setWorkitemId(workItemId);
            decision.setAction(action);
            decision.setComments(action + ' in a test');
            Approval.ProcessResult result = Approval.process(decision);
            System.assert(result.isSuccess(), String.valueOf(result.getErrors()));
        }
    }

    private static Visit__c visitOf(Id visitId) {
        return [
            SELECT Status__c, Approval_Status__c, CP_Executive_Approver__c, CP_Manager_Approver__c, Lead__c, Channel_Partner__c, Project__c,
                Requirement_Type__c, Visit_Date__c, Visit_Time__c, Visit_Description__c, OwnerId
            FROM Visit__c WHERE Id = :visitId
        ];
    }

    private static Id pendingApproverOf(Id visitId) {
        List<ProcessInstanceWorkitem> items = [SELECT ActorId FROM ProcessInstanceWorkitem WHERE ProcessInstance.TargetObjectId = :visitId];
        return items.isEmpty() ? null : items[0].ActorId;
    }

    // The request waits for the JKP CP Executive; approved, the visit is scheduled and the lead moves to Site Visit
    // Scheduled
    @isTest
    static void theCpExecutiveApprovesARequest() {
        Approvers people = approvers();
        useSetting(people.executive.Username, null);
        User partner = PartnerPortalTestUser.create();
        Lead record = leadOf(accountOf(partner), partner.Id, project());

        Visit__c requested = request(partner, record, Date.today().addDays(2));
        Visit__c waiting = visitOf(requested.Id);
        String leadStageWhileWaiting = [SELECT Status FROM Lead WHERE Id = :record.Id].Status;
        Id approverAsked = pendingApproverOf(requested.Id);
        Test.startTest();
        decide(people.executive, requested.Id, 'Approve');
        Test.stopTest();

        System.assertEquals('Requested', waiting.Status__c);
        System.assertEquals(PartnerSiteVisitService.PENDING_EXECUTIVE, waiting.Approval_Status__c);
        System.assertEquals(people.executive.Id, waiting.CP_Executive_Approver__c, 'The setting\'s CP Executive');
        System.assertEquals(people.manager.Id, waiting.CP_Manager_Approver__c, 'The CP Executive\'s manager');
        System.assertEquals(partner.Id, waiting.OwnerId);
        System.assertEquals(record.Channel_Partner__c, waiting.Channel_Partner__c);
        System.assertEquals(requirementType(), waiting.Requirement_Type__c);
        System.assertEquals(LATE, waiting.Visit_Time__c);
        System.assertEquals('Family of 4', waiting.Visit_Description__c);
        System.assertEquals(people.executive.Id, approverAsked, 'The CP Executive is asked first');
        System.assertEquals('Assigned', leadStageWhileWaiting, 'The lead keeps its stage until the visit is approved');

        Visit__c approved = visitOf(requested.Id);
        System.assertEquals(PartnerSiteVisitService.APPROVED, approved.Approval_Status__c);
        System.assertEquals('Upcoming', approved.Status__c, 'The setting\'s Visit Status');
        System.assertEquals('Site Visit Scheduled', [SELECT Status FROM Lead WHERE Id = :record.Id].Status);
        System.assertEquals(1, PartnerSiteVisitService.emailsWritten, 'The partner is told the visit is confirmed');
        String email = PartnerSiteVisitService.emailBodies[0];
        String customer = [SELECT Name FROM Lead WHERE Id = :record.Id].Name;
        // The email is written as the approver: the day and the time read as that user's locale writes them
        String day;
        String hour;
        System.runAs(people.executive) {
            day = PartnerSiteVisitService.dateText(Date.today().addDays(2));
            hour = PartnerSiteVisitService.timeText(LATE);
        }
        System.assert(email.contains(customer) && !email.contains(customer + ','), 'The customer by name, without the company: ' + email);
        System.assert(email.containsIgnoreCase(day), 'The day of the visit: ' + email);
        System.assert(email.containsIgnoreCase(hour), 'The time of the visit: ' + email);
        System.assert(!email.contains('[['), 'Nothing is left for Apex to fill in: ' + email);
    }

    // Rejected by the CP Executive, the request goes to the CP Manager; the CP Manager approves it
    @isTest
    static void theCpManagerApprovesWhatTheCpExecutiveRejected() {
        Approvers people = approvers();
        useSetting(people.executive.Username, null);
        User partner = PartnerPortalTestUser.create();
        Lead record = leadOf(accountOf(partner), partner.Id, project());
        Visit__c requested = request(partner, record, Date.today().addDays(2));

        Test.startTest();
        decide(people.executive, requested.Id, 'Reject');
        Test.stopTest();
        Visit__c escalated = visitOf(requested.Id);
        Id approverAsked = pendingApproverOf(requested.Id);
        String leadStageAfterRejection = [SELECT Status FROM Lead WHERE Id = :record.Id].Status;
        decide(people.manager, requested.Id, 'Approve');

        System.assertEquals(PartnerSiteVisitService.PENDING_MANAGER, escalated.Approval_Status__c);
        System.assertEquals('Requested', escalated.Status__c, 'Still a request');
        System.assertEquals(people.manager.Id, approverAsked, 'Now the CP Manager is asked');
        System.assertEquals('Assigned', leadStageAfterRejection);
        Visit__c approved = visitOf(requested.Id);
        System.assertEquals(PartnerSiteVisitService.APPROVED, approved.Approval_Status__c);
        System.assertEquals('Upcoming', approved.Status__c);
        System.assertEquals('Site Visit Scheduled', [SELECT Status FROM Lead WHERE Id = :record.Id].Status);
    }

    // Rejected by both, the request is rejected and the lead keeps its stage; the partner can ask again
    @isTest
    static void aRequestBothRejectEnds() {
        Approvers people = approvers();
        useSetting(people.executive.Username, null);
        User partner = PartnerPortalTestUser.create();
        Lead record = leadOf(accountOf(partner), partner.Id, project());
        Visit__c requested = request(partner, record, Date.today().addDays(2));

        Test.startTest();
        decide(people.executive, requested.Id, 'Reject');
        Test.stopTest();
        decide(people.manager, requested.Id, 'Reject');
        String blockedAfter;
        System.runAs(partner) {
            blockedAfter = PartnerSiteVisitService.blockedReason(record.Id);
        }

        Visit__c rejected = visitOf(requested.Id);
        System.assertEquals(PartnerSiteVisitService.REJECTED, rejected.Approval_Status__c);
        System.assertEquals('Rejected', rejected.Status__c, 'The setting\'s Visit Rejected Status');
        System.assertEquals('Assigned', [SELECT Status FROM Lead WHERE Id = :record.Id].Status);
        System.assertEquals(null, pendingApproverOf(requested.Id), 'Nobody is asked any more');
        System.assertEquals(null, blockedAfter, 'A rejected request does not stop a new one');
        System.assertEquals(1, PartnerSiteVisitService.emailBodies.size(), 'Only the final rejection is emailed');
        String email = PartnerSiteVisitService.emailBodies[0];
        System.assert(email.contains('Reject in a test'), 'The approver\'s reason: ' + email);
        System.assert(!email.contains('[['), 'Nothing is left for Apex to fill in: ' + email);
    }

    // A request that cannot go to the CP Manager (no CP Manager any more) is rejected instead of waiting for nobody
    @isTest
    static void aRequestWithoutCpManagerIsRejected() {
        Approvers people = approvers();
        useSetting(people.executive.Username, null);
        User partner = PartnerPortalTestUser.create();
        Lead record = leadOf(accountOf(partner), partner.Id, project());
        Visit__c requested = request(partner, record, Date.today().addDays(2));
        update new Visit__c(Id = requested.Id, CP_Manager_Approver__c = null);

        Test.startTest();
        decide(people.executive, requested.Id, 'Reject');
        Test.stopTest();

        Visit__c rejected = visitOf(requested.Id);
        System.assertEquals(PartnerSiteVisitService.REJECTED, rejected.Approval_Status__c);
        System.assertEquals('Rejected', rejected.Status__c);
        System.assertEquals(null, pendingApproverOf(requested.Id));
    }

    // While a request waits or a visit is scheduled, the lead cannot have another; the partner marks the scheduled visit
    // completed from its day on, and the lead moves to Visited
    @isTest
    static void thePartnerCompletesAScheduledVisit() {
        Approvers people = approvers();
        useSetting(people.executive.Username, null);
        User partner = PartnerPortalTestUser.create();
        Lead record = leadOf(accountOf(partner), partner.Id, project());
        Visit__c today = request(partner, record, Date.today());
        String whileWaiting = PartnerSiteVisitService.blockedReason(record.Id);
        Test.startTest();
        decide(people.executive, today.Id, 'Approve');
        Test.stopTest();
        String whileScheduled = PartnerSiteVisitService.blockedReason(record.Id);
        timeHasCome(today.Id);
        String secondRequest;
        String unknownVisit;
        System.runAs(partner) {
            try {
                PartnerSiteVisitService.request(record, record.Project__c, requirementType(), Date.today().addDays(5), Time.newInstance(9, 0, 0, 0), null);
            } catch (PartnerSiteVisitService.VisitException e) {
                secondRequest = e.getMessage();
            }
            try {
                PartnerSiteVisitService.complete(record, record.Id);
            } catch (PartnerSiteVisitService.VisitException e) {
                unknownVisit = e.getMessage();
            }
            PartnerSiteVisitService.complete(record, today.Id);
        }

        System.assertEquals(PartnerSiteVisitService.PARTNER_VISIT_REQUEST_PENDING, whileWaiting);
        System.assertEquals(String.format(PartnerSiteVisitService.PARTNER_VISIT_ALREADY_SCHEDULED, new List<Object>{ PartnerSiteVisitService.dateText(Date.today()) }),
            whileScheduled);
        System.assertEquals(whileScheduled, secondRequest);
        System.assertEquals(PartnerSiteVisitService.PARTNER_VISIT_CHOOSE_VISIT, unknownVisit);
        System.assertEquals('Completed', visitOf(today.Id).Status__c);
        System.assertEquals('Visited', [SELECT Status FROM Lead WHERE Id = :record.Id].Status);
        System.assertEquals(null, PartnerSiteVisitService.blockedReason(record.Id), 'A completed visit does not stop a new request');
    }

    // A visit still ahead cannot be completed yet; nor can a past day be requested, or a request without what it needs
    @isTest
    static void refusesWhatTheChartDoesNotAllow() {
        Approvers people = approvers();
        useSetting(people.executive.Username, null);
        User partner = PartnerPortalTestUser.create();
        Lead record = leadOf(accountOf(partner), partner.Id, project());
        Visit__c ahead = new Visit__c(Lead__c = record.Id, Status__c = 'Upcoming', Visit_Date__c = Date.today().addDays(3), OwnerId = partner.Id);
        Lead other = leadOf(accountOf(partner), partner.Id, record.Project__c);

        Map<String, String> refusals = new Map<String, String>();
        Test.startTest();
        insert ahead;
        System.runAs(partner) {
            refusals.put('not yet', completeError(record, ahead.Id));
            refusals.put('past day', requestError(other, record.Project__c, requirementType(), Date.today().addDays(-1), Time.newInstance(9, 0, 0, 0)));
            refusals.put('no project', requestError(other, null, requirementType(), Date.today(), Time.newInstance(9, 0, 0, 0)));
            refusals.put('no type', requestError(other, record.Project__c, ' ', Date.today(), Time.newInstance(9, 0, 0, 0)));
            refusals.put('unknown type', requestError(other, record.Project__c, 'Castle', Date.today(), Time.newInstance(9, 0, 0, 0)));
            refusals.put('no date', requestError(other, record.Project__c, requirementType(), null, Time.newInstance(9, 0, 0, 0)));
            refusals.put('no time', requestError(other, record.Project__c, requirementType(), Date.today(), null));
        }
        Test.stopTest();

        System.assertEquals(String.format(PartnerSiteVisitService.PARTNER_VISIT_NOT_YET, new List<Object>{ PartnerSiteVisitService.dateText(Date.today().addDays(3)) }),
            refusals.get('not yet'));
        System.assertEquals(PartnerSiteVisitService.PARTNER_VISIT_DATE_PAST, refusals.get('past day'));
        System.assertEquals(required(Visit__c.Project__c), refusals.get('no project'));
        System.assertEquals(required(Visit__c.Requirement_Type__c), refusals.get('no type'));
        System.assertEquals(required(Visit__c.Requirement_Type__c), refusals.get('unknown type'));
        System.assertEquals(required(Visit__c.Visit_Date__c), refusals.get('no date'));
        System.assertEquals(required(Visit__c.Visit_Time__c), refusals.get('no time'));
        System.assertEquals('Upcoming', visitOf(ahead.Id).Status__c);
        System.assertEquals(1, [SELECT COUNT() FROM Visit__c], 'No request saved');
    }

    // A lead's site visits are for the project it was created for: another project is refused, and so is the lead's own
    // project once it is no longer open for site visits (not active). An old lead without a project takes the project the
    // partner chose.
    @isTest
    static void aVisitIsForTheLeadsOwnProject() {
        Approvers people = approvers();
        useSetting(people.executive.Username, null);
        User partner = PartnerPortalTestUser.create();
        Id accountId = accountOf(partner);
        Id projectId = project();
        Project__c other = TestRecordDefaults.project('Other Visit Project', true);
        insert other;
        Lead record = leadOf(accountId, partner.Id, projectId);
        Lead closing = leadOf(accountId, partner.Id, other.Id);
        // A lead from before leads needed a project (the Project is mandatory rule no longer lets one be saved without)
        Lead withoutProject = new Lead(Id = leadOf(accountId, partner.Id, projectId).Id, Channel_Partner__c = accountId);
        Date day = Date.today().addDays(1);

        String anotherProject;
        Visit__c leadsProject;
        Visit__c chosenProject;
        String notOpen;
        Test.startTest();
        System.runAs(partner) {
            anotherProject = requestError(record, other.Id, requirementType(), day, LATE);
            leadsProject = PartnerSiteVisitService.request(record, record.Project__c, requirementType(), day, LATE, null);
            chosenProject = PartnerSiteVisitService.request(withoutProject, other.Id, requirementType(), day, LATE, null);
        }
        update new Project__c(Id = other.Id, Active__c = false);
        System.runAs(partner) {
            notOpen = requestError(closing, closing.Project__c, requirementType(), day, LATE);
        }
        Test.stopTest();

        System.assertEquals(String.format(PartnerSiteVisitService.PARTNER_VISIT_PROJECT_NOT_LEAD, new List<Object>{ 'Visit Request Project' }), anotherProject);
        System.assertEquals(projectId, visitOf(leadsProject.Id).Project__c, 'The lead\'s project');
        System.assertEquals(other.Id, visitOf(chosenProject.Id).Project__c, 'A lead without a project: the project the partner chose');
        System.assertEquals(String.format(PartnerSiteVisitService.PARTNER_VISIT_PROJECT_NOT_OPEN, new List<Object>{ 'Other Visit Project' }), notOpen);
        System.assertEquals(0, [SELECT COUNT() FROM Visit__c WHERE Lead__c = :closing.Id], 'No request for a project not open for site visits');
        System.assertEquals(null, PartnerSiteVisitService.projectNotOpenReason(null), 'Without a project');
    }

    // The CP Executive is the setting's, else the partner account's owner; the CP Manager the CP Executive's manager,
    // else the setting's; without both a request cannot be sent
    @isTest
    static void findsTheApprovers() {
        Approvers people = approvers();
        User partner = PartnerPortalTestUser.create();
        Id accountId = accountOf(partner);
        Id accountOwnerId = [SELECT OwnerId FROM Account WHERE Id = :accountId].OwnerId;

        useSetting(people.executive.Username, null);
        PartnerSiteVisitService.Approvers fromSetting = PartnerSiteVisitService.approversFor(accountId);
        useSetting(people.manager.Username, people.executive.Username);
        PartnerSiteVisitService.Approvers settingManager = PartnerSiteVisitService.approversFor(accountId);
        useSetting(null, people.manager.Username);
        PartnerSiteVisitService.Approvers accountOwner = PartnerSiteVisitService.approversFor(accountId);
        useSetting('nobody@nowhere.example.com', null);
        PartnerSiteVisitService.Approvers none = PartnerSiteVisitService.approversFor(accountId);
        Lead record = leadOf(accountId, partner.Id, project());
        String refusal;
        System.runAs(partner) {
            refusal = requestError(record, record.Project__c, requirementType(), Date.today().addDays(1), Time.newInstance(9, 0, 0, 0));
        }

        System.assertEquals(people.executive.Id, fromSetting.executive);
        System.assertEquals(people.manager.Id, fromSetting.manager, 'The CP Executive\'s manager');
        System.assertEquals(people.manager.Id, settingManager.executive);
        System.assertEquals(people.executive.Id, settingManager.manager, 'The setting\'s CP Manager when the CP Executive has no manager');
        System.assertEquals(accountOwnerId, accountOwner.executive, 'The partner account\'s owner without a CP Executive setting');
        System.assertEquals(people.manager.Id, accountOwner.manager);
        System.assertEquals(null, none, 'Nobody to approve');
        System.assertEquals(PartnerSiteVisitService.PARTNER_VISIT_NO_APPROVER, refusal);
    }

    // A request approved after its lead was closed (here: lost to another partner) is cancelled, the lead stays as it is
    // and nobody is emailed
    @isTest
    static void anApprovalForAClosedLeadCancelsTheVisit() {
        Approvers people = approvers();
        useSetting(people.executive.Username, null);
        User partner = PartnerPortalTestUser.create();
        Lead record = leadOf(accountOf(partner), partner.Id, project());
        Visit__c requested = request(partner, record, Date.today().addDays(2));
        update new Lead(Id = record.Id, Status = 'Site Visit Done by Other Agent');

        Test.startTest();
        decide(people.executive, requested.Id, 'Approve');
        Test.stopTest();

        Visit__c cancelled = [SELECT Status__c, Approval_Status__c, Reason_of_Cancellation__c FROM Visit__c WHERE Id = :requested.Id];
        System.assertEquals(PartnerSiteVisitService.APPROVED, cancelled.Approval_Status__c);
        System.assertEquals('Cancelled', cancelled.Status__c, 'Not scheduled for a closed lead');
        System.assertEquals(PartnerSiteVisitService.PARTNER_VISIT_LEAD_CLOSED_REASON, cancelled.Reason_of_Cancellation__c);
        System.assertEquals('Site Visit Done by Other Agent', [SELECT Status FROM Lead WHERE Id = :record.Id].Status);
        System.assertEquals(0, PartnerSiteVisitService.emailsWritten, 'No confirmation for a cancelled visit');
    }

    // A repeat visit approved for a lead already Visited leaves it at Visited (without the hand-over to JKP at Visited)
    @isTest
    static void aRepeatVisitKeepsTheLeadVisited() {
        Approvers people = approvers();
        useSetting(people.executive.Username, null);
        PartnerLeadHandover.setting = new Partner_Portal_Setting__mdt();
        User partner = PartnerPortalTestUser.create();
        Lead record = leadOf(accountOf(partner), partner.Id, project());
        Visit__c done = new Visit__c(Lead__c = record.Id, Status__c = 'Completed', Visit_Date__c = Date.today().addDays(-3), OwnerId = partner.Id);
        insert done;
        update new Lead(Id = record.Id, Status = 'Visited');
        Visit__c again = request(partner, record, Date.today().addDays(4));

        Test.startTest();
        decide(people.executive, again.Id, 'Approve');
        Test.stopTest();

        System.assertEquals('Upcoming', visitOf(again.Id).Status__c);
        System.assertEquals('Visited', [SELECT Status FROM Lead WHERE Id = :record.Id].Status, 'Not taken back to Site Visit Scheduled');
    }

    // Today, a visit must be at a time still ahead; today's visit can be marked completed only from its time
    @isTest
    static void todaysTimeMatters() {
        Approvers people = approvers();
        useSetting(people.executive.Username, null);
        User partner = PartnerPortalTestUser.create();
        Lead record = leadOf(accountOf(partner), partner.Id, project());
        Visit__c tonight = new Visit__c(Lead__c = record.Id, Status__c = 'Upcoming', Visit_Date__c = Date.today(),
            Visit_Time__c = Time.newInstance(23, 59, 0, 0), OwnerId = partner.Id);
        Lead other = leadOf(accountOf(partner), partner.Id, record.Project__c);

        String pastTime;
        String tooEarly;
        Test.startTest();
        insert tonight;
        System.runAs(partner) {
            pastTime = requestError(other, record.Project__c, requirementType(), Date.today(), Time.newInstance(0, 0, 0, 0));
            tooEarly = completeError(record, tonight.Id);
        }
        Test.stopTest();

        System.assertEquals(PartnerSiteVisitService.PARTNER_VISIT_TIME_PAST, pastTime);
        System.assertEquals(String.format(PartnerSiteVisitService.PARTNER_VISIT_NOT_YET_TODAY, new List<Object>{
            PartnerSiteVisitService.timeText(Time.newInstance(23, 59, 0, 0)) }), tooEarly);
        System.assertEquals('Upcoming', visitOf(tonight.Id).Status__c);
    }

    // A visit JKP completes in Salesforce also moves its partner lead to Visited; a lead JKP owns is left alone
    @isTest
    static void aVisitCompletedInSalesforceMovesThePartnerLead() {
        Approvers people = approvers();
        useSetting(people.executive.Username, null);
        User partner = PartnerPortalTestUser.create();
        Id projectId = project();
        Lead partners = leadOf(accountOf(partner), partner.Id, projectId);
        Lead insertedDone = leadOf(accountOf(partner), partner.Id, projectId);
        Lead jkps = leadOf(accountOf(partner), UserInfo.getUserId(), projectId);
        Visit__c scheduled = new Visit__c(Lead__c = partners.Id, Status__c = 'Upcoming', Visit_Date__c = Date.today());
        Visit__c jkpVisit = new Visit__c(Lead__c = jkps.Id, Status__c = 'Upcoming', Visit_Date__c = Date.today());
        insert new List<Visit__c>{ scheduled, jkpVisit };

        Test.startTest();
        update new List<Visit__c>{ new Visit__c(Id = scheduled.Id, Status__c = 'Completed'), new Visit__c(Id = jkpVisit.Id, Status__c = 'Completed') };
        insert new Visit__c(Lead__c = insertedDone.Id, Status__c = 'Completed', Visit_Date__c = Date.today());
        Test.stopTest();

        System.assertEquals('Visited', [SELECT Status FROM Lead WHERE Id = :partners.Id].Status);
        System.assertEquals('Visited', [SELECT Status FROM Lead WHERE Id = :insertedDone.Id].Status, 'A visit saved as completed');
        System.assertNotEquals('Visited', [SELECT Status FROM Lead WHERE Id = :jkps.Id].Status, 'Not a partner lead');
    }

    // A request JKP recalls (an admin removes it from approval) ends as rejected, so it no longer blocks the lead
    @isTest
    static void aRecalledRequestEnds() {
        Approvers people = approvers();
        useSetting(people.executive.Username, null);
        User partner = PartnerPortalTestUser.create();
        Lead record = leadOf(accountOf(partner), partner.Id, project());
        Visit__c requested = request(partner, record, Date.today().addDays(2));

        Test.startTest();
        Approval.ProcessWorkitemRequest recall = new Approval.ProcessWorkitemRequest();
        recall.setWorkitemId([SELECT Id FROM ProcessInstanceWorkitem WHERE ProcessInstance.TargetObjectId = :requested.Id].Id);
        recall.setAction('Removed');
        Approval.process(recall);
        Test.stopTest();

        Visit__c ended = visitOf(requested.Id);
        System.assertEquals(PartnerSiteVisitService.REJECTED, ended.Approval_Status__c);
        System.assertEquals('Rejected', ended.Status__c);
        System.assertEquals(null, PartnerSiteVisitService.blockedReason(record.Id), 'A new request can be sent');
    }

    // A Visit Action is read whatever its capitals
    @isTest
    static void readsVisitActionsInAnyCapitals() {
        System.assertEquals(PartnerSiteVisitService.ACTION_REQUEST, PartnerSiteVisitService.actionOf(' request '));
        System.assertEquals(PartnerSiteVisitService.ACTION_COMPLETE, PartnerSiteVisitService.actionOf('COMPLETE'));
        System.assertEquals(null, PartnerSiteVisitService.actionOf(' '));
        PartnerSiteVisitService.stageByAction = new Map<String, String>{ 'request' => 'Site Visit Scheduled' };
        System.assertEquals('Site Visit Scheduled', PartnerSiteVisitService.stageFor('Request'));
        System.assertEquals(null, PartnerSiteVisitService.stageFor(null));
    }

    // "10:30 AM" from the Site Visits page and "14:05" from a time input
    @isTest
    static void readsTimesOfDay() {
        System.assertEquals(Time.newInstance(10, 30, 0, 0), PartnerSiteVisitService.timeOf('10:30 AM'));
        System.assertEquals(Time.newInstance(0, 15, 0, 0), PartnerSiteVisitService.timeOf('12:15 am'));
        System.assertEquals(Time.newInstance(14, 5, 0, 0), PartnerSiteVisitService.timeOf('14:05'));
        System.assertEquals(Time.newInstance(9, 0, 0, 0), PartnerSiteVisitService.timeOf('09:00:00.000'));
        for (String notATime : new List<String>{ '24:00', '13:00 PM', '9:60', 'soon', '', null }) {
            System.assertEquals(null, PartnerSiteVisitService.timeOf(notATime), 'Not a time: ' + notATime);
        }
        // The user's locale writes the AM/PM marker (en_IN: "pm")
        String afternoon = PartnerSiteVisitService.timeText(Time.newInstance(14, 5, 0, 0));
        System.assert(afternoon.equalsIgnoreCase('2:05 PM'), afternoon);
        String day = PartnerSiteVisitService.dateText(Date.newInstance(2026, 10, 6));
        System.assert(day.equalsIgnoreCase('6 Oct 2026'), day);
    }

    private static String required(SObjectField field) {
        return String.format(PartnerSiteVisitService.PARTNER_LEAD_EDIT_FIELD_REQUIRED, new List<Object>{ field.getDescribe().getLabel() });
    }

    private static String requestError(Lead record, Id projectId, String type, Date day, Time at) {
        try {
            PartnerSiteVisitService.request(record, projectId, type, day, at, null);
            return null;
        } catch (PartnerSiteVisitService.VisitException e) {
            return e.getMessage();
        }
    }

    private static String completeError(Lead record, Id visitId) {
        try {
            PartnerSiteVisitService.complete(record, visitId);
            return null;
        } catch (PartnerSiteVisitService.VisitException e) {
            return e.getMessage();
        }
    }
}