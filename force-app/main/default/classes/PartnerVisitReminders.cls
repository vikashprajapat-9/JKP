// The Site Visit Reminders of the Lead Nurturing chart, for the channel partner agent (their own leads' visits only):
//  - D-1: tomorrow's scheduled visits in the portal bell;
//  - visit day: today's visits in the portal bell, and a Salesforce notification (the Partner Portal Setting's Visit
//    Reminder Notification, sent by PartnerVisitReminderJob);
//  - D+1: visits whose day has passed and that are still scheduled ("to update") in the bell, where the agent marks them
//    Visited or Did not visit; a Salesforce notification the day after the visit.
// The portal shows them in its bell only (not on the Dashboard).
// Partners cannot read visits under approval or internal users, so this runs without sharing in system mode; every
// visit is checked against the logged-in partner (PartnerPortalAccess) and their own open leads.
public without sharing class PartnerVisitReminders {

    // Tests set their own
    @TestVisible
    private static Partner_Portal_Setting__mdt setting = Partner_Portal_Setting__mdt.getInstance('Default');

    // The notifications written, and sent (for tests)
    @TestVisible
    private static Integer notificationsAttempted = 0;
    @TestVisible
    private static Integer notificationsSent = 0;

    // The texts this class gives: the portal's messages, and the titles and bodies of the reminder notifications
    @TestVisible
    private static final String PARTNER_VISIT_MARKED_VISITED = 'The visit is marked Visited. The John Keells Properties CP team takes the lead over from here.';
    @TestVisible
    private static final String PARTNER_VISIT_NOT_VISITED_DONE = 'The visit is marked Not Visited. You can request a new site visit for this lead.';
    private static final String PARTNER_PORTAL_NO_ACCESS = 'Your Partner Portal access is not active. Please contact the JKP CP team.';
    @TestVisible
    private static final String PARTNER_VISIT_NOT_SCHEDULED = 'This visit is no longer scheduled. Refresh the page to see its latest status.';
    private static final String PARTNER_VISIT_REMINDER_TODAY_TITLE = 'Site visit today: {0}';
    private static final String PARTNER_VISIT_REMINDER_UPDATE_TITLE = 'Update your site visit: {0}';
    private static final String PARTNER_VISIT_REMINDER_TODAY_BODY = '{0} at {1}, {2}.';
    private static final String PARTNER_VISIT_REMINDER_UPDATE_BODY = 'The visit with {0} on {1} is not updated. On the portal, mark it Visited or Did not visit.';

    public class Reminder {
        @AuraEnabled public Id visitId;
        @AuraEnabled public Id leadId;
        @AuraEnabled public String visitName;
        @AuraEnabled public String customerName;
        @AuraEnabled public String projectName;
        @AuraEnabled public String dateText;
        @AuraEnabled public String timeText;
        // The visit's day (and today its time) has come: it can be marked Visited or Did not visit
        @AuraEnabled public Boolean canUpdate = false;
        @AuraEnabled public String note;
    }

    public class Reminders {
        @AuraEnabled public List<Reminder> today = new List<Reminder>();
        @AuraEnabled public List<Reminder> tomorrow = new List<Reminder>();
        @AuraEnabled public List<Reminder> toUpdate = new List<Reminder>();
        // What needs the agent: today's visits and the ones to update
        @AuraEnabled public Integer count = 0;
    }

    // =====================================================================================================
    // THE PORTAL (the bell)
    // =====================================================================================================

    @AuraEnabled
    public static Reminders getReminders() {
        Reminders result = new Reminders();
        PartnerPortalAccess access = PartnerPortalAccess.current();
        if (access.accountId == null) {
            return result;
        }
        Date today = Date.today();
        for (Visit__c visit : visitsOf(access, null, today.addDays(1))) {
            Reminder reminder = reminderOf(visit);
            if (visit.Visit_Date__c < today) {
                result.toUpdate.add(reminder);
            } else if (visit.Visit_Date__c == today) {
                result.today.add(reminder);
            } else {
                result.tomorrow.add(reminder);
            }
        }
        result.count = result.today.size() + result.toUpdate.size();
        return result;
    }

    // The customer came: the visit is completed and the lead moves to Visited (as on the Edit popup)
    @AuraEnabled
    public static String markVisited(Id visitId) {
        Visit__c visit = ownVisit(visitId);
        try {
            PartnerSiteVisitService.complete(visit.Lead__r, visit.Id);
        } catch (PartnerSiteVisitService.VisitException e) {
            throw userError(e.getMessage());
        }
        return PARTNER_VISIT_MARKED_VISITED;
    }

    // The customer did not come: the visit is Not Visited and a new site visit can be requested
    @AuraEnabled
    public static String markNotVisited(Id visitId) {
        Visit__c visit = ownVisit(visitId);
        try {
            PartnerSiteVisitService.markNotVisited(visit.Lead__r, visit.Id);
        } catch (PartnerSiteVisitService.VisitException e) {
            throw userError(e.getMessage());
        }
        return PARTNER_VISIT_NOT_VISITED_DONE;
    }

    // One of the agent's scheduled visits, of a lead they may still update; refused otherwise
    private static Visit__c ownVisit(Id visitId) {
        PartnerPortalAccess access = PartnerPortalAccess.current();
        if (access.accountId == null) {
            throw userError(PARTNER_PORTAL_NO_ACCESS);
        }
        if (visitId == null) {
            throw userError(PARTNER_VISIT_NOT_SCHEDULED);
        }
        List<Visit__c> visits = visitsOf(access, visitId, null);
        if (visits.isEmpty()) {
            throw userError(PARTNER_VISIT_NOT_SCHEDULED);
        }
        return visits[0];
    }

    // The agent's scheduled visits of their own leads they may still update (up to the day given), earliest first; or
    // the one visit
    private static List<Visit__c> visitsOf(PartnerPortalAccess access, Id visitId, Date upTo) {
        Map<String, Object> binds = new Map<String, Object>();
        String query = 'SELECT Id, Name, Visit_Date__c, Visit_Time__c, Status__c, Project__r.Name, Lead__c, Lead__r.Id, Lead__r.Name,'
            + ' Lead__r.Status, Lead__r.OwnerId, Lead__r.IsConverted, Lead__r.CP_Approval_Status__c, Lead__r.Channel_Partner__c'
            + ' FROM Visit__c WHERE Visit_Date__c != null AND ' + PartnerSiteVisitService.scheduledCondition(binds)
            + ' AND Lead__c IN (SELECT Id FROM Lead WHERE IsConverted = false AND ' + access.ownLeads(binds) + ')';
        if (visitId != null) {
            binds.put('visitId', visitId);
            query += ' AND Id = :visitId';
        }
        if (upTo != null) {
            binds.put('upTo', upTo);
            query += ' AND Visit_Date__c <= :upTo';
        }
        query += ' ORDER BY Visit_Date__c ASC, Visit_Time__c ASC NULLS LAST LIMIT 200';
        List<Visit__c> visits = Database.queryWithBinds(query, binds, AccessLevel.SYSTEM_MODE);
        Set<Id> ownerIds = new Set<Id>();
        for (Visit__c visit : visits) {
            ownerIds.add(visit.Lead__r.OwnerId);
        }
        partnerWebPortalLeadEditController.loadOwners(ownerIds);
        List<Visit__c> usable = new List<Visit__c>();
        for (Visit__c visit : visits) {
            if (partnerWebPortalLeadEditController.readOnlyReasonOf(visit.Lead__r, access) == null) {
                usable.add(visit);
            }
        }
        return usable;
    }

    private static Reminder reminderOf(Visit__c visit) {
        Reminder reminder = new Reminder();
        reminder.visitId = visit.Id;
        reminder.leadId = visit.Lead__c;
        reminder.visitName = visit.Name;
        reminder.customerName = visit.Lead__r.Name;
        reminder.projectName = visit.Project__r == null ? null : visit.Project__r.Name;
        reminder.dateText = PartnerSiteVisitService.dateText(visit.Visit_Date__c);
        reminder.timeText = PartnerSiteVisitService.timeText(visit.Visit_Time__c);
        reminder.note = PartnerSiteVisitService.notYetReason(visit);
        reminder.canUpdate = reminder.note == null;
        return reminder;
    }

    // =====================================================================================================
    // SALESFORCE NOTIFICATIONS (PartnerVisitReminderJob)
    // =====================================================================================================

    // The job's visits: scheduled ones dated today (the visit day) or yesterday (not updated the day after)
    public static Database.QueryLocator dueVisits() {
        Map<String, Object> binds = new Map<String, Object>{ 'days' => new Set<Date>{ Date.today(), Date.today().addDays(-1) } };
        return Database.getQueryLocatorWithBinds(
            'SELECT Id, OwnerId, Visit_Date__c, Visit_Time__c, Project__r.Name, Lead__c, Lead__r.Name, Lead__r.OwnerId FROM Visit__c'
                + ' WHERE Visit_Date__c IN :days AND Lead__c != null AND ' + PartnerSiteVisitService.scheduledCondition(binds),
            binds, AccessLevel.SYSTEM_MODE);
    }

    // Notifies each visit's agent (the partner user who requested it, else the lead's partner owner): today's visit, or
    // yesterday's visit to update. A notification that cannot be sent does not stop the others.
    public static void notify(List<Visit__c> visits) {
        String typeName = setting == null || String.isBlank(setting.Visit_Reminder_Notification__c) ? null
            : setting.Visit_Reminder_Notification__c.trim();
        if (typeName == null || visits.isEmpty()) {
            return;
        }
        List<CustomNotificationType> types = [
            SELECT Id FROM CustomNotificationType WHERE DeveloperName = :typeName WITH SYSTEM_MODE LIMIT 1
        ];
        if (types.isEmpty()) {
            System.debug(LoggingLevel.ERROR, 'Custom notification type not found: ' + typeName);
            return;
        }
        Set<Id> users = new Set<Id>();
        for (Visit__c visit : visits) {
            users.add(visit.OwnerId);
            users.add(visit.Lead__r.OwnerId);
        }
        partnerWebPortalLeadEditController.loadOwners(users);
        for (Visit__c visit : visits) {
            Id agent = partnerWebPortalLeadEditController.isPartnerUser(visit.OwnerId) ? visit.OwnerId
                : (partnerWebPortalLeadEditController.isPartnerUser(visit.Lead__r.OwnerId) ? visit.Lead__r.OwnerId : null);
            if (agent == null) {
                continue;
            }
            Boolean today = visit.Visit_Date__c == Date.today();
            String customer = visit.Lead__r.Name;
            String project = visit.Project__r == null ? '' : visit.Project__r.Name;
            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setNotificationTypeId(types[0].Id);
            notification.setTargetId(visit.Id);
            notification.setTitle(String.format(today ? PARTNER_VISIT_REMINDER_TODAY_TITLE : PARTNER_VISIT_REMINDER_UPDATE_TITLE,
                new List<Object>{ customer }));
            notification.setBody(today
                ? String.format(PARTNER_VISIT_REMINDER_TODAY_BODY, new List<Object>{ project,
                    PartnerSiteVisitService.timeText(visit.Visit_Time__c), PartnerSiteVisitService.dateText(visit.Visit_Date__c) })
                : String.format(PARTNER_VISIT_REMINDER_UPDATE_BODY, new List<Object>{ customer,
                    PartnerSiteVisitService.dateText(visit.Visit_Date__c) }));
            notificationsAttempted++;
            try {
                notification.send(new Set<String>{ String.valueOf(agent) });
                notificationsSent++;
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Site visit reminder not sent for ' + visit.Id + ': ' + e.getMessage());
            }
        }
    }

    private static AuraHandledException userError(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}