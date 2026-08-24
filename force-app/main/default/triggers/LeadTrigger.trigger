trigger LeadTrigger on Lead (before insert, before update, after insert, after update) {  
    if (Trigger.isBefore) {
        LeadTriggerHandler.beforeInsertUpdate( Trigger.new,Trigger.oldMap,Trigger.isInsert, Trigger.isUpdate );
    }

    if (Trigger.isAfter) {
        LeadTriggerHandler.afterInsertUpdate(  Trigger.new,Trigger.oldMap, Trigger.isInsert, Trigger.isUpdate );
    }
}