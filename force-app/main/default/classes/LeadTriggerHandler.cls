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
            leadsToScore.add(ld);
            phoneLeads.add(ld);
            if(ld.OwnerId != null && String.valueOf(ld.OwnerId).startsWith('005')){
                ld.Is_User_Assigned__c = true;
                ld.Pre_Sales_Team_Member__c = ld.OwnerId;
                ld.Lead_Assigned_Date_Time__c = Datetime.now();
                if(ld.Status == 'New'){
                    ld.Status = 'Assigned';
                }

            }
            continue;
        }
        Lead oldLead = oldMap.get(ld.Id);
			// if(
			// 	(ld.Lead_Sub_Source__c == 'Website Forms') && 
			// 	(ld.LeadSource != 'Digital') && 
			// 	(
			// 		!oldMap.containsKey(ld.Id) || 
			// 		(
			// 			ld.Designation__c != oldLead.Designation__c || 
			// 			ld.Purchase_Type__c != oldLead.Purchase_Type__c || 
			// 			ld.Time_to_Purchase__c != oldLead.Time_to_Purchase__c || 
			// 			ld.Budget_Aligned__c != oldLead.Budget_Aligned__c
			// 		)
			// 	)
			// ) {
			// 	leadsToScore.add(ld);
			// }
            if (ld.Phone != oldLead.Phone) {
                phoneLeads.add(ld);
            }
            if(ld.OwnerId != null && String.valueOf(ld.OwnerId).startsWith('005') && (ld.OwnerId != oldLead.OwnerId) && (oldLead.Status == 'New')){
                ld.Is_User_Assigned__c = true;
                ld.Pre_Sales_Team_Member__c = ld.OwnerId;
                ld.Lead_Assigned_Date_Time__c = Datetime.now();
                if(ld.Status == 'New'){
                    ld.Status = 'Assigned';
                }
            }
        }

        if (!leadsToScore.isEmpty()) {
            LeadLogicController.calculateLeadScore(leadsToScore);
        }
        if (!phoneLeads.isEmpty()) {
            LeadLogicController.normalizePhone(phoneLeads);
        }
        if (isInsert) {
            LeadLogicController.checkDuplicateLead(newLeads);
        }
    }
    public static void afterInsertUpdate(List<Lead> newLeads, Map<Id, Lead> oldMap,Boolean isInsert, Boolean isUpdate) {
        if(newLeads.isEmpty()) {
            System.debug('Lead List is Empty!');
            return;
        }
        List<Lead> leadsToSendmail  = new List<Lead>();
        List<Task> tasksToCreate = new List<Task>();
        for(Lead lead : newLeads){
            if(isInsert){
                if(lead.OwnerId !=null && String.valueOf(lead.OwnerId).startsWith('005')){
                    leadsToSendmail.add(lead);
                }
            }else if(isUpdate){
                Lead oldLead = oldMap.get(lead.Id);
                if(oldLead != null && (lead.OwnerId != oldLead.OwnerId) && String.valueOf(lead.OwnerId).startsWith('005')){
                    leadsToSendmail.add(lead);
                }
            }
             // Create Task when Lead Status changes to Qualified
            if (isUpdate) {
                Lead oldLead = oldMap.get(lead.Id);
                if (oldLead != null && lead.Status == 'Qualified' && oldLead.Status != 'Qualified') {
                    tasksToCreate.add(new Task(
                        Subject = 'Schedule a visit',
                        WhoId = lead.Id,
                        OwnerId = lead.OwnerId,
                        Status = 'Not Started',
                        Priority = 'Normal'
                    ));
                }
            }
    
        }
        if(!leadsToSendmail.isEmpty()){
            LeadLogicController.sendEmailToLeadOwnerOnAssignment(leadsToSendmail);
        }
        if (!tasksToCreate.isEmpty()) {
            insert tasksToCreate;
        }
        LeadLogicController.createLeadHistory(newLeads,oldMap, isInsert);
    }
    
}