trigger CommissionRateTrigger on Commission_Rate__c (before insert, before update, before delete, after insert, after update, after delete, after undelete) {
    CommissionTriggerHandler.rates(Trigger.operationType, Trigger.new, Trigger.oldMap);
}