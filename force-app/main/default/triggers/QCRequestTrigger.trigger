trigger QCRequestTrigger on QC_Request__c (before update,after update) {
    if (Trigger.isBefore && Trigger.isUpdate) {
        QCRequestTriggerHandler.handleBeforeUpdate(Trigger.new,Trigger.oldMap);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        QCRequestTriggerHandler.handleAfterUpdate(Trigger.new,Trigger.oldMap);
    }
}