// The Site Visit Reminders of the Lead Nurturing chart (PartnerVisitReminders) and Visited? No: the agent sees today's,
// tomorrow's and not updated visits of their own leads on the portal, marks them Visited or Did not visit there or in
// the Edit popup, and gets a Salesforce notification on the visit day and the day after a visit not updated.
@isTest
private class PartnerVisitRemindersTest {

    private static Integer leadCount = 0;
    private static final Time TEN = Time.newInstance(10, 0, 0, 0);

    private static void useSetting() {
        Partner_Portal_Setting__mdt setting = new Partner_Portal_Setting__mdt(
            Visit_Status__c = 'Upcoming',
            Visit_Request_Status__c = 'Requested',
            Visit_Rejected_Status__c = 'Rejected',
            Open_Visit_Statuses__c = 'Upcoming',
            Completed_Visit_Status__c = 'Completed',
            Cancelled_Visit_Status__c = 'Cancelled',
            Not_Visited_Status__c = 'Not Visited',
            CP_Lead_Lost_Status__c = 'Site Visit Done by Other Agent',
            Visit_Reminder_Notification__c = 'CP_Site_Visit_Reminder'
        );
        PartnerSiteVisitService.setting = setting;
        PartnerVisitReminders.setting = setting;
        PartnerLeadFreeze.setting = setting;
        PartnerSiteVisitService.stageByAction = new Map<String, String>{ 'request' => 'Site Visit Scheduled', 'complete' => 'Visited' };
        // No hand-over to the CP team when a visit is completed here
        PartnerLeadHandover.setting = new Partner_Portal_Setting__mdt();
    }

    private static Id accountOf(User portalUser) {
        return [SELECT Contact.AccountId FROM User WHERE Id = :portalUser.Id].Contact.AccountId;
    }

    private static Id project() {
        Project__c project = TestRecordDefaults.project('Reminder Project', true);
        insert project;
        return project.Id;
    }

    private static Lead leadOf(Id channelPartnerId, Id ownerId, Id projectId) {
        leadCount++;
        Lead record = new Lead(LastName = 'Reminder Buyer ' + leadCount, Company = 'Reminder Holdings ' + leadCount,
            Phone = '07712399' + String.valueOf(leadCount).leftPad(2, '0'), Email = 'reminder.buyer' + leadCount + '@example.com',
            LeadSource = 'Channel Partner', Budget_Aligned__c = 'Matching Budget', Project__c = projectId,
            Channel_Partner__c = channelPartnerId, OwnerId = ownerId);
        insert record;
        return [SELECT Id, Name, Status, OwnerId, IsConverted, CP_Approval_Status__c, Channel_Partner__c, Project__c FROM Lead WHERE Id = :record.Id];
    }

    // A scheduled visit of the lead on the day, requested by the owner
    private static Visit__c visitOf(Lead record, Date day, Id ownerId) {
        return new Visit__c(Lead__c = record.Id, Project__c = record.Project__c, Visit_Date__c = day, Visit_Time__c = TEN,
            Status__c = 'Upcoming', OwnerId = ownerId);
    }

    private static String statusOf(Id visitId) {
        return [SELECT Status__c FROM Visit__c WHERE Id = :visitId].Status__c;
    }

    // Yesterday's visit is to update, today's and tomorrow's are reminders, a later one is not; another partner's visit
    // and a cancelled one are not shown
    @isTest
    static void theAgentSeesTheirReminders() {
        useSetting();
        User partner = PartnerPortalTestUser.create();
        Id projectId = project();
        Lead record = leadOf(accountOf(partner), partner.Id, projectId);
        Lead second = leadOf(accountOf(partner), partner.Id, projectId);
        Account other = new Account(Name = 'Other Reminder Partner', RecordTypeId = partnerPortalRegistrationController.partnerRecordTypeId());
        insert other;
        Lead othersLead = leadOf(other.Id, UserInfo.getUserId(), projectId);
        Visit__c yesterday = visitOf(record, Date.today().addDays(-1), partner.Id);
        Visit__c today = visitOf(second, Date.today(), partner.Id);
        Visit__c tomorrow = visitOf(record, Date.today().addDays(1), partner.Id);
        Visit__c later = visitOf(second, Date.today().addDays(5), partner.Id);
        Visit__c cancelled = visitOf(second, Date.today(), partner.Id);
        cancelled.Status__c = 'Cancelled';
        Visit__c others = visitOf(othersLead, Date.today(), UserInfo.getUserId());
        insert new List<Visit__c>{ yesterday, today, tomorrow, later, cancelled, others };

        PartnerVisitReminders.Reminders reminders;
        System.runAs(partner) {
            reminders = PartnerVisitReminders.getReminders();
        }
        System.assertEquals(1, reminders.toUpdate.size());
        System.assertEquals(yesterday.Id, reminders.toUpdate[0].visitId);
        System.assert(reminders.toUpdate[0].canUpdate, 'Its day has passed');
        System.assertEquals(1, reminders.today.size());
        System.assertEquals(today.Id, reminders.today[0].visitId);
        System.assertEquals(second.Name, reminders.today[0].customerName);
        System.assertEquals(PartnerSiteVisitService.timeText(TEN), reminders.today[0].timeText);
        System.assertEquals(1, reminders.tomorrow.size());
        System.assertEquals(tomorrow.Id, reminders.tomorrow[0].visitId);
        System.assert(!reminders.tomorrow[0].canUpdate, 'Not before its day');
        System.assertEquals(2, reminders.count, 'Today and to update');
    }

