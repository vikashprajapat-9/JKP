// Site visits a channel partner requests on the Partner Portal (the Lead Nurturing chart):
//  - the request (for the project the lead was created for; the Visit Request Status, Approval Status Pending CP
//    Executive) goes to the JKP CP Executive (the Partner Portal Setting's CP Executive, else the partner account's
//    owner) through the CP Site Visit Executive Approval;
//  - when the CP Executive rejects it, it goes to the CP Manager (the CP Executive's manager, else the setting's CP
//    Manager) through the CP Site Visit Manager Approval; when the CP Manager rejects it too, the request is rejected
//    (the Visit Rejected Status) and the partner is emailed (the setting's Visit Rejected Email Template);
//  - an approved request becomes a scheduled visit (the setting's Visit Status), the partner is emailed (the Visit
//    Confirmed Email Template), and the lead moves to the stage of the Partner Portal Lead Status with the Request
//    visit action (Site Visit Scheduled). When the lead was closed meanwhile (booked, lost to another partner or taken
//    over by a JKP queue), the approved visit is cancelled instead and nobody is emailed;
//  - the partner marks the visit completed on the portal, which moves the lead to the stage with the Complete visit
//    action (Visited); or, when the customer did not come, Not Visited (the setting's Not Visited Status), after which
//    the partner can request another visit. A visit whose day has passed blocks a new request until it is updated.
// Partners cannot see internal users or update visits under approval, so this runs without sharing in system mode;
// the portal controllers check that the lead is the partner's own before calling it.
public without sharing class PartnerSiteVisitService {

    public static final String PENDING_EXECUTIVE = 'Pending CP Executive';
    public static final String REJECTED_BY_EXECUTIVE = 'Rejected by CP Executive';
    public static final String PENDING_MANAGER = 'Pending CP Manager';
    public static final String APPROVED = 'Approved';
    public static final String REJECTED = 'Rejected';
    // The Visit Action of a Partner Portal Lead Status
    public static final String ACTION_REQUEST = 'Request';
    public static final String ACTION_COMPLETE = 'Complete';

    @TestVisible
    private static final String EXECUTIVE_PROCESS = 'CP_Site_Visit_Executive_Approval';
    @TestVisible
    private static final String MANAGER_PROCESS = 'CP_Site_Visit_Manager_Approval';
    private static final Set<String> WAITING = new Set<String>{ PENDING_EXECUTIVE, REJECTED_BY_EXECUTIVE, PENDING_MANAGER };

    // "10:30 AM" (the Site Visits page) or "14:05" (a time input)
    private static final Pattern TWELVE_HOUR_TIME = Pattern.compile('^\\s*(\\d{1,2}):(\\d{2})\\s*([AaPp][Mm])\\s*$');
    private static final Pattern TWENTY_FOUR_HOUR_TIME = Pattern.compile('^\\s*(\\d{1,2}):(\\d{2})(:\\d{2}(\\.\\d{1,3})?)?\\s*$');

    // The texts this class gives: the portal's messages, a cancelled visit's reason and the rejection email's reason line
    @TestVisible
    private static final String PARTNER_VISIT_DATE_PAST = 'Choose today or a later date for the visit.';
    @TestVisible
    private static final String PARTNER_VISIT_TIME_PAST = 'Choose a time later than now for a visit today.';
    @TestVisible
    private static final String PARTNER_VISIT_NO_APPROVER = 'Site visits cannot be requested right now because no John Keells Properties approver is set up. Please contact your CP Executive.';
    @TestVisible
    private static final String PARTNER_VISIT_PROJECT_NOT_LEAD = 'A site visit for this lead can only be for its project, {0}. Please reload the page and try again.';
    @TestVisible
    private static final String PARTNER_VISIT_PROJECT_NOT_OPEN = 'Site visits cannot be requested for this lead now: its project, {0}, is not open for site visits. Please contact your CP Executive.';
    @TestVisible
    private static final String PARTNER_VISIT_REQUEST_PENDING = 'A site visit request for this lead is already waiting for approval.';
    @TestVisible
    private static final String PARTNER_VISIT_NOT_UPDATED = 'Your site visit on {0} is not updated yet. Mark it Visited, or that the customer did not visit, before requesting another one.';
    @TestVisible
    private static final String PARTNER_VISIT_ALREADY_SCHEDULED = 'This lead already has a site visit scheduled on {0}. Mark it completed before requesting another one.';
    @TestVisible
    private static final String PARTNER_VISIT_LEAD_CLOSED_REASON = 'Cancelled automatically: the lead was booked, went to another channel partner or was taken over by John Keells Properties before the visit was approved.';
    @TestVisible
    private static final String PARTNER_VISIT_CHOOSE_VISIT = 'Choose the visit that took place.';
    private static final String PARTNER_LEAD_EDIT_STATUS_UNKNOWN = 'Choose one of the stages offered for this lead.';
    @TestVisible
    private static final String PARTNER_VISIT_NOT_YET = 'This visit is on {0}. You can mark it completed on or after that day.';
    @TestVisible
    private static final String PARTNER_VISIT_NOT_YET_TODAY = 'This visit is at {0} today. You can mark it completed from that time.';
    @TestVisible
    private static final String PARTNER_VISIT_NOT_SCHEDULED = 'This visit is no longer scheduled. Refresh the page to see its latest status.';
    @TestVisible
    private static final String PARTNER_VISIT_NOT_VISITED_TOO_EARLY = 'You can say the customer did not visit only after the visit\'s date and time.';
    private static final String PARTNER_VISIT_NOT_SENT = 'The site visit request could not be sent for approval. Please try again or contact your CP Executive.';
    private static final String PARTNER_VISIT_REJECTION_COMMENT = 'Reason given by John Keells Properties: {0}';
    @TestVisible
    private static final String PARTNER_LEAD_EDIT_FIELD_REQUIRED = '{0} is required.';

    // The Partner Portal Setting and the lead stages of the visit actions; tests set their own
    @TestVisible
    private static Partner_Portal_Setting__mdt setting = Partner_Portal_Setting__mdt.getInstance('Default');
    @TestVisible
    private static Map<String, String> stageByAction;

    // The partner emails written, and their texts (for tests: emails are not sent in tests)
    @TestVisible
    private static Integer emailsWritten = 0;
    @TestVisible
    private static List<String> emailBodies = new List<String>();

    public class VisitException extends Exception {}

    // A request's two approvers
    @TestVisible
    private class Approvers {
        @TestVisible private Id executive;
        @TestVisible private Id manager;
    }

    // =====================================================================================================
    // REQUEST
    // =====================================================================================================

    // The visit a partner asks for, for one of their own open leads (the caller checks the lead, and passes it with its
    // Project__c): the lead's project (see visitProjectOf), the requirement type, a date from today on and a time; the
    // description is optional. Refused while the lead has a request waiting for approval or a visit scheduled. The
    // request is saved and sent to the JKP CP Executive together: when it cannot be sent, nothing is saved.
    public static Visit__c request(Lead customer, Id projectId, String requirementType, Date visitDate, Time visitTime, String description) {
        Id visitProject = visitProjectOf(customer, projectId);
        String requirement = requirementTypeOf(requirementType);
        if (visitDate == null) {
            throw new VisitException(required(Visit__c.Visit_Date__c));
        }
        if (visitDate < Date.today()) {
            throw new VisitException(PARTNER_VISIT_DATE_PAST);
        }
        if (visitTime == null) {
            throw new VisitException(required(Visit__c.Visit_Time__c));
        }
        if (visitDate == Date.today() && Datetime.newInstance(visitDate, visitTime) < Datetime.now()) {
            throw new VisitException(PARTNER_VISIT_TIME_PAST);
        }
        String blocked = blockedReason(customer.Id);
        if (blocked != null) {
            throw new VisitException(blocked);
        }
        Approvers approvers = approversFor(customer.Channel_Partner__c);
        if (approvers == null) {
            throw new VisitException(PARTNER_VISIT_NO_APPROVER);
        }

        Visit__c visit = new Visit__c(
            OwnerId = UserInfo.getUserId(),
            Lead__c = customer.Id,
            Channel_Partner__c = customer.Channel_Partner__c,
            Project__c = visitProject,
            Requirement_Type__c = requirement,
            Visit_Date__c = visitDate,
            Visit_Time__c = visitTime,
            Visit_Description__c = String.isBlank(description) ? null : description.trim(),
            Status__c = settingText(Partner_Portal_Setting__mdt.Visit_Request_Status__c),
            Approval_Status__c = PENDING_EXECUTIVE,
            CP_Executive_Approver__c = approvers.executive,
            CP_Manager_Approver__c = approvers.manager
        );
        Database.DMLOptions options = new Database.DMLOptions();
        options.DuplicateRuleHeader.allowSave = true;
        options.optAllOrNone = true;
        Savepoint beforeSave = Database.setSavepoint();
        try {
            Database.insert(visit, options, AccessLevel.SYSTEM_MODE);
            submit(new List<Id>{ visit.Id }, EXECUTIVE_PROCESS, true);
        } catch (DmlException e) {
            Database.rollback(beforeSave);
            throw new VisitException(e.getDmlMessage(0));
        } catch (VisitException e) {
            Database.rollback(beforeSave);
            throw e;
        }
        return visit;
    }

    // The project of the lead's visit. A lead is created for one project, and its site visits are for that project
    // only: another project is refused, and so is the lead's project while it is not open for site visits (no longer
    // active). A lead without a project (an old lead, from before leads needed one) keeps the project the partner
    // chose, as before; the portal controllers offer only the partner's active projects for it.
    private static Id visitProjectOf(Lead customer, Id projectId) {
        if (projectId == null) {
            throw new VisitException(required(Visit__c.Project__c));
        }
        if (customer.Project__c == null) {
            return projectId;
        }
        List<Project__c> leadProject = [SELECT Name, Active__c FROM Project__c WHERE Id = :customer.Project__c WITH SYSTEM_MODE];
        if (projectId != customer.Project__c) {
            throw new VisitException(String.format(PARTNER_VISIT_PROJECT_NOT_LEAD, new List<Object>{
                leadProject.isEmpty() ? '' : leadProject[0].Name }));
        }
        String notOpen = leadProject.isEmpty() ? null : projectNotOpenReason(leadProject[0]);
        if (notOpen != null) {
            throw new VisitException(notOpen);
        }
        return projectId;
    }

    // Why the leads of this project (read with its Name and Active__c) cannot have site visits now: the project is no
    // longer active. Null when they can, or without a project.
    public static String projectNotOpenReason(Project__c project) {
        return project == null || project.Active__c ? null
            : String.format(PARTNER_VISIT_PROJECT_NOT_OPEN, new List<Object>{ project.Name });
    }

    // Why the lead cannot have another request now (one is waiting for approval, a visit is scheduled, or a visit whose
    // day has passed is not updated yet), or null
    public static String blockedReason(Id leadId) {
        Map<String, Object> binds = new Map<String, Object>{ 'leadId' => leadId };
        List<Visit__c> visits = Database.queryWithBinds(
            'SELECT Id, Visit_Date__c, Status__c, Approval_Status__c FROM Visit__c WHERE Lead__c = :leadId AND '
                + openVisitCondition(binds) + ' ORDER BY Visit_Date__c ASC NULLS LAST LIMIT 20',
            binds, AccessLevel.SYSTEM_MODE);
        for (Visit__c visit : visits) {
            if (WAITING.contains(visit.Approval_Status__c)) {
                return PARTNER_VISIT_REQUEST_PENDING;
            }
        }
        if (!visits.isEmpty()) {
            // A visit whose day has passed must be marked Visited or Not Visited first
            Date first = visits[0].Visit_Date__c;
            return String.format(first != null && first < Date.today() ? PARTNER_VISIT_NOT_UPDATED
                : PARTNER_VISIT_ALREADY_SCHEDULED, new List<Object>{ dateText(first) });
        }
        return null;
    }

    // The SOQL condition of a visit that is waiting for approval or scheduled; its bind values go in binds
    public static String openVisitCondition(Map<String, Object> binds) {
        binds.put('visitWaiting', WAITING);
        return '(Approval_Status__c IN :visitWaiting OR ' + scheduledCondition(binds) + ')';
    }

    // The SOQL condition of a scheduled visit: one of the Open Visit Statuses, or no status when visits without one
    // are shown as an open status (the setting's Visit Status)
    public static String scheduledCondition(Map<String, Object> binds) {
        Set<String> scheduled = openStatuses();
        binds.put('visitScheduled', scheduled);
        String shownAs = settingText(Partner_Portal_Setting__mdt.Visit_Status__c);
        return shownAs != null && scheduled.contains(shownAs)
            ? '(Status__c IN :visitScheduled OR Status__c = null)' : 'Status__c IN :visitScheduled';
    }

    // The JKP CP Executive (the setting's, else the partner account's owner) and the CP Manager (the CP Executive's
    // manager, else the setting's); null when either is missing
    @TestVisible
    private static Approvers approversFor(Id accountId) {
        Approvers team = teamFor(accountId);
        return team == null || team.manager == null ? null : team;
    }

    // The JKP CP team of a partner account: its CP Executive and its CP Manager (null when there is none); null without
    // a CP Executive. (The site visit approvers and the lead hand-over.)
    public static List<Id> cpTeamOf(Id accountId) {
        Approvers team = teamFor(accountId);
        return team == null ? null : new List<Id>{ team.executive, team.manager };
    }

    private static Approvers teamFor(Id accountId) {
        String executiveName = settingText(Partner_Portal_Setting__mdt.CP_Executive_Username__c);
        String managerName = settingText(Partner_Portal_Setting__mdt.CP_Manager_Username__c);
        Set<String> usernames = new Set<String>();
        for (String username : new List<String>{ executiveName, managerName }) {
            if (username != null) {
                usernames.add(username);
            }
        }
        Map<String, User> byUsername = new Map<String, User>();
        for (User internal : [
            SELECT Id, Username, ManagerId, Manager.IsActive FROM User
            WHERE Username IN :usernames AND IsActive = true AND UserType = 'Standard' WITH SYSTEM_MODE
        ]) {
            byUsername.put(internal.Username.toLowerCase(), internal);
        }
        User executive = executiveName == null ? null : byUsername.get(executiveName.toLowerCase());
        if (executive == null && accountId != null) {
            Id ownerId;
            for (Account partner : [SELECT OwnerId FROM Account WHERE Id = :accountId WITH SYSTEM_MODE]) {
                ownerId = partner.OwnerId;
            }
            for (User owner : [
                SELECT Id, Username, ManagerId, Manager.IsActive FROM User
                WHERE Id = :ownerId AND IsActive = true AND UserType = 'Standard' WITH SYSTEM_MODE
            ]) {
                executive = owner;
            }
        }
        if (executive == null) {
            return null;
        }
        Approvers approvers = new Approvers();
        approvers.executive = executive.Id;
        if (executive.ManagerId != null && executive.Manager.IsActive) {
            approvers.manager = executive.ManagerId;
        } else if (managerName != null && byUsername.containsKey(managerName.toLowerCase())) {
            approvers.manager = byUsername.get(managerName.toLowerCase()).Id;
        }
        return approvers;
    }

    // =====================================================================================================
    // DECISIONS (VisitTrigger)
    // =====================================================================================================

    // Before update: a decision gives the visit its status (approved: the setting's Visit Status, or the Cancelled Visit
    // Status when the lead was closed meanwhile; rejected by the CP Manager: the Visit Rejected Status)
    public static void beforeUpdate(List<Visit__c> visits, Map<Id, Visit__c> oldVisits) {
        String scheduledStatus = settingText(Partner_Portal_Setting__mdt.Visit_Status__c);
        String rejectedStatus = settingText(Partner_Portal_Setting__mdt.Visit_Rejected_Status__c);
        String cancelledStatus = settingText(Partner_Portal_Setting__mdt.Cancelled_Visit_Status__c);
        Set<Id> approvedLeads = new Set<Id>();
        for (Visit__c visit : visits) {
            Visit__c before = oldVisits.get(visit.Id);
            if (before != null && visit.Approval_Status__c != before.Approval_Status__c && visit.Approval_Status__c == APPROVED
                    && visit.Lead__c != null) {
                approvedLeads.add(visit.Lead__c);
            }
        }
        Set<Id> closed = closedLeads(approvedLeads);
        for (Visit__c visit : visits) {
            Visit__c before = oldVisits.get(visit.Id);
            if (before == null || visit.Approval_Status__c == before.Approval_Status__c) {
                continue;
            }
            if (visit.Approval_Status__c == APPROVED && closed.contains(visit.Lead__c) && cancelledStatus != null) {
                visit.Status__c = cancelledStatus;
                visit.Reason_of_Cancellation__c = PARTNER_VISIT_LEAD_CLOSED_REASON;
            } else if (visit.Approval_Status__c == APPROVED && scheduledStatus != null) {
                visit.Status__c = scheduledStatus;
            } else if (visit.Approval_Status__c == REJECTED && rejectedStatus != null) {
                visit.Status__c = rejectedStatus;
            }
        }
    }

    // After insert: a visit saved as completed (by JKP in Salesforce) moves its partner lead to Visited
    public static void afterInsert(List<Visit__c> visits) {
        moveLeadsOfCompletedVisits(visits, null);
    }

    // After update: a request the CP Executive rejected goes to the CP Manager (in a job of its own: the visit is still
    // in its first approval process); an approved one moves its lead to Site Visit Scheduled and the partner is told it
    // is confirmed; a rejected one, that it was not approved. A visit completed (on the portal, or by JKP in Salesforce)
    // moves its partner lead to Visited.
    public static void afterUpdate(List<Visit__c> visits, Map<Id, Visit__c> oldVisits) {
        moveLeadsOfCompletedVisits(visits, oldVisits);
        String scheduledStatus = settingText(Partner_Portal_Setting__mdt.Visit_Status__c);
        Set<Id> toManager = new Set<Id>();
        Set<Id> scheduledLeads = new Set<Id>();
        Set<Id> confirmed = new Set<Id>();
        Set<Id> declined = new Set<Id>();
        for (Visit__c visit : visits) {
            Visit__c before = oldVisits.get(visit.Id);
            if (before == null || visit.Approval_Status__c == before.Approval_Status__c) {
                continue;
            }
            if (visit.Approval_Status__c == REJECTED_BY_EXECUTIVE) {
                toManager.add(visit.Id);
            } else if (visit.Approval_Status__c == APPROVED && visit.Status__c == scheduledStatus) {
                confirmed.add(visit.Id);
                if (visit.Lead__c != null) {
                    scheduledLeads.add(visit.Lead__c);
                }
            } else if (visit.Approval_Status__c == REJECTED) {
                declined.add(visit.Id);
            }
        }
        if (!toManager.isEmpty()) {
            if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
                System.enqueueJob(new Escalation(toManager));
            } else {
                System.debug(LoggingLevel.ERROR, 'Site visit requests not sent to the CP Manager (no job left): ' + toManager);
            }
        }
        if (!scheduledLeads.isEmpty()) {
            moveLeads(scheduledLeads, ACTION_REQUEST);
        }
        emailOwners(confirmed, settingText(Partner_Portal_Setting__mdt.Visit_Confirmed_Email_Template__c), new Map<Id, String>());
        emailOwners(declined, settingText(Partner_Portal_Setting__mdt.Visit_Rejected_Email_Template__c), rejectionComments(declined));
    }

    // The leads of the visits that became completed (the Completed Visit Status) move to Visited, when they are partner
    // leads still open (see moveLeads)
    private static void moveLeadsOfCompletedVisits(List<Visit__c> visits, Map<Id, Visit__c> oldVisits) {
        String completed = settingText(Partner_Portal_Setting__mdt.Completed_Visit_Status__c);
        if (completed == null) {
            return;
        }
        Set<Id> leadIds = new Set<Id>();
        for (Visit__c visit : visits) {
            Visit__c before = oldVisits == null ? null : oldVisits.get(visit.Id);
            if (visit.Lead__c != null && visit.Status__c == completed && (before == null || before.Status__c != completed)) {
                leadIds.add(visit.Lead__c);
            }
        }
        if (!leadIds.isEmpty()) {
            moveLeads(leadIds, ACTION_COMPLETE);
        }
    }

    // The approver's comment on the rejection of each visit (its latest rejected step), for the email; none when the
    // approver gave no comment
    private static Map<Id, String> rejectionComments(Set<Id> visitIds) {
        Map<Id, String> comments = new Map<Id, String>();
        if (visitIds.isEmpty()) {
            return comments;
        }
        Set<Id> seen = new Set<Id>();
        for (ProcessInstanceStep step : [
            SELECT ProcessInstance.TargetObjectId, Comments FROM ProcessInstanceStep
            WHERE ProcessInstance.TargetObjectId IN :visitIds AND StepStatus = 'Rejected'
            WITH SYSTEM_MODE ORDER BY CreatedDate DESC
        ]) {
            Id visitId = step.ProcessInstance.TargetObjectId;
            if (seen.add(visitId) && String.isNotBlank(step.Comments)) {
                comments.put(visitId, step.Comments.trim());
            }
        }
        return comments;
    }

    // Sends the requests the CP Executive rejected to the CP Manager. A request that cannot be sent is rejected (and
    // the partner emailed, see afterUpdate), so that it does not wait for nobody.
    public class Escalation implements Queueable {
        private final Set<Id> visitIds;

        public Escalation(Set<Id> visitIds) {
            this.visitIds = visitIds;
        }

        public void execute(QueueableContext context) {
            List<Visit__c> visits = [
                SELECT Id FROM Visit__c WHERE Id IN :visitIds AND Approval_Status__c = :REJECTED_BY_EXECUTIVE WITH SYSTEM_MODE
            ];
            if (visits.isEmpty()) {
                return;
            }
            List<Id> ids = new List<Id>();
            for (Visit__c visit : visits) {
                visit.Approval_Status__c = PENDING_MANAGER;
                ids.add(visit.Id);
            }
            Database.update(visits, AccessLevel.SYSTEM_MODE);
            List<Id> notSent = submit(ids, MANAGER_PROCESS, false);
            if (notSent.isEmpty()) {
                return;
            }
            List<Visit__c> refused = new List<Visit__c>();
            for (Id visitId : notSent) {
                refused.add(new Visit__c(Id = visitId, Approval_Status__c = REJECTED));
            }
            Database.update(refused, false, AccessLevel.SYSTEM_MODE);
        }
    }

    // =====================================================================================================
    // COMPLETE
    // =====================================================================================================

    // The lead's visits the partner can mark completed: the scheduled ones (the Open Visit Statuses), earliest first
    public static List<Visit__c> scheduledVisits(Id leadId) {
        Map<String, Object> binds = new Map<String, Object>{ 'leadId' => leadId };
        return Database.queryWithBinds(
            'SELECT Id, Name, Visit_Date__c, Visit_Time__c, Status__c, Project__r.Name FROM Visit__c WHERE Lead__c = :leadId AND '
                + scheduledCondition(binds) + ' ORDER BY Visit_Date__c ASC NULLS LAST, Name ASC LIMIT 20',
            binds, AccessLevel.SYSTEM_MODE);
    }

    // The partner marks one of the lead's scheduled visits completed (on or after its day): the visit gets the
    // Completed Visit Status and the lead moves to Visited
    public static void complete(Lead customer, Id visitId) {
        Visit__c visit;
        for (Visit__c candidate : scheduledVisits(customer.Id)) {
            if (candidate.Id == visitId) {
                visit = candidate;
            }
        }
        if (visit == null) {
            throw new VisitException(PARTNER_VISIT_CHOOSE_VISIT);
        }
        String notYet = notYetReason(visit);
        if (notYet != null) {
            throw new VisitException(notYet);
        }
        String completed = settingText(Partner_Portal_Setting__mdt.Completed_Visit_Status__c);
        String stage = stageFor(ACTION_COMPLETE);
        if (completed == null || stage == null) {
            throw new VisitException(PARTNER_LEAD_EDIT_STATUS_UNKNOWN);
        }
        Savepoint beforeSave = Database.setSavepoint();
        try {
            Database.update(new Visit__c(Id = visit.Id, Status__c = completed), AccessLevel.SYSTEM_MODE);
            Database.update(new Lead(Id = customer.Id, Status = stage), AccessLevel.SYSTEM_MODE);
        } catch (DmlException e) {
            Database.rollback(beforeSave);
            throw new VisitException(e.getDmlMessage(0));
        }
    }

    // Why the visit cannot be marked completed yet (its day, or today its time, is still ahead), or null
    public static String notYetReason(Visit__c visit) {
        if (visit.Visit_Date__c == null || visit.Visit_Date__c < Date.today()) {
            return null;
        }
        if (visit.Visit_Date__c > Date.today()) {
            return String.format(PARTNER_VISIT_NOT_YET, new List<Object>{ dateText(visit.Visit_Date__c) });
        }
        if (visit.Visit_Time__c != null && Datetime.newInstance(visit.Visit_Date__c, visit.Visit_Time__c) > Datetime.now()) {
            return String.format(PARTNER_VISIT_NOT_YET_TODAY, new List<Object>{ timeText(visit.Visit_Time__c) });
        }
        return null;
    }

    // The customer did not come to one of the lead's scheduled visits (on or after its day and time): the visit gets the
    // Not Visited Status and the lead keeps its stage, so that the partner can raise a new site visit request (the
    // chart's Visited? No)
    public static void markNotVisited(Lead customer, Id visitId) {
        Visit__c visit;
        for (Visit__c candidate : scheduledVisits(customer.Id)) {
            if (candidate.Id == visitId) {
                visit = candidate;
            }
        }
        if (visit == null) {
            throw new VisitException(PARTNER_VISIT_NOT_SCHEDULED);
        }
        if (notYetReason(visit) != null) {
            throw new VisitException(PARTNER_VISIT_NOT_VISITED_TOO_EARLY);
        }
        String notVisited = settingText(Partner_Portal_Setting__mdt.Not_Visited_Status__c);
        if (notVisited == null) {
            throw new VisitException(PARTNER_LEAD_EDIT_STATUS_UNKNOWN);
        }
        try {
            Database.update(new Visit__c(Id = visit.Id, Status__c = notVisited), AccessLevel.SYSTEM_MODE);
        } catch (DmlException e) {
            throw new VisitException(e.getDmlMessage(0));
        }
    }

    // Cancels the lead's scheduled visits with the reason (a lead the partner hands over to JKP); a visit that cannot be
    // saved does not stop the hand-over
    public static void cancelScheduledVisits(Id leadId, String reason) {
        String cancelledStatus = settingText(Partner_Portal_Setting__mdt.Cancelled_Visit_Status__c);
        if (cancelledStatus == null) {
            return;
        }
        List<Visit__c> visits = scheduledVisits(leadId);
        for (Visit__c visit : visits) {
            visit.Status__c = cancelledStatus;
            visit.Reason_of_Cancellation__c = reason;
        }
        for (Database.SaveResult result : Database.update(visits, false, AccessLevel.SYSTEM_MODE)) {
            if (!result.isSuccess()) {
                System.debug(LoggingLevel.ERROR, 'Site visit not cancelled: ' + result.getErrors());
            }
        }
    }

    // =====================================================================================================
    // HELPERS
    // =====================================================================================================

    // The lead stage of a visit action (the Partner Portal Lead Status with that Visit Action, in any capitals); null
    // when none
    public static String stageFor(String action) {
        if (stageByAction == null) {
            stageByAction = new Map<String, String>();
            for (Partner_Portal_Lead_Status__mdt config : [
                SELECT Lead_Status__c, Visit_Action__c FROM Partner_Portal_Lead_Status__mdt WHERE Visit_Action__c != null WITH SYSTEM_MODE
            ]) {
                stageByAction.put(config.Visit_Action__c.trim().toLowerCase(), config.Lead_Status__c);
            }
        }
        return action == null ? null : stageByAction.get(action.trim().toLowerCase());
    }

    // The visit action of a Partner Portal Lead Status, as Request or Complete whatever its capitals; null when none
    public static String actionOf(String visitAction) {
        if (String.isBlank(visitAction)) {
            return null;
        }
        String action = visitAction.trim();
        if (action.equalsIgnoreCase(ACTION_REQUEST)) {
            return ACTION_REQUEST;
        }
        return action.equalsIgnoreCase(ACTION_COMPLETE) ? ACTION_COMPLETE : action;
    }

    // The leads among these that are no longer the partner's open leads: booked, lost to another partner, or taken over
    // by JKP (a queue owns them)
    private static Set<Id> closedLeads(Set<Id> leadIds) {
        Set<Id> closed = new Set<Id>();
        if (leadIds.isEmpty()) {
            return closed;
        }
        String lostStatus = settingText(Partner_Portal_Setting__mdt.CP_Lead_Lost_Status__c);
        List<Lead> leads = [SELECT Id, Status, OwnerId, IsConverted FROM Lead WHERE Id IN :leadIds WITH SYSTEM_MODE];
        Set<Id> ownerIds = new Set<Id>();
        for (Lead record : leads) {
            ownerIds.add(record.OwnerId);
        }
        partnerWebPortalLeadEditController.loadOwners(ownerIds);
        for (Lead record : leads) {
            if (record.IsConverted || (lostStatus != null && record.Status == lostStatus)
                    || !partnerWebPortalLeadEditController.isPartnerUser(record.OwnerId)) {
                closed.add(record.Id);
            }
        }
        return closed;
    }

    // The leads of approved requests move to Site Visit Scheduled, unless meanwhile they were closed (see closedLeads)
    // or they are already Visited (a repeat visit does not take the lead back). A lead that cannot be saved does not stop
    // the approval.
    private static void moveLeads(Set<Id> leadIds, String action) {
        String stage = stageFor(action);
        if (stage == null) {
            return;
        }
        String visited = stageFor(ACTION_COMPLETE);
        Set<Id> closed = closedLeads(leadIds);
        List<Lead> changes = new List<Lead>();
        for (Lead record : [SELECT Id, Status FROM Lead WHERE Id IN :leadIds WITH SYSTEM_MODE]) {
            if (record.Status == stage || (visited != null && record.Status == visited) || closed.contains(record.Id)) {
                continue;
            }
            changes.add(new Lead(Id = record.Id, Status = stage));
        }
        for (Database.SaveResult result : Database.update(changes, false, AccessLevel.SYSTEM_MODE)) {
            if (!result.isSuccess()) {
                System.debug(LoggingLevel.ERROR, 'Lead not moved to ' + stage + ': ' + result.getErrors());
            }
        }
    }

    // Sends the visits to the approval process; returns the ones that could not be sent (orThrow: throws instead)
    private static List<Id> submit(List<Id> visitIds, String processName, Boolean orThrow) {
        List<Approval.ProcessSubmitRequest> submissions = new List<Approval.ProcessSubmitRequest>();
        for (Id visitId : visitIds) {
            Approval.ProcessSubmitRequest submission = new Approval.ProcessSubmitRequest();
            submission.setObjectId(visitId);
            submission.setProcessDefinitionNameOrId(processName);
            submissions.add(submission);
        }
        List<Id> notSent = new List<Id>();
        List<Approval.ProcessResult> results = Approval.process(submissions, false);
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                if (orThrow) {
                    throw new VisitException(PARTNER_VISIT_NOT_SENT + ' (' + results[i].getErrors()[0].getMessage() + ')');
                }
                System.debug(LoggingLevel.ERROR, 'Site visit request ' + visitIds[i] + ' not sent: ' + results[i].getErrors());
                notSent.add(visitIds[i]);
            }
        }
        return notSent;
    }

    // What the site visit email templates leave for this class to fill in. A classic template shows the lead of a visit
    // as "name, company" and has no say in how a date or a time is written.
    private static final String CUSTOMER_TOKEN = '[[Customer]]';
    private static final String VISIT_DATE_TOKEN = '[[Visit Date]]';
    private static final String VISIT_TIME_TOKEN = '[[Visit Time]]';

    // Emails the partners who requested these visits (their owners), with the email template of this name: its merge
    // fields are the visit's and the owner's, the tokens above are filled in here, and [[Reason]] is the visit's reason
    // (PartnerEmailSender; a template without a place for it gets the reason as its last line). An email that cannot
    // be written or sent does not stop the decision.
    private static void emailOwners(Set<Id> visitIds, String templateName, Map<Id, String> reasons) {
        if (visitIds.isEmpty() || templateName == null) {
            return;
        }
        try {
            List<EmailTemplate> templates = [SELECT Id FROM EmailTemplate WHERE DeveloperName = :templateName WITH SYSTEM_MODE LIMIT 1];
            if (templates.isEmpty()) {
                System.debug(LoggingLevel.ERROR, 'Site visit email template not found: ' + templateName);
                return;
            }
            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
            for (Visit__c visit : [
                SELECT Id, OwnerId, Visit_Date__c, Visit_Time__c, Lead__r.Name
                FROM Visit__c WHERE Id IN :visitIds WITH SYSTEM_MODE
            ]) {
                if (visit.OwnerId.getSObjectType() != User.SObjectType) {
                    continue;
                }
                Messaging.SingleEmailMessage rendered = Messaging.renderStoredEmailTemplate(templates[0].Id, visit.OwnerId, visit.Id);
                Map<String, String> values = emailValues(visit);
                String reason = reasons.get(visit.Id);
                String reasonLine = reason == null ? null
                    : String.format(PARTNER_VISIT_REJECTION_COMMENT, new List<Object>{ reason });

                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setTargetObjectId(visit.OwnerId);
                email.setSubject(PartnerEmailSender.fill(rendered.getSubject(), values));
                String body = PartnerEmailSender.textWithReason(
                    PartnerEmailSender.fill(rendered.getPlainTextBody(), values), reason, reasonLine);
                email.setPlainTextBody(body);
                // The templates in the John Keells design have both versions; a text-only one sends as before
                if (String.isNotBlank(rendered.getHtmlBody())) {
                    email.setHtmlBody(PartnerEmailSender.htmlWithReason(
                        PartnerEmailSender.fillHtml(rendered.getHtmlBody(), values), reason, reasonLine));
                }
                emailBodies.add(body);
                email.setSaveAsActivity(false);
                emails.add(email);
            }
            emailsWritten += emails.size();
            if (!emails.isEmpty()) {
                for (Messaging.SendEmailResult result : PartnerEmailSender.send(emails)) {
                    if (!result.isSuccess()) {
                        System.debug(LoggingLevel.ERROR, 'Site visit email not sent: ' + result.getErrors());
                    }
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Site visit email not sent: ' + e.getMessage());
        }
    }

    // The customer's name and the day and time of a visit, as its email shows them ("12 Oct 2026", "10:30 AM")
    private static Map<String, String> emailValues(Visit__c visit) {
        return new Map<String, String>{
            CUSTOMER_TOKEN => visit.Lead__r == null ? '' : visit.Lead__r.Name,
            VISIT_DATE_TOKEN => dateText(visit.Visit_Date__c),
            VISIT_TIME_TOKEN => timeText(visit.Visit_Time__c)
        };
    }

    // A Requirement Type value of the visit; refused when blank or not a value of the picklist
    private static String requirementTypeOf(String value) {
        String text = value == null ? '' : value.trim();
        for (PicklistEntry entry : Visit__c.Requirement_Type__c.getDescribe().getPicklistValues()) {
            if (entry.isActive() && entry.getValue() == text) {
                return text;
            }
        }
        throw new VisitException(required(Visit__c.Requirement_Type__c));
    }

    // The visit's Requirement Type choices
    public static List<Map<String, String>> requirementTypes() {
        List<Map<String, String>> options = new List<Map<String, String>>();
        for (PicklistEntry entry : Visit__c.Requirement_Type__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                options.add(new Map<String, String>{ 'label' => entry.getLabel(), 'value' => entry.getValue() });
            }
        }
        return options;
    }

    // "10:30 AM" or "14:05" as a Time; null when it is not a time of day
    public static Time timeOf(String text) {
        if (String.isBlank(text)) {
            return null;
        }
        Matcher twelve = TWELVE_HOUR_TIME.matcher(text);
        if (twelve.matches()) {
            Integer hours = Integer.valueOf(twelve.group(1));
            Integer minutes = Integer.valueOf(twelve.group(2));
            if (hours < 1 || hours > 12 || minutes > 59) {
                return null;
            }
            return Time.newInstance(Math.mod(hours, 12) + (twelve.group(3).equalsIgnoreCase('PM') ? 12 : 0), minutes, 0, 0);
        }
        Matcher twentyFour = TWENTY_FOUR_HOUR_TIME.matcher(text);
        if (twentyFour.matches()) {
            Integer hours = Integer.valueOf(twentyFour.group(1));
            Integer minutes = Integer.valueOf(twentyFour.group(2));
            return hours > 23 || minutes > 59 ? null : Time.newInstance(hours, minutes, 0, 0);
        }
        return null;
    }

    // "10:30 AM"
    public static String timeText(Time value) {
        return value == null ? '' : Datetime.newInstance(Date.today(), value).format('h:mm a');
    }

    // "12 Oct 2026"
    public static String dateText(Date value) {
        return value == null ? '-' : Datetime.newInstance(value, Time.newInstance(12, 0, 0, 0)).format('d MMM yyyy');
    }

    // The visit statuses that count as scheduled (the Open Visit Statuses); a request waiting for approval is told by
    // its Approval Status
    private static Set<String> openStatuses() {
        Set<String> statuses = new Set<String>();
        String open = settingText(Partner_Portal_Setting__mdt.Open_Visit_Statuses__c);
        if (open != null) {
            for (String part : open.split(',')) {
                if (String.isNotBlank(part)) {
                    statuses.add(part.trim());
                }
            }
        }
        return statuses;
    }

    private static String required(SObjectField field) {
        return String.format(PARTNER_LEAD_EDIT_FIELD_REQUIRED, new List<Object>{ field.getDescribe().getLabel() });
    }

    private static String settingText(SObjectField field) {
        if (setting == null) {
            return null;
        }
        Object value = setting.get(field);
        return value == null || String.isBlank(String.valueOf(value)) ? null : String.valueOf(value).trim();
    }
}