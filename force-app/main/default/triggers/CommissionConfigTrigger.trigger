trigger CommissionConfigTrigger on Commission_Config__c (before insert, before update, before delete, after insert, after update, after undelete) {
    CommissionTriggerHandler.configs(Trigger.operationType, Trigger.new, Trigger.oldMap);
}