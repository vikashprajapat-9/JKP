trigger ProjectTrigger on Project__c (after insert) {
    if (Trigger.isAfter && Trigger.isInsert) {
        ProjectTriggerHandler.handleAfterInsert(Trigger.new);
    }
}