public class OpportunityTriggerHandler {

    public static void handleBeforeUpdate(List<Opportunity> newOpps,Map<Id, Opportunity> oldMap) {
        List<Opportunity> opportunitiesToAssign = new List<Opportunity>();
        for (Opportunity opp : newOpps) {
            Opportunity oldOpp = oldMap.get(opp.Id);
            if (opp.StageName == 'SPA Creation' && oldOpp.StageName != 'SPA Creation') {
                opportunitiesToAssign.add(opp);
            }
        }
        if (opportunitiesToAssign.isEmpty()) {
            return;
        }
        List<Assignment_Group__c> assignmentGroups = [SELECT Id, Name,Supported_Sobject__c,Type__c,IsActive__c,Last_Allocated_RRid__c FROM Assignment_Group__c  WHERE IsActive__c = true AND Supported_Sobject__c = 'Opportunity' AND Name = 'Opportunity Assignment' LIMIT 1];

        if (assignmentGroups.isEmpty()) {
            System.debug('No active Opportunity Assignment Group found.');
            return;
        }
        Assignment_Group__c assignmentGroup = assignmentGroups[0];
        SobjectLoadAssignmentHelper.executeOpportunityAssignment(opportunitiesToAssign,assignmentGroup.Id);
    }
}