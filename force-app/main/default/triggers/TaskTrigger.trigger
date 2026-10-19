trigger TaskTrigger on Task (after insert, after update) {
    if (Trigger.isAfter && Trigger.isInsert) {
    TaskTriggerHandler.handleAfter(Trigger.new,Trigger.oldMap,Trigger.isInsert,Trigger.isUpdate);
     //Case_SalesOrderCancellation.handleTaskAfterUpdate(Trigger.new, Trigger.oldMap);
    }
    // added by nazir   
    if (Trigger.isAfter && Trigger.isUpdate) {
        CaseDOAHandler.handleTaskCompletion(Trigger.new, Trigger.oldMap);
        Case_SalesOrderCancellation.handleTaskAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}