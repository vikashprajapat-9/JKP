// Requests to change a channel partner's Partner Portal access, decided by approval (Partner Access Request):
//  - Extension (the onboarding chart: "CP Agent requests an extension of the access window by selecting extension days,
//    the CP Manager approves or rejects; the request is available on the portal"): the channel head asks on the portal in
//    the last days of its temporary access (partnerWebPortalAccessController); once the access has ended the partner can
//    no longer log in, and the login page offers no extension. The CP Manager approves: the partner account owner's
//    manager, else the owner.
//    Approved: the access end date moves on by the days asked (counted from the later of the old end date and today), an
//    Access Denied partner is Temporary again with its portal users (and its executives') active again; the partner is
//    emailed either way.
//  - Termination ("CP Manager can terminate the access of an Agent on CP Head's approval"): the CP Manager asks from the
//    partner's account (quick action Request Termination); the CP Head queue (role Manager Sales Partnerships) approves.
//    Approved: Partner Type Terminated, the portal users of the partner (and of its executives) are deactivated, and the
//    partner is emailed.
// A decision is applied by PartnerAccessChangeTrigger as an administrator: approved partner accounts stay locked for other
// users. Options, offer days and email templates are in the Partner Portal Setting; texts are labels (Partner_Access_*).
public without sharing class PartnerAccessRequestService {
    // Messages this class shows or sends
    @TestVisible private static final String PARTNER_ACCESS_ALREADY_TERMINATED = 'This partner is already Terminated.';
    @TestVisible private static final String PARTNER_ACCESS_EXTENSION_DAYS = 'Choose one of the offered extension periods.';
    @TestVisible private static final String PARTNER_ACCESS_EXTENSION_HEAD_ONLY = 'Only your channel partner can request an extension of the access.';
    @TestVisible private static final String PARTNER_ACCESS_EXTENSION_NOT_AVAILABLE = 'An extension cannot be requested for this login. Please contact the JKP CP team.';
    @TestVisible private static final String PARTNER_ACCESS_REASON_REQUIRED = 'Enter the reason for the request.';
    @TestVisible private static final String PARTNER_ACCESS_REQUEST_PENDING = 'A request of this kind is already waiting for approval.';
    @TestVisible private static final String PARTNER_ACCESS_TERMINATION_INFO = 'Once the CP Head approves, the partner becomes Terminated, its portal login is deactivated (with those of its executives) and it receives an email.';
    @TestVisible private static final String PARTNER_ACCESS_TERMINATION_NOT_PARTNER = 'Only channel partner accounts can be terminated.';
    @TestVisible private static final String PARTNER_ACCESS_TERMINATION_REQUESTED = 'The termination has been sent to the CP Head for approval.';


    public static final String EXTENSION = 'Extension';
    public static final String TERMINATION = 'Termination';
    public static final String PENDING = 'Pending';
    public static final String APPROVED = 'Approved';
    public static final String REJECTED = 'Rejected';
    public static final String VIA_PORTAL = 'Portal';
    public static final String VIA_LOGIN_PAGE = 'Login Page';
    public static final String VIA_SALESFORCE = 'Salesforce';

    private static final String EXTENSION_PROCESS = 'Partner_Access_Extension';
    private static final String TERMINATION_PROCESS = 'Partner_Access_Termination';
    private static final Integer DEFAULT_OFFER_DAYS = 7;

    @TestVisible
    private static Partner_Portal_Setting__mdt setting {
        get {
            if (setting == null) {
                setting = Partner_Portal_Setting__mdt.getInstance('Default');
            }
            return setting;
        }
        set;
    }

    // A request that cannot be made; its message is meant for the user
    public class RequestException extends Exception {}

    // What the Request Termination quick action shows
    public class TerminationInfo {
        @AuraEnabled public String accountName;
        @AuraEnabled public String partnerType;
        @AuraEnabled public Boolean isChannelHead = false;
        @AuraEnabled public Integer executiveCount = 0;
        @AuraEnabled public Boolean canRequest = false;
        @AuraEnabled public String message;
    }

    // =====================================================================================================
    // SETTINGS
    // =====================================================================================================

    // The extension periods (days) partners may choose, in order
    public static List<Integer> extensionOptions() {
        List<Integer> options = new List<Integer>();
        String listed = setting == null ? null : setting.Extension_Day_Options__c;
        if (String.isNotBlank(listed)) {
            for (String part : listed.split(',')) {
                if (part.trim().isNumeric() && Integer.valueOf(part.trim()) > 0 && !options.contains(Integer.valueOf(part.trim()))) {
                    options.add(Integer.valueOf(part.trim()));
                }
            }
        }
        options.sort();
        return options;
    }

    // How many days before the end of the temporary access the portal offers an extension
    public static Integer offerDays() {
        return setting == null || setting.Extension_Offer_Days__c == null ? DEFAULT_OFFER_DAYS : setting.Extension_Offer_Days__c.intValue();
    }

    // The request of this type waiting for approval for the account, or null
    public static Partner_Access_Request__c pendingRequest(Id accountId, String requestType) {
        List<Partner_Access_Request__c> pending = [
            SELECT Id, Extension_Days__c, CreatedDate FROM Partner_Access_Request__c
            WHERE Account__c = :accountId AND Type__c = :requestType AND Status__c = :PENDING
            WITH SYSTEM_MODE ORDER BY CreatedDate DESC LIMIT 1
        ];
        return pending.isEmpty() ? null : pending[0];
    }

    // =====================================================================================================
    // EXTENSION
    // =====================================================================================================

    // Whether this channel head may ask for an extension now: on temporary access (or Access Denied once it ended), and
    // no extension waiting for approval yet
    public static Boolean mayRequestExtension(Account partner) {
        return partner != null && partner.Id != null && partner.Channel_Head__c == null
            && (partner.Partner_Type__c == PartnerTemporaryAccess.TEMPORARY || partner.Partner_Type__c == PartnerTemporaryAccess.ACCESS_DENIED)
            && pendingRequest(partner.Id, EXTENSION) == null;
    }

    // A channel head's extension request, sent to the CP Manager for approval
    public static Partner_Access_Request__c requestExtension(Id accountId, Integer days, String reason, String via, Id requestedBy) {
        if (days == null || !extensionOptions().contains(days)) {
            throw new RequestException(PARTNER_ACCESS_EXTENSION_DAYS);
        }
        if (String.isBlank(reason)) {
            throw new RequestException(PARTNER_ACCESS_REASON_REQUIRED);
        }
        List<Account> accounts = [
            SELECT Id, OwnerId, Owner.ManagerId, Owner.Manager.IsActive, Channel_Head__c, Partner_Type__c
            FROM Account WHERE Id = :accountId WITH SYSTEM_MODE
        ];
        if (accounts.isEmpty() || accounts[0].Channel_Head__c != null) {
            throw new RequestException(PARTNER_ACCESS_EXTENSION_HEAD_ONLY);
        }
        Account partner = accounts[0];
        if (!mayRequestExtension(partner)) {
            throw new RequestException(pendingRequest(partner.Id, EXTENSION) != null
                ? PARTNER_ACCESS_REQUEST_PENDING : PARTNER_ACCESS_EXTENSION_NOT_AVAILABLE);
        }
        Id cpManager = partner.Owner.ManagerId != null && partner.Owner.Manager.IsActive ? partner.Owner.ManagerId : partner.OwnerId;
        Partner_Access_Request__c request = new Partner_Access_Request__c(
            Account__c = partner.Id,
            OwnerId = partner.OwnerId,
            Type__c = EXTENSION,
            Status__c = PENDING,
            Extension_Days__c = days,
            Reason__c = reason.trim().left(1000),
            Requested_By__c = requestedBy,
            Requested_Via__c = via,
            Approver__c = cpManager
        );
        Database.insert(request, AccessLevel.SYSTEM_MODE);
        submit(request.Id, EXTENSION_PROCESS, partner.OwnerId);
        return request;
    }

    // =====================================================================================================
    // TERMINATION (quick action Request Termination)
    // =====================================================================================================

    @AuraEnabled
    public static TerminationInfo getTerminationInfo(Id accountId) {
        try {
            TerminationInfo info = new TerminationInfo();
            List<Account> accounts = [
                SELECT Id, Name, RecordTypeId, Partner_Type__c, Channel_Head__c
                FROM Account WHERE Id = :accountId WITH SYSTEM_MODE
            ];
            if (accounts.isEmpty()) {
                info.message = PARTNER_ACCESS_TERMINATION_NOT_PARTNER;
                return info;
            }
            Account partner = accounts[0];
            info.accountName = partner.Name;
            info.partnerType = partner.Partner_Type__c;
            info.isChannelHead = partner.Channel_Head__c == null;
            info.executiveCount = info.isChannelHead
                ? [SELECT COUNT() FROM Account WHERE Channel_Head__c = :partner.Id WITH SYSTEM_MODE] : 0;
            info.message = terminationProblem(partner);
            info.canRequest = info.message == null;
            if (info.canRequest) {
                info.message = PARTNER_ACCESS_TERMINATION_INFO;
            }
            return info;
        } catch (Exception e) {
            throw userError(e.getMessage());
        }
    }

    @AuraEnabled
    public static String requestTermination(Id accountId, String reason) {
        try {
            if (String.isBlank(reason)) {
                throw new RequestException(PARTNER_ACCESS_REASON_REQUIRED);
            }
            List<Account> accounts = [
                SELECT Id, RecordTypeId, Partner_Type__c, Channel_Head__c FROM Account WHERE Id = :accountId WITH SYSTEM_MODE
            ];
            String problem = accounts.isEmpty() ? PARTNER_ACCESS_TERMINATION_NOT_PARTNER : terminationProblem(accounts[0]);
            if (problem != null) {
                throw new RequestException(problem);
            }
            Partner_Access_Request__c request = new Partner_Access_Request__c(
                Account__c = accountId,
                OwnerId = UserInfo.getUserId(),
                Type__c = TERMINATION,
                Status__c = PENDING,
                Reason__c = reason.trim().left(1000),
                Requested_By__c = UserInfo.getUserId(),
                Requested_Via__c = VIA_SALESFORCE
            );
            Database.insert(request, AccessLevel.SYSTEM_MODE);
            submit(request.Id, TERMINATION_PROCESS, UserInfo.getUserId());
            return PARTNER_ACCESS_TERMINATION_REQUESTED;
        } catch (RequestException e) {
            throw userError(e.getMessage());
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Termination request failed: ' + e.getMessage());
            throw userError(e.getMessage());
        }
    }

    // Why the account cannot be terminated, or null
    private static String terminationProblem(Account partner) {
        if (partner.RecordTypeId != partnerPortalRegistrationController.partnerRecordTypeId()) {
            return PARTNER_ACCESS_TERMINATION_NOT_PARTNER;
        }
        if (partner.Partner_Type__c == PartnerTemporaryAccess.TERMINATED) {
            return PARTNER_ACCESS_ALREADY_TERMINATED;
        }
        if (pendingRequest(partner.Id, TERMINATION) != null) {
            return PARTNER_ACCESS_REQUEST_PENDING;
        }
        return null;
    }

    // =====================================================================================================
    // DECISIONS
    // =====================================================================================================

    // After update: a request the approval decided is passed on, to be applied as an administrator
    public static void requestsDecided(List<Partner_Access_Request__c> requests, Map<Id, Partner_Access_Request__c> oldRequests) {
        List<Partner_Access_Change__e> changes = new List<Partner_Access_Change__e>();
        for (Partner_Access_Request__c request : requests) {
            String before = oldRequests.get(request.Id).Status__c;
            if (before == PENDING && (request.Status__c == APPROVED || request.Status__c == REJECTED)) {
                changes.add(new Partner_Access_Change__e(Request_Id__c = request.Id));
            }
        }
        if (changes.isEmpty()) {
            return;
        }
        for (Database.SaveResult result : EventBus.publish(changes)) {
            if (!result.isSuccess()) {
                throw new RequestException('The decision could not be passed on: ' + result.getErrors());
            }
        }
    }

    // The decisions, applied as an administrator (PartnerAccessChangeTrigger)
    public static void applyDecisions(List<Partner_Access_Change__e> changes) {
        Set<Id> requestIds = new Set<Id>();
        for (Partner_Access_Change__e change : changes) {
            if (String.isNotBlank(change.Request_Id__c)) {
                requestIds.add(change.Request_Id__c);
            }
        }
        Date today = PartnerTemporaryAccess.today();
        Map<Id, Account> accountUpdates = new Map<Id, Account>();
        List<Partner_Access_Request__c> requestUpdates = new List<Partner_Access_Request__c>();
        Set<Id> reactivate = new Set<Id>();
        Set<Id> deactivate = new Set<Id>();
        Map<Id, String> templateByAccount = new Map<Id, String>();
        for (Partner_Access_Request__c request : [
            SELECT Id, Type__c, Status__c, Extension_Days__c, Account__c, Account__r.Partner_Type__c, Account__r.Temporary_Access_End_Date__c
            FROM Partner_Access_Request__c WHERE Id IN :requestIds WITH SYSTEM_MODE
        ]) {
            Account partner = request.Account__r;
            if (request.Type__c == EXTENSION && request.Status__c == APPROVED && request.Extension_Days__c != null) {
                Date endsOn = partner.Temporary_Access_End_Date__c == null || partner.Temporary_Access_End_Date__c < today
                    ? today : partner.Temporary_Access_End_Date__c;
                Date newEnd = endsOn.addDays(request.Extension_Days__c.intValue());
                Account change = new Account(Id = request.Account__c, Temporary_Access_End_Date__c = newEnd);
                if (partner.Partner_Type__c == PartnerTemporaryAccess.ACCESS_DENIED) {
                    change.Partner_Type__c = PartnerTemporaryAccess.TEMPORARY;
                    reactivate.add(request.Account__c);
                }
                accountUpdates.put(request.Account__c, change);
                requestUpdates.add(new Partner_Access_Request__c(Id = request.Id, New_End_Date__c = newEnd));
                templateByAccount.put(request.Account__c, setting == null ? null : setting.Extension_Approved_Email_Template__c);
            } else if (request.Type__c == EXTENSION && request.Status__c == REJECTED) {
                templateByAccount.put(request.Account__c, setting == null ? null : setting.Extension_Rejected_Email_Template__c);
            } else if (request.Type__c == TERMINATION && request.Status__c == APPROVED) {
                accountUpdates.put(request.Account__c, new Account(Id = request.Account__c, Partner_Type__c = PartnerTemporaryAccess.TERMINATED));
                deactivate.add(request.Account__c);
                templateByAccount.put(request.Account__c, setting == null ? null : setting.Termination_Email_Template__c);
            }
        }
        for (Database.SaveResult result : Database.update(accountUpdates.values(), false, AccessLevel.SYSTEM_MODE)) {
            if (!result.isSuccess()) {
                System.debug(LoggingLevel.ERROR, 'Partner access decision not applied: ' + result.getErrors());
            }
        }
        Database.update(requestUpdates, false, AccessLevel.SYSTEM_MODE);
        if (!reactivate.isEmpty()) {
            System.enqueueJob(new PartnerUserActivationQueueable(portalUsers(reactivate, false), true));
        }
        if (!deactivate.isEmpty()) {
            System.enqueueJob(new PartnerUserActivationQueueable(portalUsers(deactivate, true), false));
        }
        emailPartners(templateByAccount);
    }

    // The portal users of these partners and of their executives, active or not. When looking for inactive users (to
    // switch them on again after an extension), those of an account that is itself Access Denied or Terminated are left
    // out: they stay off, and use no licence.
    @TestVisible
    private static Set<Id> portalUsers(Set<Id> accountIds, Boolean active) {
        Set<Id> userIds = new Set<Id>();
        for (User person : [
            SELECT Id, Contact.Account.Partner_Type__c FROM User
            WHERE ContactId != null AND IsActive = :active
                AND (Contact.AccountId IN :accountIds OR Contact.Account.Channel_Head__c IN :accountIds)
            WITH SYSTEM_MODE
        ]) {
            if (active || !PartnerTemporaryAccess.isClosed(person.Contact.Account.Partner_Type__c)) {
                userIds.add(person.Id);
            }
        }
        return userIds;
    }

    // The decision email to each partner's first contact
    private static void emailPartners(Map<Id, String> templateByAccount) {
        Set<String> names = new Set<String>();
        for (String name : templateByAccount.values()) {
            if (String.isNotBlank(name)) {
                names.add(name.trim());
            }
        }
        if (names.isEmpty()) {
            return;
        }
        Map<String, Id> templates = new Map<String, Id>();
        for (EmailTemplate template : [SELECT Id, DeveloperName FROM EmailTemplate WHERE DeveloperName IN :names WITH SYSTEM_MODE]) {
            templates.put(template.DeveloperName, template.Id);
        }
        Map<Id, Id> contactByAccount = new Map<Id, Id>();
        for (Contact person : [
            SELECT Id, AccountId FROM Contact WHERE AccountId IN :templateByAccount.keySet() AND Email != null
            WITH SYSTEM_MODE ORDER BY CreatedDate ASC, Id ASC
        ]) {
            if (!contactByAccount.containsKey(person.AccountId)) {
                contactByAccount.put(person.AccountId, person.Id);
            }
        }
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        for (Id accountId : templateByAccount.keySet()) {
            String name = templateByAccount.get(accountId);
            Id templateId = String.isBlank(name) ? null : templates.get(name.trim());
            if (templateId == null || !contactByAccount.containsKey(accountId)) {
                continue;
            }
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setTemplateId(templateId);
            email.setTargetObjectId(contactByAccount.get(accountId));
            email.setWhatId(accountId);
            email.setSaveAsActivity(false);
            emails.add(email);
        }
        if (emails.isEmpty()) {
            return;
        }
        for (Messaging.SendEmailResult result : PartnerEmailSender.send(emails)) {
            if (!result.isSuccess()) {
                System.debug(LoggingLevel.ERROR, 'Partner access email not sent: ' + result.getErrors());
            }
        }
    }

    // =====================================================================================================
    // HELPERS
    // =====================================================================================================

    // The request into its approval process, on behalf of an allowed submitter (the owner or the creator)
    private static void submit(Id requestId, String processName, Id submitterId) {
        Approval.ProcessSubmitRequest submission = new Approval.ProcessSubmitRequest();
        submission.setObjectId(requestId);
        submission.setProcessDefinitionNameOrId(processName);
        submission.setSubmitterId(submitterId);
        Approval.ProcessResult result = Approval.process(submission);
        if (!result.isSuccess()) {
            throw new RequestException(String.valueOf(result.getErrors()));
        }
    }

    private static AuraHandledException userError(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}