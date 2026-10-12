// Nightly check of the channel partners' temporary access, with the rule of PartnerTemporaryAccess (the onboarding chart:
// "Condition met in 30 days?"). Only channel heads are judged: their executives go by them.
//  - Yes: the partner's exclusive agent contract is drafted (PartnerContractService: verification by the CP Manager and
//    the Head of Sales, then the partner signs offline); the partner becomes Exclusive once the CP Executive records the
//    signature.
//  - No, once the access ended more than the Denial Grace Days ago: Access Denied, and the portal users of the partner
//    and of its executives are deactivated (the login refuses them from the day after the end date already).
// Each run also makes a partner with a signed contract Exclusive (should that have failed when it was signed), and
// deactivates any active portal user of an Access Denied or Terminated partner (also when set by hand). It sends the
// running user a summary. Schedule it as an administrator: approved partner accounts stay locked for other users.
global class PartnerExclusiveCheckBatch implements Database.Batchable<sObject>, Database.Stateful, Schedulable {
    global List<String> draftedPartners  = new List<String>();
    global List<String> promotedPartners = new List<String>();
    global List<String> deniedPartners   = new List<String>();
    global List<String> failures         = new List<String>();
    global Integer totalEvaluated        = 0;
    // The contracts drafted; their OneDrive folders and draft PDFs are made when the batch finishes (ContractDocumentService)
    global Set<Id> draftedContractIds    = new Set<Id>();

    // Each account's check takes a few queries, so the batches stay small
    private static final Integer BATCH_SIZE = 20;

    global void execute(SchedulableContext sc) {
        Database.executeBatch(new PartnerExclusiveCheckBatch(), BATCH_SIZE);
    }

    // Channel heads on temporary access, and every Access Denied or Terminated partner
    global Database.QueryLocator start(Database.BatchableContext bc) {
        String temporary = PartnerTemporaryAccess.TEMPORARY;
        List<String> closed = new List<String>{ PartnerTemporaryAccess.ACCESS_DENIED, PartnerTemporaryAccess.TERMINATED };
        return Database.getQueryLocator([
            SELECT Id, Name, OwnerId, Partner_Type__c, Temporary_Access_Start_Date__c, Temporary_Access_End_Date__c, Channel_Head__c
            FROM Account
            WHERE (Channel_Head__c = null AND Partner_Type__c = :temporary) OR Partner_Type__c IN :closed
            WITH SYSTEM_MODE
        ]);
    }

    global void execute(Database.BatchableContext bc, List<Account> scope) {
        Date today = PartnerTemporaryAccess.today();
        Integer graceDays = PartnerTemporaryAccess.denialGraceDays();
        Boolean canDeny = PartnerTemporaryAccess.hasConditions();
        Map<Id, String> stageByAccount = new Map<Id, String>();
        for (Contract record : [
            SELECT AccountId, Contract_Stage__c FROM Contract WHERE AccountId IN :scope WITH SYSTEM_MODE ORDER BY CreatedDate ASC
        ]) {
            stageByAccount.put(record.AccountId, record.Contract_Stage__c);
        }

        Map<Id, Account> updates = new Map<Id, Account>();
        Map<Id, String> names = new Map<Id, String>();
        List<Account> toDraft = new List<Account>();
        Set<Id> closedAccountIds = new Set<Id>();
        for (Account acc : scope) {
            names.put(acc.Id, acc.Name);
            if (acc.Partner_Type__c != PartnerTemporaryAccess.TEMPORARY) {
                // Access Denied or Terminated: its users (and its executives') must not log in
                closedAccountIds.add(acc.Id);
                continue;
            }
            totalEvaluated++;
            String stage = stageByAccount.get(acc.Id);
            if (stage == PartnerContractService.SIGNED || stage == PartnerContractService.COMPLETED) {
                updates.put(acc.Id, new Account(Id = acc.Id, Partner_Type__c = PartnerTemporaryAccess.EXCLUSIVE));
            } else if (PartnerTemporaryAccess.metConditions(acc)) {
                if (stage == null) {
                    toDraft.add(acc);
                }
            } else if (canDeny && acc.Temporary_Access_End_Date__c != null && acc.Temporary_Access_End_Date__c.addDays(graceDays) < today) {
                updates.put(acc.Id, new Account(Id = acc.Id, Partner_Type__c = PartnerTemporaryAccess.ACCESS_DENIED));
            }
        }

        List<Account> changed = updates.values();
        List<Database.SaveResult> results = Database.update(changed, false, AccessLevel.SYSTEM_MODE);
        for (Integer i = 0; i < changed.size(); i++) {
            Account acc = changed[i];
            if (!results[i].isSuccess()) {
                failures.add(names.get(acc.Id) + ': ' + results[i].getErrors()[0].getMessage());
            } else if (acc.Partner_Type__c == PartnerTemporaryAccess.EXCLUSIVE) {
                promotedPartners.add(names.get(acc.Id));
            } else {
                deniedPartners.add(names.get(acc.Id));
                closedAccountIds.add(acc.Id);
            }
        }

        if (!toDraft.isEmpty()) {
            Savepoint beforeDrafts = Database.setSavepoint();
            try {
                for (Contract record : PartnerContractService.createDrafts(toDraft)) {
                    draftedPartners.add(names.get(record.AccountId));
                    draftedContractIds.add(record.Id);
                }
            } catch (Exception e) {
                Database.rollback(beforeDrafts);
                failures.add('Contract drafts: ' + e.getMessage());
            }
        }

        if (!closedAccountIds.isEmpty()) {
            Set<Id> userIdsToDeactivate = activeUsersOf(closedAccountIds);
            if (!userIdsToDeactivate.isEmpty()) {
                // In a transaction of its own (user changes cannot share one with account changes). A login that cannot
                // be switched off does not keep the others on.
                System.enqueueJob(new PartnerUserActivationQueueable(userIdsToDeactivate, false));
            }
        }
    }

    // The active portal users of these partners and of the executives under them: the logins to switch off, so that
    // they stop using a licence
    @TestVisible
    private static Set<Id> activeUsersOf(Set<Id> accountIds) {
        return new Map<Id, User>([
            SELECT Id FROM User
            WHERE IsActive = true AND ContactId != null
                AND (Contact.AccountId IN :accountIds OR Contact.Account.Channel_Head__c IN :accountIds)
            WITH SYSTEM_MODE
        ]).keySet();
    }

    // Summary email to the running user
    global void finish(Database.BatchableContext bc) {
        // The drafted contracts' folders and PDFs, and any contract documents an earlier run could not finish
        Set<Id> contractIds = new Set<Id>(draftedContractIds);
        contractIds.addAll(ContractDocumentService.pendingContractIds());
        ContractDocumentService.startJob(contractIds);

        String htmlBody = '<h2>Channel Partner Evaluation Batch Summary</h2>'
            + '<p><strong>Temporary Channel Partners Evaluated:</strong> ' + totalEvaluated + '</p><hr/>'
            + section('📝 Exclusive Contract Drafted (' + draftedPartners.size() + ')', '#1565c0', draftedPartners)
            + section('✅ Made Exclusive - Contract Signed (' + promotedPartners.size() + ')', '#2e7d32', promotedPartners)
            + section('❌ Access Denied (' + deniedPartners.size() + ')', '#c62828', deniedPartners)
            + (failures.isEmpty() ? '' : section('⚠️ Not Processed (' + failures.size() + ')', '#e65100', failures))
            + '<p><i>This is an automated notification from the Salesforce Channel Partner Evaluation Job.</i></p>';
        try {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new List<String>{ UserInfo.getUserEmail() });
            mail.setSubject('Partner Evaluation Batch Results - ' + Date.today().format());
            mail.setHtmlBody(htmlBody);
            PartnerEmailSender.send(new List<Messaging.SingleEmailMessage>{ mail });
        } catch (Exception e) {
            System.debug('>>> [PartnerEvaluation] Failed to send email: ' + e.getMessage());
        }
    }

    private static String section(String title, String colour, List<String> lines) {
        String html = '<h3 style="color: ' + colour + ';">' + title.escapeHtml4() + '</h3><ul>';
        if (lines.isEmpty()) {
            html += '<li>None in this run</li>';
        }
        for (String line : lines) {
            html += '<li>' + line.escapeHtml4() + '</li>';
        }
        return html + '</ul>';
    }
}