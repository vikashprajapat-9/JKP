/**
 * @description Batch and Schedulable class to process Opportunity records in
 *              'Offer Letter and Deposit Collection' stage where the offer letter has been sent
 *              and threshold days have passed without the complete deposit amount collected.
 *              Generates a 'Deposit Amount Overdue' task assigned to the Opportunity's Sales Member.
 */
global with sharing class BatchForDepositCollectionReminder implements Database.Batchable<sObject>, Schedulable {

    private String query;

    global BatchForDepositCollectionReminder() {
    }

    global BatchForDepositCollectionReminder(String customQuery) {
        this.query = customQuery;
    }

    global Database.QueryLocator start(Database.BatchableContext BC) {
        if (String.isNotBlank(this.query)) {
            return Database.getQueryLocator(this.query);
        }
        return Database.getQueryLocator([
            SELECT Id, Name, StageName, Offer_Letter_Sent__c, Offer_Letter_Sent_Date__c,
                   Sales_Member__c, OwnerId, Project__c, Project__r.Deposit_Collection_Threshold__c,
                   Token_Amount__c
            FROM Opportunity
            WHERE StageName = 'Offer Letter and Deposit Collection'
              AND Offer_Letter_Sent__c = true
              AND Offer_Letter_Sent_Date__c != null
              AND Project__c != null
              AND Project__r.Deposit_Collection_Threshold__c != null
        ]);
    }

    global void execute(Database.BatchableContext BC, List<Opportunity> scope) {
        if (scope == null || scope.isEmpty()) {
            return;
        }

        Date todayDate = Date.today();
        List<Opportunity> overdueCandidates = new List<Opportunity>();
        Set<Id> overdueCandidateIds = new Set<Id>();

        for (Opportunity opp : scope) {
            if (opp.Offer_Letter_Sent_Date__c == null || opp.Project__r == null || opp.Project__r.Deposit_Collection_Threshold__c == null) {
                continue;
            }

            Integer thresholdDays = Integer.valueOf(opp.Project__r.Deposit_Collection_Threshold__c);
            Date thresholdDeadline = opp.Offer_Letter_Sent_Date__c.addDays(thresholdDays);

            // Check if threshold days have passed after the offer letter was sent
            if (todayDate > thresholdDeadline) {
                overdueCandidates.add(opp);
                overdueCandidateIds.add(opp.Id);
            }
        }

        if (overdueCandidateIds.isEmpty()) {
            return;
        }

        // 1. Query Payment Schedules named 'Deposit Amount' for required deposit amounts
        Map<Id, Decimal> oppToDepositRequired = new Map<Id, Decimal>();
        for (Payment_Schedule__c ps : [
            SELECT Id, Name, Total_Amount_Inclusive_Of_Tax__c, Total_Due_Amount__c, Total_Received_Amount__c, Opportunity__c
            FROM Payment_Schedule__c
            WHERE Opportunity__c IN :overdueCandidateIds
              AND Name LIKE '%Deposit Amount%'
        ]) {
            Decimal requiredAmount = (ps.Total_Due_Amount__c != null && ps.Total_Due_Amount__c > 0)
                ? ps.Total_Due_Amount__c
                : (ps.Total_Amount_Inclusive_Of_Tax__c != null ? ps.Total_Amount_Inclusive_Of_Tax__c : 0);
            oppToDepositRequired.put(ps.Opportunity__c, requiredAmount);
        }

        // 2. Query total amount collected via Receipt Logs for these Opportunities
        Map<Id, Decimal> oppToTotalPaid = new Map<Id, Decimal>();
        for (AggregateResult ar : [
            SELECT Opportunity__c oppId, SUM(Amount__c) totalPaid
            FROM Receipt_Log__c
            WHERE Opportunity__c IN :overdueCandidateIds
            GROUP BY Opportunity__c
        ]) {
            Id oppId = (Id) ar.get('oppId');
            Decimal totalPaid = (Decimal) ar.get('totalPaid');
            oppToTotalPaid.put(oppId, totalPaid != null ? totalPaid : 0);
        }

        // 3. Filter Opportunities where the deposit amount has NOT been completely collected
        Set<Id> oppsNeedingTask = new Set<Id>();
        for (Opportunity opp : overdueCandidates) {
            Decimal requiredDeposit = oppToDepositRequired.get(opp.Id);
            if (requiredDeposit == null || requiredDeposit <= 0) {
                requiredDeposit = opp.Token_Amount__c != null ? opp.Token_Amount__c : 0;
            }

            Decimal totalPaid = oppToTotalPaid.containsKey(opp.Id) ? oppToTotalPaid.get(opp.Id) : 0;

            Boolean isDepositCollected = false;
            if (requiredDeposit > 0) {
                isDepositCollected = (totalPaid >= requiredDeposit);
            } else {
                isDepositCollected = (totalPaid > 0);
            }

            if (!isDepositCollected) {
                oppsNeedingTask.add(opp.Id);
            }
        }

        if (oppsNeedingTask.isEmpty()) {
            return;
        }

        // 4. Check for existing open Tasks to avoid duplicate task creation
        Set<Id> oppsWithExistingTask = new Set<Id>();
        for (Task existingTask : [
            SELECT Id, WhatId
            FROM Task
            WHERE WhatId IN :oppsNeedingTask
              AND Subject = 'Deposit Amount Overdue'
              AND Status != 'Completed'
        ]) {
            oppsWithExistingTask.add(existingTask.WhatId);
        }

        // 5. Lookup Task Master for 'Deposit Amount Overdue'
        Id taskMasterId = null;
        List<Task_Master__c> taskMasters = [
            SELECT Id
            FROM Task_Master__c
            WHERE Task_Subject__c = 'Deposit Amount Overdue'
              AND Object_Type__c = 'Opportunity'
              AND IsActive__c = true
            LIMIT 1
        ];
        if (!taskMasters.isEmpty()) {
            taskMasterId = taskMasters[0].Id;
        }

        // 6. Create Tasks for Sales Members
        List<Task> tasksToInsert = new List<Task>();
        for (Opportunity opp : overdueCandidates) {
            if (oppsNeedingTask.contains(opp.Id) && !oppsWithExistingTask.contains(opp.Id)) {
                Task overdueTask = new Task();
                overdueTask.Subject = 'Deposit Amount Overdue';
                overdueTask.WhatId = opp.Id;
                overdueTask.OwnerId = opp.Sales_Member__c != null ? opp.Sales_Member__c : opp.OwnerId;
                overdueTask.ActivityDate = todayDate;
                overdueTask.Status = 'Open';
                overdueTask.Priority = 'High';
                if (taskMasterId != null) {
                    overdueTask.Task_Master__c = taskMasterId;
                }
                tasksToInsert.add(overdueTask);
            }
        }

        if (!tasksToInsert.isEmpty()) {
            insert tasksToInsert;
            System.debug('Created ' + tasksToInsert.size() + ' Deposit Amount Overdue tasks.');
        }
    }

    global void finish(Database.BatchableContext BC) {
        System.debug('BatchForDepositCollectionReminder batch job finished.');
    }

    global void execute(SchedulableContext SC) {
        Database.executeBatch(new BatchForDepositCollectionReminder(), 200);
    }
}