trigger CommissionStageTrigger on Commission_Stage__c (before insert, before update, before delete, after insert, after update, after delete, after undelete) {
    CommissionTriggerHandler.stages(Trigger.operationType, Trigger.new, Trigger.oldMap);
}