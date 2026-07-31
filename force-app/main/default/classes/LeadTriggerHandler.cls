public with sharing class LeadTriggerHandler {
    public static void beforeInsertUpdate(List<Lead> newLeads, Map<Id, Lead> oldMap,Boolean isInsert, Boolean isUpdate) {
		if(newLeads.isEmpty()) {
			System.debug('Lead List is Empty!');
			return;
		}
		List<Lead> leadsToScore = new List<Lead>();
        List<Lead> phoneLeads = new List<Lead>();
		for(Lead ld : newLeads) {
            if (isInsert) {
                scoreLeads.add(newLead);
                phoneLeads.add(newLead);
                continue;
            }
            Lead oldLead = oldMap.get(ld.Id);
			if(
				(ld.Lead_Sub_Source__c == 'Website Forms') && 
				(ld.LeadSource != 'Digital Source') && 
				(
					!oldMap.containsKey(ld.Id) || 
					(
						ld.Designation__c != oldLead.Designation__c || 
						ld.Purchase_Type__c != oldLead.Purchase_Type__c || 
						ld.Time_to_Purchase__c != oldLead.Time_to_Purchase__c || 
						ld.Budget_Aligned__c != oldLead.Budget_Aligned__c
					)
				)
			) {
				leadsToScore.add(ld);
			}
            if (ld.Phone != oldLead.Phone) {
                phoneLeads.add(ld);
            }
        }

        if (!leadsToScore.isEmpty()) {
            LeadLogicController.calculateLeadScore(leadsToScore);
        }

        if (!phoneLeads.isEmpty()) {
            LeadLogicController.normalizePhone(phoneLeads);
        }
    }
}