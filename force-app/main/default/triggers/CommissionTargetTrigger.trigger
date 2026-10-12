trigger CommissionTargetTrigger on Commission_Target__c (before insert, before update, before delete) {
    CommissionTargetService.rows(Trigger.operationType, Trigger.new, Trigger.oldMap);
}