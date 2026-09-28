trigger OpportunityTrigger on Opportunity (before update) {
    if (Trigger.isBefore && Trigger.isUpdate) {
        OpportunityTriggerHandler.handleBeforeUpdate(Trigger.new,Trigger.oldMap );
    }
}