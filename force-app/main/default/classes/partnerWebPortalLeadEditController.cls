// The Edit popup of the Partner Portal's Leads page (the Lead Nurturing chart): a channel partner moves their own lead
// to another stage and records what goes with that stage, as the Partner Portal Lead Status records say. A stage shows
// its own Lead fields and those of the stages a lead passes on the way to it (Previous Stages), and on the portal every
// one of them, and the call log, is optional: a channel partner may change the stage without filling them, while a value
// that is given must make sense (and an empty one never clears what the lead has). Nothing is filled in for them: a call
// log is saved only when they filled any of it, with what they gave:
//  - a call log (Call Disposition) for the call stages: Call Date Time and Subject, with the Follow Up Date Time where
//    the stage asks for it (In-Discussion); Description is optional;
//  - the Lead fields the stage needs (Loss Reason for Not Interested, with Other Loss Reason when it is Other; the
//    qualification fields for Contacted; Qualification Status Reason for Qualified and Not Qualified);
//  - the JKP queue that takes the lead over (Not Interested → Re-Marketing Queue), after which the partner sees it
//    read-only; its scheduled site visits are cancelled;
//  - a site visit (the Visit Action of the stage): Site Visit Scheduled sends a site visit request (for the lead's
//    project: requirement type, date and time) for approval, and the lead moves there once it is approved; Visited
//    marks one of the lead's scheduled visits completed (PartnerSiteVisitService).
// Visited? No: the partner marks a scheduled visit the customer did not come to as Not Visited, and can request another.
// The Lead Freezing Window: the popup shows the lead's Freezing Date, and the partner can ask the CP Manager for more
// days (PartnerLeadFreeze); a frozen lead (moved to the Partnership Queue) is read-only.
// Only the partner's own leads can be edited: a channel head sees their executives' leads read-only, and nobody edits a
// lead JKP owns (a queue or an internal user), a lead waiting for the managers' approval, a booked lead, or one another
// partner won. A call stage (and a site visit stage) can be chosen again while the lead is at it, to log another call.
// Partners cannot read or update leads directly, so this runs without sharing and in system mode, and every lead is
// checked against the logged-in partner (PartnerPortalAccess).
public without sharing class partnerWebPortalLeadEditController {

    // A Lead field the stage needs, as the popup shows it
    public class FieldInfo {
        @AuraEnabled public String apiName;
        @AuraEnabled public String label;
        // picklist, number, text, textarea, date, datetime, checkbox
        @AuraEnabled public String type;
        @AuraEnabled public List<Map<String, String>> options = new List<Map<String, String>>();
        @AuraEnabled public String value;
        @AuraEnabled public Integer maxLength;
    }

    // A stage the lead can move to
    public class StatusOption {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
        @AuraEnabled public String description;
        @AuraEnabled public String callDisposition;
        @AuraEnabled public Boolean followUpRequired = false;
        @AuraEnabled public List<FieldInfo> fields = new List<FieldInfo>();
        @AuraEnabled public String ownerQueue;
        @AuraEnabled public String visitAction;
        @AuraEnabled public Boolean current = false;
        // The stage can be chosen again while the lead is at it: another call, another visit request or visit
        @AuraEnabled public Boolean repeatable = false;
        // Why the stage cannot be chosen now (a site visit stage), or null
        @AuraEnabled public String unavailableReason;
    }

    // What the site visit stages need: the request's choices and the lead's scheduled visits. A request is for the lead's
    // project, which the popup shows read-only; only an old lead without a project offers the partner's projects.
    public class VisitForm {
        @AuraEnabled public List<Map<String, String>> projects = new List<Map<String, String>>();
        @AuraEnabled public String projectId;
        @AuraEnabled public String projectName;
        // The project is the lead's, shown read-only; false for an old lead without a project, which offers projects
        @AuraEnabled public Boolean projectFromLead = false;
        @AuraEnabled public List<Map<String, String>> requirementTypes = new List<Map<String, String>>();
        @AuraEnabled public String requirementType;
        @AuraEnabled public String today;
        @AuraEnabled public String projectLabel;
        @AuraEnabled public String requirementTypeLabel;
        @AuraEnabled public String dateLabel;
        @AuraEnabled public String timeLabel;
        @AuraEnabled public String descriptionLabel;
        @AuraEnabled public String requestNote;
        @AuraEnabled public String completeNote;
        @AuraEnabled public List<VisitChoice> scheduled = new List<VisitChoice>();
    }

    // A scheduled visit the partner can mark completed (from its day on)
    public class VisitChoice {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String projectName;
        @AuraEnabled public String whenText;
        @AuraEnabled public Boolean canComplete = false;
        @AuraEnabled public String note;
    }

    public class EditOptions {
        @AuraEnabled public Id leadId;
        @AuraEnabled public String leadName;
        @AuraEnabled public String currentStatus;
        @AuraEnabled public String projectName;
        @AuraEnabled public Boolean canEdit = false;
        @AuraEnabled public String readOnlyReason;
        @AuraEnabled public List<StatusOption> statuses = new List<StatusOption>();
        // The Other Loss Reason field, shown when Loss Reason is Other
        @AuraEnabled public FieldInfo otherLossReason;
        @AuraEnabled public String otherLossReasonTrigger;
        @AuraEnabled public Integer subjectMaxLength;
        @AuraEnabled public VisitForm visit;
        // The Lead Freezing Window: the Freezing Date and whether more time can be asked for
        @AuraEnabled public PartnerLeadFreeze.FreezeInfo freeze;
    }

    public class SaveResult {
        @AuraEnabled public String status;
        @AuraEnabled public String message;
        @AuraEnabled public Boolean handedToJkp = false;
        // A site visit request was sent: the lead keeps its stage until it is approved
        @AuraEnabled public Boolean visitRequested = false;
    }

    // The value of Loss Reason that needs Other Loss Reason
    private static final String OTHER_LOSS_REASON = 'Other';

    // The site visit values the page sends
    private static final String VISIT_PROJECT = 'visitProjectId';
    private static final String VISIT_REQUIREMENT_TYPE = 'visitRequirementType';
    private static final String VISIT_DATE = 'visitDate';
    private static final String VISIT_TIME = 'visitTime';
    private static final String VISIT_DESCRIPTION = 'visitDescription';
    private static final String VISIT_ID = 'visitId';

    // The stages a partner can choose, in order; tests set their own
    @TestVisible
    private static List<Partner_Portal_Lead_Status__mdt> statusOverride;

    // =====================================================================================================
    // LOAD
    // =====================================================================================================

    @AuraEnabled
    public static EditOptions getEditOptions(Id leadId) {
        Lead record = leadOf(leadId);
        EditOptions options = new EditOptions();
        options.leadId = record.Id;
        options.leadName = record.Name;
        options.currentStatus = record.Status;
        options.projectName = record.Project__r == null ? null : record.Project__r.Name;
        options.readOnlyReason = readOnlyReason(record, PartnerPortalAccess.current());
        options.canEdit = options.readOnlyReason == null;
        options.subjectMaxLength = Call_Disposition__c.Subject__c.getDescribe().getLength();
        if (!options.canEdit) {
            return options;
        }
        options.freeze = PartnerLeadFreeze.infoOf(record);
        List<Partner_Portal_Lead_Status__mdt> configs = statuses();
        for (Partner_Portal_Lead_Status__mdt config : configs) {
            if (String.isNotBlank(config.Visit_Action__c)) {
                options.visit = visitFormOf(record);
                break;
            }
        }
        for (Partner_Portal_Lead_Status__mdt config : configs) {
            StatusOption option = new StatusOption();
            option.value = config.Lead_Status__c;
            option.label = statusLabel(config.Lead_Status__c);
            option.description = config.Description__c;
            option.callDisposition = blankToNull(config.Call_Disposition__c);
            option.followUpRequired = config.Follow_Up_Required__c;
            option.ownerQueue = blankToNull(config.Owner_Queue__c);
            option.visitAction = PartnerSiteVisitService.actionOf(config.Visit_Action__c);
            option.current = config.Lead_Status__c == record.Status;
            option.repeatable = option.ownerQueue == null && (option.callDisposition != null
                || option.visitAction == PartnerSiteVisitService.ACTION_REQUEST || option.visitAction == PartnerSiteVisitService.ACTION_COMPLETE);
            for (String fieldName : stageFields(config)) {
                option.fields.add(fieldInfo(fieldName, record));
            }
            if (option.visitAction == PartnerSiteVisitService.ACTION_REQUEST) {
                option.unavailableReason = PartnerSiteVisitService.blockedReason(record.Id);
                // A request is for the lead's project: none while that project is not open for site visits
                if (option.unavailableReason == null) {
                    option.unavailableReason = PartnerSiteVisitService.projectNotOpenReason(record.Project__r);
                }
            } else if (option.visitAction == PartnerSiteVisitService.ACTION_COMPLETE && options.visit.scheduled.isEmpty()) {
                option.unavailableReason = Label.Partner_Visit_None_To_Complete;
            }
            options.statuses.add(option);
        }
        options.otherLossReason = fieldInfo('Other_Loss_Reason__c', record);
        options.otherLossReasonTrigger = OTHER_LOSS_REASON;
        return options;
    }

    // =====================================================================================================
    // SAVE
    // =====================================================================================================

    // Moves the lead to the stage with what it needs. values: callDateTime and followUpDateTime (ISO date times),
    // subject, description, and the stage's Lead fields by API name; for a site visit request visitProjectId (the
    // lead's project), visitRequirementType, visitDate (2026-10-12), visitTime (14:30) and visitDescription; for a
    // completed visit visitId. Every Lead field and the call log are optional; refused, with the reason, when a value
    // given is wrong (a call in the future, a follow-up in the past, a number that is not above 0) or the change is not
    // allowed.
    @AuraEnabled
    public static SaveResult saveStatus(Id leadId, String status, Map<String, Object> values) {
        Lead record = leadOf(leadId);
        PartnerPortalAccess access = PartnerPortalAccess.current();
        String reason = readOnlyReason(record, access);
        if (reason != null) {
            throw userError(reason);
        }
        Partner_Portal_Lead_Status__mdt config = configFor(status);
        if (config == null) {
            throw userError(Label.Partner_Lead_Edit_Status_Unknown);
        }
        Map<String, Object> input = values == null ? new Map<String, Object>() : values;
        String visitAction = PartnerSiteVisitService.actionOf(config.Visit_Action__c);
        if (visitAction == PartnerSiteVisitService.ACTION_REQUEST) {
            return requestVisit(record, access, config, input);
        }
        if (visitAction == PartnerSiteVisitService.ACTION_COMPLETE) {
            return completeVisit(record, config, input);
        }
        if (visitAction != null) {
            throw userError(Label.Partner_Lead_Edit_Status_Unknown);
        }

        // The Lead fields of the stage, all optional
        Lead change = new Lead(Id = record.Id, Status = config.Lead_Status__c);
        putLeadFields(record, change, config, input);

        // The call log of the stage, only when the partner filled it in
        Call_Disposition__c callLog;
        if (String.isNotBlank(config.Call_Disposition__c)) {
            callLog = callLogOf(record.Id, config, input);
            if (callLog != null && callLog.Follow_Up_DateTime__c != null) {
                change.Lead_Follow_Up_DateTime__c = callLog.Follow_Up_DateTime__c;
            }
        }

        // The JKP queue that takes the lead over
        SaveResult result = new SaveResult();
        if (String.isNotBlank(config.Owner_Queue__c)) {
            List<Group> queues = [
                SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = :config.Owner_Queue__c.trim() WITH SYSTEM_MODE LIMIT 1
            ];
            if (queues.isEmpty()) {
                throw userError(Label.Partner_Lead_Edit_Failed);
            }
            change.OwnerId = queues[0].Id;
            result.handedToJkp = true;
        }

        Savepoint beforeSave = Database.setSavepoint();
        try {
            if (callLog != null) {
                Database.insert(callLog, AccessLevel.SYSTEM_MODE);
            }
            Database.update(change, AccessLevel.SYSTEM_MODE);
            // JKP takes the lead over: its scheduled site visits will not happen with the partner
            if (result.handedToJkp) {
                PartnerSiteVisitService.cancelScheduledVisits(record.Id, Label.Partner_Visit_Not_Interested_Reason);
            }
        } catch (DmlException e) {
            Database.rollback(beforeSave);
            throw userError(e.getDmlMessage(0));
        }
        result.status = config.Lead_Status__c;
        result.message = String.format(Label.Partner_Lead_Edit_Saved, new List<Object>{ statusLabel(config.Lead_Status__c) });
        return result;
    }

    // =====================================================================================================
    // SITE VISITS
    // =====================================================================================================

    // Site Visit Scheduled: the request goes for approval; the lead keeps its stage until it is approved. It is for the
    // lead's project: PartnerSiteVisitService refuses another one, and the lead's project while it is not open for site
    // visits. Only an old lead without a project (from before leads needed one) takes the project the partner chose, as
    // before: one of their active projects (an executive's own). The Lead fields given with it (all optional) are saved
    // with the request.
    private static SaveResult requestVisit(Lead record, PartnerPortalAccess access, Partner_Portal_Lead_Status__mdt config,
            Map<String, Object> input) {
        Id projectId = idOf(input.get(VISIT_PROJECT), Project__c.SObjectType);
        if (projectId == null || (record.Project__c == null && (!access.canSeeProject(projectId)
                || !partnerWebPortalSiteVisit.offeredProjectIds().contains(String.valueOf(projectId))))) {
            throw userError(String.format(Label.Partner_Lead_Edit_Field_Required, new List<Object>{
                Visit__c.Project__c.getDescribe().getLabel() }));
        }
        Date visitDate;
        try {
            visitDate = input.get(VISIT_DATE) == null ? null : Date.valueOf(String.valueOf(input.get(VISIT_DATE)).trim());
        } catch (Exception e) {
            visitDate = null;
        }
        Time visitTime = PartnerSiteVisitService.timeOf(input.get(VISIT_TIME) == null ? null : String.valueOf(input.get(VISIT_TIME)));
        Lead change = new Lead(Id = record.Id);
        Boolean fieldsGiven = putLeadFields(record, change, config, input);
        Savepoint beforeSave = Database.setSavepoint();
        try {
            if (fieldsGiven) {
                Database.update(change, AccessLevel.SYSTEM_MODE);
            }
            PartnerSiteVisitService.request(record, projectId, input.get(VISIT_REQUIREMENT_TYPE) == null ? null
                : String.valueOf(input.get(VISIT_REQUIREMENT_TYPE)), visitDate, visitTime,
                input.get(VISIT_DESCRIPTION) == null ? null : String.valueOf(input.get(VISIT_DESCRIPTION)));
        } catch (PartnerSiteVisitService.VisitException e) {
            Database.rollback(beforeSave);
            throw userError(e.getMessage());
        } catch (DmlException e) {
            Database.rollback(beforeSave);
            throw userError(e.getDmlMessage(0));
        }
        SaveResult result = new SaveResult();
        result.status = record.Status;
        result.message = Label.Partner_Visit_Requested;
        result.visitRequested = true;
        return result;
    }

    // Visited: the chosen scheduled visit is completed and the lead moves to the stage, with the Lead fields given (all
    // optional)
    private static SaveResult completeVisit(Lead record, Partner_Portal_Lead_Status__mdt config, Map<String, Object> input) {
        Id visitId = idOf(input.get(VISIT_ID), Visit__c.SObjectType);
        if (visitId == null) {
            throw userError(Label.Partner_Visit_Choose_Visit);
        }
        Lead change = new Lead(Id = record.Id);
        Boolean fieldsGiven = putLeadFields(record, change, config, input);
        Savepoint beforeSave = Database.setSavepoint();
        try {
            if (fieldsGiven) {
                Database.update(change, AccessLevel.SYSTEM_MODE);
            }
            PartnerSiteVisitService.complete(record, visitId);
        } catch (PartnerSiteVisitService.VisitException e) {
            Database.rollback(beforeSave);
            throw userError(e.getMessage());
        } catch (DmlException e) {
            Database.rollback(beforeSave);
            throw userError(e.getDmlMessage(0));
        }
        SaveResult result = new SaveResult();
        result.status = config.Lead_Status__c;
        result.message = String.format(Label.Partner_Lead_Edit_Saved, new List<Object>{ statusLabel(config.Lead_Status__c) });
        return result;
    }

    // Visited? No: the customer did not come to the chosen scheduled visit; the partner can request a new one
    @AuraEnabled
    public static SaveResult markNotVisited(Id leadId, Id visitId) {
        Lead record = leadOf(leadId);
        String reason = readOnlyReason(record, PartnerPortalAccess.current());
        if (reason != null) {
            throw userError(reason);
        }
        try {
            PartnerSiteVisitService.markNotVisited(record, visitId);
        } catch (PartnerSiteVisitService.VisitException e) {
            throw userError(e.getMessage());
        }
        SaveResult result = new SaveResult();
        result.status = record.Status;
        result.message = Label.Partner_Visit_Not_Visited_Done;
        return result;
    }

    // Grace period: the partner asks the CP Manager for more days in the lead's freezing window
    @AuraEnabled
    public static SaveResult requestGracePeriod(Id leadId, Integer days, String reason) {
        Lead record = leadOf(leadId);
        String readOnly = readOnlyReason(record, PartnerPortalAccess.current());
        if (readOnly != null) {
            throw userError(readOnly);
        }
        try {
            PartnerLeadFreeze.requestGrace(record, days, reason);
        } catch (PartnerLeadFreeze.FreezeException e) {
            throw userError(e.getMessage());
        }
        SaveResult result = new SaveResult();
        result.status = record.Status;
        result.message = Label.Partner_Lead_Grace_Requested;
        return result;
    }

    // The site visit choices of the lead: its project (a lead's site visits are for the project it was created for; an
    // old lead without a project offers the partner's projects instead), the requirement types (the lead's Unit Type
    // first), today, and the lead's scheduled visits
    private static VisitForm visitFormOf(Lead record) {
        VisitForm form = new VisitForm();
        if (record.Project__c != null) {
            form.projectId = String.valueOf(record.Project__c);
            form.projectName = record.Project__r.Name;
            form.projectFromLead = true;
        } else {
            form.projects = partnerWebPortalSiteVisit.getProjectOptions();
        }
        form.requirementTypes = PartnerSiteVisitService.requirementTypes();
        Object unitType = record.get('Unit_Type__c');
        for (Map<String, String> option : form.requirementTypes) {
            if (unitType != null && option.get('value') == String.valueOf(unitType)) {
                form.requirementType = option.get('value');
            }
        }
        form.today = String.valueOf(Date.today());
        form.projectLabel = Visit__c.Project__c.getDescribe().getLabel();
        form.requirementTypeLabel = Visit__c.Requirement_Type__c.getDescribe().getLabel();
        form.dateLabel = Visit__c.Visit_Date__c.getDescribe().getLabel();
        form.timeLabel = Visit__c.Visit_Time__c.getDescribe().getLabel();
        form.descriptionLabel = Visit__c.Visit_Description__c.getDescribe().getLabel();
        form.requestNote = Label.Partner_Visit_Request_Note;
        form.completeNote = Label.Partner_Visit_Complete_Note;
        for (Visit__c visit : PartnerSiteVisitService.scheduledVisits(record.Id)) {
            VisitChoice choice = new VisitChoice();
            choice.id = visit.Id;
            choice.name = visit.Name;
            choice.projectName = visit.Project__r == null ? null : visit.Project__r.Name;
            choice.whenText = PartnerSiteVisitService.dateText(visit.Visit_Date__c)
                + (visit.Visit_Time__c == null ? '' : ', ' + PartnerSiteVisitService.timeText(visit.Visit_Time__c));
            choice.note = PartnerSiteVisitService.notYetReason(visit);
            choice.canComplete = choice.note == null;
            form.scheduled.add(choice);
        }
        return form;
    }

    // An Id of the object from the page; null when blank or another object's
    private static Id idOf(Object value, SObjectType type) {
        if (value == null || String.isBlank(String.valueOf(value))) {
            return null;
        }
        try {
            Id candidate = Id.valueOf(String.valueOf(value).trim());
            return candidate.getSObjectType() == type ? candidate : null;
        } catch (Exception e) {
            return null;
        }
    }

    // =====================================================================================================
    // WHO MAY EDIT
    // =====================================================================================================

    // Owner Ids known to be partner (portal) users or not; filled by loadOwners, or on demand
    private static Map<Id, Boolean> partnerOwners = new Map<Id, Boolean>();

    // Finds out in one query which of these users are partner users (the Leads page calls it for a page of leads)
    public static void loadOwners(Set<Id> ownerIds) {
        Set<Id> unknown = new Set<Id>();
        for (Id ownerId : ownerIds) {
            if (ownerId != null && ownerId.getSObjectType() == User.SObjectType && !partnerOwners.containsKey(ownerId)) {
                unknown.add(ownerId);
            }
        }
        if (unknown.isEmpty()) {
            return;
        }
        for (Id ownerId : unknown) {
            partnerOwners.put(ownerId, false);
        }
        for (User owner : [SELECT Id FROM User WHERE Id IN :unknown AND ContactId != null WITH SYSTEM_MODE]) {
            partnerOwners.put(owner.Id, true);
        }
    }

    // Whether the user is a partner (portal) user; a queue or an internal user is JKP
    public static Boolean isPartnerUser(Id userId) {
        if (userId == null || userId.getSObjectType() != User.SObjectType) {
            return false;
        }
        loadOwners(new Set<Id>{ userId });
        return partnerOwners.get(userId);
    }

    // Why the partner cannot edit the lead, or null when they can: only their own open lead (a channel head's
    // executives update their own leads), not one JKP owns (a queue or an internal user), one waiting for approval, a
    // booked one or one another partner won
    @TestVisible
    private static String readOnlyReason(Lead record, PartnerPortalAccess access) {
        if (access == null || access.accountId == null) {
            return Label.Partner_Portal_No_Access;
        }
        if (record.Channel_Partner__c != access.accountId) {
            return Label.Partner_Lead_Read_Only_Team;
        }
        if (record.IsConverted) {
            return Label.Partner_Lead_Read_Only_Booked;
        }
        if (record.CP_Approval_Status__c == LeadLogicController.CP_APPROVAL_PENDING) {
            return Label.Partner_Lead_Read_Only_Waiting;
        }
        String lostStatus = Partner_Portal_Setting__mdt.getInstance('Default') == null ? null
            : Partner_Portal_Setting__mdt.getInstance('Default').CP_Lead_Lost_Status__c;
        if (String.isNotBlank(lostStatus) && record.Status == lostStatus.trim()) {
            return Label.Partner_Lead_Read_Only_Lost;
        }
        if (!isPartnerUser(record.OwnerId)) {
            // No site visit within the freezing window: the Partnership Queue took the lead (PartnerLeadFreeze)
            if (record.OwnerId != null && record.OwnerId == PartnerLeadFreeze.partnershipQueueId()) {
                return Label.Partner_Lead_Read_Only_Frozen;
            }
            // After the site visit the JKP CP team takes the lead over (PartnerLeadHandover)
            String handOver = Partner_Portal_Setting__mdt.getInstance('Default') == null ? null
                : Partner_Portal_Setting__mdt.getInstance('Default').Hand_Over_Lead_Status__c;
            return String.isNotBlank(handOver) && record.Status == handOver.trim() ? Label.Partner_Lead_Read_Only_Taken_Over
                : Label.Partner_Lead_Read_Only_Jkp;
        }
        return null;
    }

    // Whether the logged-in partner may edit the lead (the Leads page's Edit button)
    public static Boolean canEdit(Lead record, PartnerPortalAccess access) {
        return readOnlyReason(record, access) == null;
    }

    // The reason shown on a read-only row of the Leads page
    public static String readOnlyReasonOf(Lead record, PartnerPortalAccess access) {
        return readOnlyReason(record, access);
    }

    // The lead, when it is one of the partner's team's leads (a rejected one is not theirs), with its project
    // (PartnerSiteVisitService keeps a site visit to it)
    private static Lead leadOf(Id leadId) {
        PartnerPortalAccess access = PartnerPortalAccess.current();
        if (leadId == null || access.accountId == null) {
            throw userError(Label.Partner_Portal_No_Access);
        }
        Map<String, Object> binds = new Map<String, Object>{ 'leadId' => leadId };
        List<Lead> leads = Database.queryWithBinds(
            'SELECT Id, Name, Status, OwnerId, IsConverted, CP_Approval_Status__c, Channel_Partner__c, Project__c, Project__r.Name,'
                + ' Project__r.Active__c, CP_Freeze_Date__c, '
                + String.join(new List<String>(editableFields()), ', ')
                + ' FROM Lead WHERE Id = :leadId AND ' + access.leads(binds) + ' LIMIT 1',
            binds, AccessLevel.SYSTEM_MODE);
        if (leads.isEmpty()) {
            throw userError(Label.Partner_Lead_Edit_Not_Found);
        }
        return leads[0];
    }

    // =====================================================================================================
    // HELPERS
    // =====================================================================================================

    private static List<Partner_Portal_Lead_Status__mdt> statuses() {
        if (statusOverride != null) {
            return statusOverride;
        }
        return [
            SELECT DeveloperName, Lead_Status__c, Order__c, Description__c, Call_Disposition__c, Follow_Up_Required__c,
                Required_Lead_Fields__c, Previous_Stages__c, Owner_Queue__c, Visit_Action__c
            FROM Partner_Portal_Lead_Status__mdt
            WITH SYSTEM_MODE
            ORDER BY Order__c ASC NULLS LAST, Lead_Status__c
        ];
    }

    private static Partner_Portal_Lead_Status__mdt configFor(String status) {
        if (String.isBlank(status)) {
            return null;
        }
        for (Partner_Portal_Lead_Status__mdt config : statuses()) {
            if (config.Lead_Status__c == status.trim()) {
                return config;
            }
        }
        return null;
    }

    // The Lead fields a stage shows: those of the stages a lead passes on the way to it (its Previous Stages, in that
    // order), then its own, each once. On the portal every one of them is optional.
    private static List<String> stageFields(Partner_Portal_Lead_Status__mdt config) {
        List<String> sources = new List<String>();
        for (String previous : String.isBlank(config.Previous_Stages__c) ? new List<String>() : config.Previous_Stages__c.split(',')) {
            Partner_Portal_Lead_Status__mdt before = configFor(previous);
            if (before != null && before.Lead_Status__c != config.Lead_Status__c) {
                sources.add(before.Required_Lead_Fields__c);
            }
        }
        sources.add(config.Required_Lead_Fields__c);
        List<String> names = new List<String>();
        for (String source : sources) {
            for (String fieldName : fieldNames(source)) {
                if (!names.contains(fieldName)) {
                    names.add(fieldName);
                }
            }
        }
        return names;
    }

    // Puts on the lead the values the partner changed among the stage's Lead fields (stageFields), each checked against
    // its field. Every one is optional: an empty one changes nothing, so it never clears what the lead already has, and
    // one equal to the lead's (the popup shows the lead's values) is left out. Other Loss Reason goes with Loss Reason
    // Other, given now or before. Returns whether anything changed.
    private static Boolean putLeadFields(Lead record, Lead change, Partner_Portal_Lead_Status__mdt config, Map<String, Object> input) {
        Boolean changed = false;
        for (String fieldName : stageFields(config)) {
            Object value = valueOf(fieldName, input.get(fieldName), false);
            if (value != null && value != record.get(fieldName)) {
                change.put(fieldName, value);
                changed = true;
            }
        }
        Object other = valueOf('Other_Loss_Reason__c', input.get('Other_Loss_Reason__c'), false);
        Object lossReason = change.get('Loss_Reason__c') != null ? change.get('Loss_Reason__c') : record.get('Loss_Reason__c');
        if (other != null && lossReason == OTHER_LOSS_REASON && other != record.get('Other_Loss_Reason__c')) {
            change.Other_Loss_Reason__c = (String) other;
            changed = true;
        }
        return changed;
    }

    // Every Lead field a stage may ask for, plus Other Loss Reason (to read their current values)
    private static Set<String> editableFields() {
        Set<String> names = new Set<String>{ 'Other_Loss_Reason__c', 'Unit_Type__c' };
        for (Partner_Portal_Lead_Status__mdt config : statuses()) {
            names.addAll(fieldNames(config.Required_Lead_Fields__c));
        }
        names.removeAll(new Set<String>{ 'Id', 'Name', 'Status', 'OwnerId', 'IsConverted', 'CP_Approval_Status__c', 'Channel_Partner__c',
            'Project__c', 'CP_Freeze_Date__c' });
        return names;
    }

    // The Lead fields of a comma-separated list that exist on Lead
    private static List<String> fieldNames(String text) {
        List<String> names = new List<String>();
        if (String.isBlank(text)) {
            return names;
        }
        Map<String, SObjectField> leadFields = Lead.SObjectType.getDescribe().fields.getMap();
        for (String part : text.split(',')) {
            String name = part.trim();
            if (String.isNotBlank(name) && leadFields.containsKey(name.toLowerCase())) {
                names.add(leadFields.get(name.toLowerCase()).getDescribe().getName());
            }
        }
        return names;
    }

    private static FieldInfo fieldInfo(String fieldName, Lead record) {
        DescribeFieldResult describe = Lead.SObjectType.getDescribe().fields.getMap().get(fieldName.toLowerCase()).getDescribe();
        FieldInfo info = new FieldInfo();
        info.apiName = describe.getName();
        info.label = describe.getLabel();
        info.type = typeOf(describe.getType());
        if (describe.getType() == DisplayType.PICKLIST || describe.getType() == DisplayType.MULTIPICKLIST) {
            for (PicklistEntry entry : describe.getPicklistValues()) {
                if (entry.isActive()) {
                    info.options.add(new Map<String, String>{ 'label' => entry.getLabel(), 'value' => entry.getValue() });
                }
            }
        }
        if (describe.getType() == DisplayType.STRING || describe.getType() == DisplayType.TEXTAREA) {
            info.maxLength = describe.getLength();
        }
        Object current = record.get(describe.getName());
        info.value = current == null ? null : String.valueOf(current);
        return info;
    }

    private static String typeOf(DisplayType type) {
        if (type == DisplayType.PICKLIST || type == DisplayType.MULTIPICKLIST) {
            return 'picklist';
        }
        if (type == DisplayType.DOUBLE || type == DisplayType.INTEGER || type == DisplayType.LONG || type == DisplayType.CURRENCY
                || type == DisplayType.PERCENT) {
            return 'number';
        }
        if (type == DisplayType.TEXTAREA) {
            return 'textarea';
        }
        if (type == DisplayType.DATE) {
            return 'date';
        }
        if (type == DisplayType.DATETIME) {
            return 'datetime';
        }
        if (type == DisplayType.BOOLEAN) {
            return 'checkbox';
        }
        return 'text';
    }

    // The value the partner gave for a Lead field, checked against the field; null when blank (required: refused)
    private static Object valueOf(String fieldName, Object raw, Boolean required) {
        DescribeFieldResult describe = Lead.SObjectType.getDescribe().fields.getMap().get(fieldName.toLowerCase()).getDescribe();
        String text = raw == null ? '' : String.valueOf(raw).trim();
        if (String.isBlank(text)) {
            if (required) {
                throw userError(String.format(Label.Partner_Lead_Edit_Field_Required, new List<Object>{ describe.getLabel() }));
            }
            return null;
        }
        DisplayType type = describe.getType();
        if (type == DisplayType.PICKLIST) {
            for (PicklistEntry entry : describe.getPicklistValues()) {
                if (entry.isActive() && entry.getValue() == text) {
                    return text;
                }
            }
            throw userError(String.format(Label.Partner_Lead_Edit_Field_Required, new List<Object>{ describe.getLabel() }));
        }
        if (typeOf(type) == 'number') {
            Decimal amount;
            try {
                amount = Decimal.valueOf(text);
            } catch (Exception e) {
                amount = null;
            }
            if (amount == null || amount <= 0) {
                throw userError(String.format(Label.Partner_Lead_Edit_Number_Invalid, new List<Object>{ describe.getLabel() }));
            }
            return type == DisplayType.INTEGER ? (Object) amount.intValue() : (Object) amount;
        }
        if (type == DisplayType.BOOLEAN) {
            return text.equalsIgnoreCase('true');
        }
        if (type == DisplayType.DATE) {
            return Date.valueOf(text);
        }
        if (type == DisplayType.DATETIME) {
            return dateTimeOf(text);
        }
        return text.left(describe.getLength());
    }

    // The call log the stage records, only when the partner filled in any of it: its disposition with the call's date and
    // time (not in the future), subject, description and, where the stage takes one, follow-up (in the future), each as
    // given. Nothing is filled in automatically: with nothing given, no call log is saved (null).
    private static Call_Disposition__c callLogOf(Id leadId, Partner_Portal_Lead_Status__mdt config, Map<String, Object> input) {
        Datetime callAt = dateTimeOf(String.valueOf(input.get('callDateTime')));
        if (callAt != null && callAt > Datetime.now().addMinutes(5)) {
            throw userError(Label.Partner_Lead_Edit_Call_In_Future);
        }
        String subject = input.get('subject') == null ? null : String.valueOf(input.get('subject')).trim();
        String description = input.get('description') == null ? null : String.valueOf(input.get('description')).trim();
        Datetime followUp = config.Follow_Up_Required__c ? dateTimeOf(String.valueOf(input.get('followUpDateTime'))) : null;
        if (followUp != null && followUp <= Datetime.now()) {
            throw userError(Label.Partner_Lead_Edit_Follow_Up_Past);
        }
        if (callAt == null && String.isBlank(subject) && String.isBlank(description) && followUp == null) {
            return null;
        }
        return new Call_Disposition__c(
            Lead__c = leadId,
            Call_Disposition__c = config.Call_Disposition__c.trim(),
            Call_DateTime__c = callAt,
            Subject__c = String.isBlank(subject) ? null : subject.left(Call_Disposition__c.Subject__c.getDescribe().getLength()),
            Description__c = String.isBlank(description) ? null : description,
            Follow_Up_DateTime__c = followUp
        );
    }

    // An ISO 8601 date and time from the page (for example 2026-10-06T08:30:00.000Z); null when blank or not a date time
    private static Datetime dateTimeOf(String value) {
        if (String.isBlank(value) || value == 'null') {
            return null;
        }
        try {
            return (Datetime) JSON.deserialize('"' + value.trim() + '"', Datetime.class);
        } catch (Exception e) {
            return null;
        }
    }

    // The label of a Lead Status value
    private static String statusLabel(String value) {
        for (PicklistEntry entry : Lead.Status.getDescribe().getPicklistValues()) {
            if (entry.getValue() == value) {
                return entry.getLabel();
            }
        }
        return value;
    }

    private static String blankToNull(String value) {
        return String.isBlank(value) ? null : value.trim();
    }

    private static AuraHandledException userError(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}