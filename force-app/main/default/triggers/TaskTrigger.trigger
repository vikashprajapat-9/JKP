trigger TaskTrigger on Task (after insert, after update) {
    TaskTriggerHandler.handleAfter(Trigger.new,Trigger.oldMap,Trigger.isInsert,Trigger.isUpdate);
    
    // added by nazir   
    if (Trigger.isAfter && Trigger.isUpdate) {
        CaseDOAHandler.handleTaskCompletion(Trigger.new, Trigger.oldMap);
    }
}