    // Visited? No: the visit whose day has passed blocks a new request until it is updated; Did not visit makes it Not
    // Visited and the lead can have a new request. Visited completes the visit and moves the lead to Visited.
    @isTest
    static void theAgentUpdatesPastVisits() {
        useSetting();
        User partner = PartnerPortalTestUser.create();
        Id projectId = project();
        Lead record = leadOf(accountOf(partner), partner.Id, projectId);
        Lead second = leadOf(accountOf(partner), partner.Id, projectId);
        Visit__c missed = visitOf(record, Date.today().addDays(-1), partner.Id);
        Visit__c done = visitOf(second, Date.today().addDays(-2), partner.Id);
        Visit__c ahead = visitOf(second, Date.today().addDays(3), partner.Id);
        insert new List<Visit__c>{ missed, done, ahead };
        String blockedBefore = PartnerSiteVisitService.blockedReason(record.Id);

        String notVisitedMessage;
        String visitedMessage;
        String tooEarly;
        String unknown;
        Test.startTest();
        System.runAs(partner) {
            notVisitedMessage = PartnerVisitReminders.markNotVisited(missed.Id);
            visitedMessage = PartnerVisitReminders.markVisited(done.Id);
            try {
                PartnerVisitReminders.markNotVisited(ahead.Id);
            } catch (AuraHandledException e) {
                tooEarly = e.getMessage();
            }
            try {
                PartnerVisitReminders.markVisited(missed.Id);
            } catch (AuraHandledException e) {
                unknown = e.getMessage();
            }
        }
        Test.stopTest();

        System.assertEquals(String.format(PartnerSiteVisitService.PARTNER_VISIT_NOT_UPDATED, new List<Object>{ PartnerSiteVisitService.dateText(Date.today().addDays(-1)) }),
            blockedBefore);
        System.assertEquals(PartnerVisitReminders.PARTNER_VISIT_NOT_VISITED_DONE, notVisitedMessage);
        System.assertEquals('Not Visited', statusOf(missed.Id));
        System.assertEquals(null, PartnerSiteVisitService.blockedReason(record.Id), 'A new site visit can be requested');
        System.assertNotEquals('Visited', [SELECT Status FROM Lead WHERE Id = :record.Id].Status, 'The lead keeps its stage');
        System.assertEquals(PartnerVisitReminders.PARTNER_VISIT_MARKED_VISITED, visitedMessage);
        System.assertEquals('Completed', statusOf(done.Id));
        System.assertEquals('Visited', [SELECT Status FROM Lead WHERE Id = :second.Id].Status);
        System.assertEquals(PartnerSiteVisitService.PARTNER_VISIT_NOT_VISITED_TOO_EARLY, tooEarly);
        System.assertEquals('Upcoming', statusOf(ahead.Id));
        System.assertEquals(PartnerVisitReminders.PARTNER_VISIT_NOT_SCHEDULED, unknown, 'Already updated');
    }

    // The Edit popup's Customer did not visit: only the partner's own lead, a visit whose time has come
    @isTest
    static void theEditPopupMarksAVisitNotVisited() {
        useSetting();
        User partner = PartnerPortalTestUser.create();
        Lead record = leadOf(accountOf(partner), partner.Id, project());
        Visit__c missed = visitOf(record, Date.today().addDays(-1), partner.Id);
        insert missed;

        partnerWebPortalLeadEditController.SaveResult result;
        String again;
        System.runAs(partner) {
            result = partnerWebPortalLeadEditController.markNotVisited(record.Id, missed.Id);
            try {
                partnerWebPortalLeadEditController.markNotVisited(record.Id, missed.Id);
            } catch (AuraHandledException e) {
                again = e.getMessage();
            }
        }
        System.assertEquals('The visit is marked Not Visited. You can request a new site visit for this lead.', result.message);
        System.assertEquals(record.Status, result.status, 'The lead keeps its stage');
        System.assertEquals('Not Visited', statusOf(missed.Id));
        System.assertEquals(PartnerSiteVisitService.PARTNER_VISIT_NOT_SCHEDULED, again);
    }

    // The daily job notifies the agent of today's visits and of yesterday's not updated
    @isTest
    static void theJobNotifiesTheAgent() {
        useSetting();
        User partner = PartnerPortalTestUser.create();
        Id projectId = project();
        Lead record = leadOf(accountOf(partner), partner.Id, projectId);
        insert new List<Visit__c>{
            visitOf(record, Date.today(), partner.Id),
            visitOf(record, Date.today().addDays(-1), partner.Id),
            visitOf(record, Date.today().addDays(1), partner.Id)
        };

        PartnerVisitReminderJob job = new PartnerVisitReminderJob();
        List<Visit__c> due = new List<Visit__c>();
        Database.QueryLocatorIterator found = job.start(null).iterator();
        while (found.hasNext()) {
            due.add((Visit__c) found.next());
        }
        Test.startTest();
        job.execute(null, due);
        Integer notified = PartnerVisitReminders.notificationsAttempted;
        // Scheduled, it runs as a batch over the same visits
        job.execute((SchedulableContext) null);
        Test.stopTest();

        System.assertEquals(2, due.size(), 'Today and yesterday, not tomorrow');
        System.assertEquals(2, notified);
        System.assertEquals(4, PartnerVisitReminders.notificationsAttempted, 'The scheduled run notifies the same visits');
        System.debug('Site visit reminders sent: ' + PartnerVisitReminders.notificationsSent);
    }
}