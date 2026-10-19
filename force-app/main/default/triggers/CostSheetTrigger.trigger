trigger CostSheetTrigger on Cost_Sheet__c (after update) {
    if (Trigger.isAfter && Trigger.isUpdate) {
        CostSheetGenerationController.handleApprovalStep(Trigger.new,Trigger.oldMap);
    }
}