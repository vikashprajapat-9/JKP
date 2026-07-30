public with sharing class LeadTriggerHandler {
    public static void beforeInsertUpdate(List<Lead> newLeads, Map<Id, Lead> oldMap,Boolean isInsert, Boolean isUpdate) {
        List<Lead> scoreLeads = new List<Lead>();
        List<Lead> phoneLeads = new List<Lead>();
            for (Lead newLead : newLeads) {
                if (isInsert) {
					scoreLeads.add(newLead);
                    phoneLeads.add(newLead);
                    continue;
            }
            Lead oldLead = oldMap.get(newLead.Id);
            if (
                newLead.Designation__c != oldLead.Designation__c ||
                newLead.Purchase_Type__c != oldLead.Purchase_Type__c ||
                newLead.Time_to_Purchase__c != oldLead.Time_to_Purchase__c ||
                newLead.Budget_Aligned__c != oldLead.Budget_Aligned__c ||
                newLead.LeadSource != oldLead.LeadSource ||
                newLead.Lead_Sub_Source__c != oldLead.Lead_Sub_Source__c
            ) {
                scoreLeads.add(newLead);
            }

            if (newLead.Phone != oldLead.Phone) {
                phoneLeads.add(newLead);
            }
        }

        if (!scoreLeads.isEmpty()) {
            LeadLogicController.calculateLeadScore(scoreLeads);
        }

        if (!phoneLeads.isEmpty()) {
            LeadLogicController.normalizePhone(phoneLeads);
        }
    }
}