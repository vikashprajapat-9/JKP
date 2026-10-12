// Daily Site Visit Reminders (PartnerVisitReminders): a Salesforce notification to the channel partner agent on the day
// of each scheduled visit, and the day after for a visit that is not updated. Schedule it as an administrator, in the
// morning.
public without sharing class PartnerVisitReminderJob implements Database.Batchable<SObject>, Schedulable {

    public void execute(SchedulableContext context) {
        Database.executeBatch(new PartnerVisitReminderJob(), 100);
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        return PartnerVisitReminders.dueVisits();
    }

    public void execute(Database.BatchableContext context, List<Visit__c> scope) {
        PartnerVisitReminders.notify(scope);
    }

    public void finish(Database.BatchableContext context) {
    }
}