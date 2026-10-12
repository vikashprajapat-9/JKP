trigger CaseTrigger on Case (after insert, after update) {
    if (Trigger.isAfter && Trigger.isInsert) {
        CaseDOAHandler.handleCases(Trigger.new);
        CaseDOAHandler.populateOpportunityFromUnit(Trigger.new, null);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        CaseDOAHandler.handleCases(Trigger.new);
        CaseDOAHandler.handleAfterApproval(Trigger.new, Trigger.oldMap);
        CaseDOAHandler.populateOpportunityFromUnit(Trigger.new, Trigger.oldMap);
    }
}