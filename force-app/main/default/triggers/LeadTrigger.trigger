trigger LeadTrigger on Lead (before insert, before update) {
    LeadTriggerHandler.beforeInsertUpdate(Trigger.new,Trigger.oldMap,Trigger.isInsert,Trigger.isUpdate);
}