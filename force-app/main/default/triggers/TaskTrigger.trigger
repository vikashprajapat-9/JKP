trigger TaskTrigger on Task (after insert, after update) {
    TaskTriggerHandler.handleAfter(Trigger.new,Trigger.oldMap,Trigger.isInsert,Trigger.isUpdate);
}