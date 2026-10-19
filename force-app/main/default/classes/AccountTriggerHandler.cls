// Gives each new account whose record type has a Document Master (for example "Account" with Record Type "Channel
// partner") its SharePoint folder, the way projects get theirs: CreateSharePointFoldersQueueable creates the account's
// folder, then DocumentCreationHandler creates a Document__c, and a sub-folder, for each category of that master.
// Accounts that already have a folder are left alone: Partner Portal registrations create theirs while registering.
public with sharing class AccountTriggerHandler {

    public static void handleAfterInsert(List<Account> newAccounts) {
        try {
            Set<String> recordTypesWithDocuments = DocumentCreationHandler.recordTypesWithDocuments();
            if (recordTypesWithDocuments.isEmpty()) {
                return;
            }
            Map<Id, Schema.RecordTypeInfo> recordTypes = Schema.SObjectType.Account.getRecordTypeInfosById();
            List<Id> accountIds = new List<Id>();
            for (Account account : newAccounts) {
                Schema.RecordTypeInfo recordType = account.RecordTypeId == null ? null : recordTypes.get(account.RecordTypeId);
                if (String.isBlank(account.Document_Id__c) && recordType != null
                        && recordTypesWithDocuments.contains(recordType.getName().toLowerCase())) {
                    accountIds.add(account.Id);
                }
            }
            // Enqueueing past the limit throws an uncatchable LimitException that would roll back the account insert
            if (!accountIds.isEmpty() && Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
                System.enqueueJob(new CreateSharePointFoldersQueueable(accountIds));
            }
        } catch (Exception e) {
            // A folder problem must never stop an account from being saved
            System.debug(LoggingLevel.ERROR, 'Account folders were not queued: ' + e.getMessage() + ' at line ' + e.getLineNumber());
        }
    }
}