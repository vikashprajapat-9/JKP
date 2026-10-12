// The Lead Freezing Window and the Lead Ownership Freeze of the Lead Nurturing chart:
//  - Freezing window: from the lead's assignment to a channel partner (a channel partner lead saved for the partner, or
//    approved for them by the managers) its Freezing Date is Lead Freeze Days ahead (Partner Portal Setting, 60). When
//    no site visit has been done (completed) by then, the nightly PartnerLeadFreezeJob moves the lead to the Partnership
//    Queue and emails the partner (Lead Frozen Email Template).
//  - Grace period: in the window the partner can ask on the portal for more days (Lead Grace Day Options) with a reason;
//    the CP Manager (the JKP CP Executive's manager, else the CP Manager Username) approves or rejects it through the CP
//    Lead Grace Period approval (a Partner Access Request of type Lead Grace Period). Approved, the Freezing Date moves
//    on; the partner is emailed either way.
//  - Ownership freeze: the owner of a lead marked as the CP Lead Lost Status (another partner won the customer, on a
//    first site visit or a conversion) cannot be changed by hand.
// Partners cannot see internal records, so this runs without sharing in system mode; the portal controller checks the
// lead belongs to the partner first.
public without sharing class PartnerLeadFreeze {

    public static final String GRACE = 'Lead Grace Period';
    @TestVisible
    private static final String GRACE_PROCESS = 'CP_Lead_Grace_Period';
    private static final String PENDING = 'Pending';
    private static final String APPROVED = 'Approved';
    private static final String REJECTED = 'Rejected';

    // Tests set their own
    @TestVisible
    private static Partner_Portal_Setting__mdt setting = Partner_Portal_Setting__mdt.getInstance('Default');

    // The emails written (for tests: emails are not sent in tests)
    @TestVisible
    private static Integer emailsWritten = 0;

    // What the Edit popup shows about the freezing window
    public class FreezeInfo {
        @AuraEnabled public Boolean inWindow = false;
        @AuraEnabled public String freezeDate;
        @AuraEnabled public String note;
        @AuraEnabled public Boolean canRequest = false;
        @AuraEnabled public Boolean pending = false;
        @AuraEnabled public String pendingNote;
        @AuraEnabled public List<Integer> graceOptions = new List<Integer>();
    }

    public class FreezeException extends Exception {}

    // =====================================================================================================
    // FREEZING DATE AND OWNERSHIP FREEZE (LeadTriggerHandler)
    // =====================================================================================================

    // Before insert (after the channel partner lead rules): a lead saved for a channel partner gets its Freezing Date,
    // unless it waits for the managers' approval (it gets it when approved)
    public static void beforeInsert(List<Lead> leads) {
        Integer days = freezeDays();
        if (days == null) {
            return;
        }
        for (Lead record : leads) {
            if (record.Channel_Partner__c != null && record.CP_Freeze_Date__c == null && !record.IsConverted
                    && record.CP_Approval_Status__c != LeadLogicController.CP_APPROVAL_PENDING
                    && record.CP_Approval_Status__c != LeadLogicController.CP_APPROVAL_REJECTED) {
                record.CP_Freeze_Date__c = Date.today().addDays(days);
            }
        }
    }

    // Before update: the owner of a lead lost to another partner cannot be changed by hand (Lead Ownership Freeze); a
    // lead approved for a channel partner, given to one, or given back to a partner user by JKP gets a new Freezing Date
    public static void beforeUpdate(List<Lead> leads, Map<Id, Lead> oldLeads) {
        if (oldLeads == null) {
            return;
        }
        String lost = settingText(Partner_Portal_Setting__mdt.CP_Lead_Lost_Status__c);
        Integer days = freezeDays();
        Set<Id> owners = new Set<Id>();
        for (Lead record : leads) {
            Lead before = oldLeads.get(record.Id);
            if (before != null && record.OwnerId != before.OwnerId && record.Channel_Partner__c != null) {
                owners.add(record.OwnerId);
                owners.add(before.OwnerId);
            }
        }
        partnerWebPortalLeadEditController.loadOwners(owners);
        for (Lead record : leads) {
            Lead before = oldLeads.get(record.Id);
            if (before == null) {
                continue;
            }
            if (lost != null && before.Status == lost && record.OwnerId != before.OwnerId && !record.IsConverted) {
                record.OwnerId.addError(String.format(Label.CP_Lead_Owner_Frozen, new List<Object>{ lost }));
                continue;
            }
            if (days == null || record.Channel_Partner__c == null || record.IsConverted || (lost != null && record.Status == lost)
                    || record.CP_Approval_Status__c == LeadLogicController.CP_APPROVAL_PENDING
                    || record.CP_Approval_Status__c == LeadLogicController.CP_APPROVAL_REJECTED) {
                continue;
            }
            Boolean approvedNow = before.CP_Approval_Status__c == LeadLogicController.CP_APPROVAL_PENDING;
            Boolean givenNow = before.Channel_Partner__c == null;
            Boolean backToPartner = record.OwnerId != before.OwnerId && !partnerWebPortalLeadEditController.isPartnerUser(before.OwnerId)
                && partnerWebPortalLeadEditController.isPartnerUser(record.OwnerId);
            if (((approvedNow || givenNow) && record.CP_Freeze_Date__c == null) || backToPartner) {
                record.CP_Freeze_Date__c = Date.today().addDays(days);
            }
        }
    }

    // The nightly job's leads: channel partner leads past their Freezing Date, not booked, lost or waiting for approval
    public static Database.QueryLocator dueLeads() {
        Map<String, Object> binds = new Map<String, Object>{
            'today' => Date.today(),
            'closedApprovals' => new Set<String>{ LeadLogicController.CP_APPROVAL_PENDING, LeadLogicController.CP_APPROVAL_REJECTED }
        };
        String query = 'SELECT Id, OwnerId, CP_Freeze_Date__c FROM Lead WHERE CP_Freeze_Date__c <= :today AND IsConverted = false'
            + ' AND Channel_Partner__c != null AND (CP_Approval_Status__c = null OR CP_Approval_Status__c NOT IN :closedApprovals)';
        String lost = settingText(Partner_Portal_Setting__mdt.CP_Lead_Lost_Status__c);
        if (lost != null) {
            binds.put('lost', lost);
            query += ' AND Status != :lost';
        }
        return Database.getQueryLocatorWithBinds(query, binds, AccessLevel.SYSTEM_MODE);
    }

    // =====================================================================================================
    // THE NIGHTLY FREEZE (PartnerLeadFreezeJob)
    // =====================================================================================================

    // The leads among these whose window ended without a site visit, still the partner's, move to the Partnership Queue;
    // their partners are emailed
    public static void freeze(List<Lead> leads) {
        Id queueId = partnershipQueueId();
        if (queueId == null || leads.isEmpty()) {
            if (queueId == null) {
                System.debug(LoggingLevel.ERROR, 'Partnership Queue not found: ' + settingText(Partner_Portal_Setting__mdt.Partnership_Queue__c));
            }
            return;
        }
        Set<Id> leadIds = new Set<Id>();
        Set<Id> ownerIds = new Set<Id>();
        for (Lead record : leads) {
            leadIds.add(record.Id);
            ownerIds.add(record.OwnerId);
        }
        partnerWebPortalLeadEditController.loadOwners(ownerIds);
        Set<Id> visited = visitedLeads(leadIds);
        List<Lead> changes = new List<Lead>();
        Map<Id, Id> partnerByLead = new Map<Id, Id>();
        for (Lead record : leads) {
            if (record.CP_Freeze_Date__c == null || record.CP_Freeze_Date__c > Date.today() || visited.contains(record.Id)
                    || !partnerWebPortalLeadEditController.isPartnerUser(record.OwnerId)) {
                continue;
            }
            changes.add(new Lead(Id = record.Id, OwnerId = queueId));
            partnerByLead.put(record.Id, record.OwnerId);
        }
        List<Database.SaveResult> results = Database.update(changes, false, AccessLevel.SYSTEM_MODE);
        Map<Id, Id> frozen = new Map<Id, Id>();
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                frozen.put(changes[i].Id, partnerByLead.get(changes[i].Id));
            } else {
                System.debug(LoggingLevel.ERROR, 'Lead not moved to the Partnership Queue: ' + results[i].getErrors());
            }
        }
        emailPartners(frozen, settingText(Partner_Portal_Setting__mdt.Lead_Frozen_Email_Template__c));
    }

    // The leads among these with a site visit done (a visit with the Completed Visit Status)
    private static Set<Id> visitedLeads(Set<Id> leadIds) {
        Set<Id> visited = new Set<Id>();
        String completed = settingText(Partner_Portal_Setting__mdt.Completed_Visit_Status__c);
        if (completed == null || leadIds.isEmpty()) {
            return visited;
        }
        for (Visit__c visit : [SELECT Lead__c FROM Visit__c WHERE Lead__c IN :leadIds AND Status__c = :completed WITH SYSTEM_MODE]) {
            visited.add(visit.Lead__c);
        }
        return visited;
    }

    // =====================================================================================================
    // GRACE PERIOD
    // =====================================================================================================

    // What the Edit popup shows: the Freezing Date while the lead is in its window, and whether more time can be asked
    public static FreezeInfo infoOf(Lead record) {
        FreezeInfo info = new FreezeInfo();
        info.inWindow = inWindow(record);
        if (!info.inWindow) {
            return info;
        }
        info.freezeDate = PartnerSiteVisitService.dateText(record.CP_Freeze_Date__c);
        info.note = String.format(Label.Partner_Lead_Freeze_Note, new List<Object>{ info.freezeDate });
        info.graceOptions = graceOptions();
        Partner_Access_Request__c waiting = pendingGrace(record.Id);
        info.pending = waiting != null;
        if (waiting != null) {
            info.pendingNote = String.format(Label.Partner_Lead_Grace_Pending, new List<Object>{
                waiting.Extension_Days__c == null ? '' : String.valueOf(waiting.Extension_Days__c.intValue()) });
        }
        info.canRequest = !info.pending && !info.graceOptions.isEmpty();
        return info;
    }

    // The partner asks for more days on the lead's freezing window: a Partner Access Request for the CP Manager's
    // approval. Refused when the lead is not in its window, a request already waits, the days or reason are missing, or
    // there is no CP Manager.
    public static Partner_Access_Request__c requestGrace(Lead record, Integer days, String reason) {
        if (!inWindow(record)) {
            throw new FreezeException(Label.Partner_Lead_Grace_Not_Available);
        }
        if (days == null || !graceOptions().contains(days)) {
            throw new FreezeException(Label.Partner_Lead_Grace_Days);
        }
        if (String.isBlank(reason)) {
            throw new FreezeException(Label.Partner_Lead_Grace_Reason);
        }
        if (pendingGrace(record.Id) != null) {
            throw new FreezeException(Label.Partner_Lead_Grace_Already_Asked);
        }
        List<Id> team = PartnerSiteVisitService.cpTeamOf(record.Channel_Partner__c);
        Id manager = team == null ? null : team[1];
        if (manager == null) {
            throw new FreezeException(Label.Partner_Lead_Grace_No_Approver);
        }
        Account partner = [SELECT Id, OwnerId FROM Account WHERE Id = :record.Channel_Partner__c WITH SYSTEM_MODE];
        Partner_Access_Request__c request = new Partner_Access_Request__c(
            Account__c = partner.Id,
            Lead__c = record.Id,
            OwnerId = partner.OwnerId,
            Type__c = GRACE,
            Status__c = PENDING,
            Extension_Days__c = days,
            Reason__c = reason.trim().left(1000),
            Requested_By__c = UserInfo.getUserId(),
            Requested_Via__c = PartnerAccessRequestService.VIA_PORTAL,
            Approver__c = manager
        );
        Savepoint beforeSave = Database.setSavepoint();
        try {
            Database.insert(request, AccessLevel.SYSTEM_MODE);
            Approval.ProcessSubmitRequest submission = new Approval.ProcessSubmitRequest();
            submission.setObjectId(request.Id);
            submission.setProcessDefinitionNameOrId(GRACE_PROCESS);
            submission.setSubmitterId(partner.OwnerId);
            Approval.ProcessResult result = Approval.process(submission);
            if (!result.isSuccess()) {
                throw new FreezeException(String.valueOf(result.getErrors()));
            }
        } catch (Exception e) {
            Database.rollback(beforeSave);
            throw new FreezeException(e instanceof DmlException ? ((DmlException) e).getDmlMessage(0) : e.getMessage());
        }
        return request;
    }

    // After update (PartnerAccessRequestTrigger): an approved grace period moves the lead's Freezing Date on by its days
    // (counted from the later of the old date and today); the partner who asked is emailed either way
    public static void graceDecided(List<Partner_Access_Request__c> requests, Map<Id, Partner_Access_Request__c> oldRequests) {
        List<Partner_Access_Request__c> decided = new List<Partner_Access_Request__c>();
        Set<Id> leadIds = new Set<Id>();
        for (Partner_Access_Request__c request : requests) {
            Partner_Access_Request__c before = oldRequests == null ? null : oldRequests.get(request.Id);
            if (request.Type__c == GRACE && request.Lead__c != null && before != null && before.Status__c == PENDING
                    && (request.Status__c == APPROVED || request.Status__c == REJECTED)) {
                decided.add(request);
                leadIds.add(request.Lead__c);
            }
        }
        if (decided.isEmpty()) {
            return;
        }
        Map<Id, Lead> leads = new Map<Id, Lead>([SELECT Id, CP_Freeze_Date__c FROM Lead WHERE Id IN :leadIds WITH SYSTEM_MODE]);
        List<Lead> leadUpdates = new List<Lead>();
        List<Partner_Access_Request__c> requestUpdates = new List<Partner_Access_Request__c>();
        Map<Id, Id> approvedRequests = new Map<Id, Id>();
        Map<Id, Id> rejectedRequests = new Map<Id, Id>();
        for (Partner_Access_Request__c request : decided) {
            if (request.Status__c == APPROVED && request.Extension_Days__c != null && leads.containsKey(request.Lead__c)) {
                Lead record = leads.get(request.Lead__c);
                Date fromDay = record.CP_Freeze_Date__c == null || record.CP_Freeze_Date__c < Date.today() ? Date.today() : record.CP_Freeze_Date__c;
                Date newDate = fromDay.addDays(request.Extension_Days__c.intValue());
                leadUpdates.add(new Lead(Id = record.Id, CP_Freeze_Date__c = newDate));
                requestUpdates.add(new Partner_Access_Request__c(Id = request.Id, New_End_Date__c = newDate));
                approvedRequests.put(request.Id, request.Requested_By__c);
            } else if (request.Status__c == REJECTED) {
                rejectedRequests.put(request.Id, request.Requested_By__c);
            }
        }
        for (Database.SaveResult result : Database.update(leadUpdates, false, AccessLevel.SYSTEM_MODE)) {
            if (!result.isSuccess()) {
                System.debug(LoggingLevel.ERROR, 'Freezing Date not moved on: ' + result.getErrors());
            }
        }
        Database.update(requestUpdates, false, AccessLevel.SYSTEM_MODE);
        emailPartners(approvedRequests, settingText(Partner_Portal_Setting__mdt.Lead_Grace_Approved_Email_Template__c));
        emailPartners(rejectedRequests, settingText(Partner_Portal_Setting__mdt.Lead_Grace_Rejected_Email_Template__c));
    }

    // =====================================================================================================
    // HELPERS
    // =====================================================================================================

    // In the freezing window: a channel partner's open lead (the partner owns it, not booked, lost or waiting for
    // approval) with a Freezing Date and no site visit done
    public static Boolean inWindow(Lead record) {
        String lost = settingText(Partner_Portal_Setting__mdt.CP_Lead_Lost_Status__c);
        if (record.Channel_Partner__c == null || record.CP_Freeze_Date__c == null || record.IsConverted
                || (lost != null && record.Status == lost) || record.CP_Approval_Status__c == LeadLogicController.CP_APPROVAL_PENDING
                || !partnerWebPortalLeadEditController.isPartnerUser(record.OwnerId)) {
            return false;
        }
        return !visitedLeads(new Set<Id>{ record.Id }).contains(record.Id);
    }

    // The lead's grace period request waiting for the CP Manager, or null
    private static Partner_Access_Request__c pendingGrace(Id leadId) {
        List<Partner_Access_Request__c> waiting = [
            SELECT Id, Extension_Days__c FROM Partner_Access_Request__c
            WHERE Lead__c = :leadId AND Type__c = :GRACE AND Status__c = :PENDING WITH SYSTEM_MODE LIMIT 1
        ];
        return waiting.isEmpty() ? null : waiting[0];
    }

    // The grace periods a partner can ask for (Lead Grace Day Options)
    public static List<Integer> graceOptions() {
        List<Integer> options = new List<Integer>();
        String text = settingText(Partner_Portal_Setting__mdt.Lead_Grace_Day_Options__c);
        if (text == null) {
            return options;
        }
        for (String part : text.split('[,;\\s]+')) {
            if (part.trim().isNumeric() && Integer.valueOf(part.trim()) > 0 && !options.contains(Integer.valueOf(part.trim()))) {
                options.add(Integer.valueOf(part.trim()));
            }
        }
        return options;
    }

    private static Id cachedQueueId;

    // The Partnership Queue (Partner Portal Setting), or null
    public static Id partnershipQueueId() {
        String name = settingText(Partner_Portal_Setting__mdt.Partnership_Queue__c);
        if (name == null) {
            return null;
        }
        if (cachedQueueId == null) {
            for (Group queue : [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = :name WITH SYSTEM_MODE LIMIT 1]) {
                cachedQueueId = queue.Id;
            }
        }
        return cachedQueueId;
    }

    // Emails the users of these records (record Id => user Id) with the template: a Lead template for leads, a Partner
    // Access Request template for requests. An email that cannot be written or sent does not stop anything.
    private static void emailPartners(Map<Id, Id> userByRecord, String templateName) {
        if (userByRecord.isEmpty() || templateName == null) {
            return;
        }
        try {
            List<EmailTemplate> templates = [SELECT Id FROM EmailTemplate WHERE DeveloperName = :templateName WITH SYSTEM_MODE LIMIT 1];
            if (templates.isEmpty()) {
                System.debug(LoggingLevel.ERROR, 'Email template not found: ' + templateName);
                return;
            }
            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
            for (Id recordId : userByRecord.keySet()) {
                Id userId = userByRecord.get(recordId);
                if (userId == null || userId.getSObjectType() != User.SObjectType) {
                    continue;
                }
                Boolean isLead = recordId.getSObjectType() == Lead.SObjectType;
                Messaging.SingleEmailMessage rendered = Messaging.renderStoredEmailTemplate(templates[0].Id, isLead ? recordId : userId,
                    isLead ? null : recordId);
                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setTargetObjectId(userId);
                email.setSubject(rendered.getSubject());
                email.setPlainTextBody(rendered.getPlainTextBody());
                email.setSaveAsActivity(false);
                emails.add(email);
            }
            emailsWritten += emails.size();
            for (Messaging.SendEmailResult result : PartnerEmailSender.send(emails)) {
                if (!result.isSuccess()) {
                    System.debug(LoggingLevel.ERROR, 'Freezing window email not sent: ' + result.getErrors());
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Freezing window email not sent: ' + e.getMessage());
        }
    }

    private static Integer freezeDays() {
        return setting == null || setting.Lead_Freeze_Days__c == null || setting.Lead_Freeze_Days__c <= 0 ? null
            : setting.Lead_Freeze_Days__c.intValue();
    }

    private static String settingText(SObjectField field) {
        if (setting == null) {
            return null;
        }
        Object value = setting.get(field);
        return value == null || String.isBlank(String.valueOf(value)) ? null : String.valueOf(value).trim();
    }
}