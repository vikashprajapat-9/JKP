/* Author      : Nazir_Patel
   Description : Daily batch runner that checks overdue Payment Schedules
                 and passes them to Case_DeedOfCancellation.
*/
public class PaymentScheduleDailyRun implements Database.Batchable<sObject>, Schedulable {

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new PaymentScheduleDailyRun(), 50);
    }

    // 1. Query schedules where Demand Letter was sent & money is strictly owed (> 0)
    public Database.QueryLocator start(Database.BatchableContext bc) {
        String query = 'SELECT Id, Demand_Letter_Sent__c, Total_Due_Amount__c, Demand_Letter_Sent_Date__c, '
                     + 'Opportunity__c, Opportunity__r.AccountId, '
                     + 'Opportunity__r.Project__r.Payment_Made_In_Days__c '
                     + 'FROM Payment_Schedule__c '
                     + 'WHERE Demand_Letter_Sent__c = true AND Total_Due_Amount__c > 0';
        return Database.getQueryLocator(query);
    }

    // 2. Filter records exceeding Project grace period and pass in bulk
    public void execute(Database.BatchableContext bc, List<Payment_Schedule__c> scope) {
        List<Payment_Schedule__c> overdueList = new List<Payment_Schedule__c>();

        for (Payment_Schedule__c p : scope) {
            if (p.Demand_Letter_Sent_Date__c == null || p.Opportunity__r?.Project__r?.Payment_Made_In_Days__c == null) {
                continue;
            }

            Integer daysAllowed = Integer.valueOf(p.Opportunity__r.Project__r.Payment_Made_In_Days__c);
            Integer daysPassed  = p.Demand_Letter_Sent_Date__c.daysBetween(Date.today());

            if (daysPassed > daysAllowed) {
                overdueList.add(p);
            }
        }

        if (!overdueList.isEmpty()) {
            Case_DeedOfCancellation.processOverdueSchedules(overdueList);
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('PaymentScheduleDailyRun completed successfully.');
    }
}