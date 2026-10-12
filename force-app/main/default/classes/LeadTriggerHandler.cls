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
            // A channel partner's lead belongs to the CP, not to a pre-sales member: it only moves to Assigned
            // (LeadLogicController.prepareChannelPartnerLeads)
            if(ld.OwnerId != null && String.valueOf(ld.OwnerId).startsWith('005') && !LeadLogicController.isChannelPartnerLead(ld)){
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
            // Channel partner leads follow their own rules (LeadLogicController, CHANNEL PARTNER LEADS); the
            // duplicate check below is for the other leads
            LeadLogicController.prepareChannelPartnerLeads(newLeads);
            // A lead saved for a channel partner starts its Lead Freezing Window
            PartnerLeadFreeze.beforeInsert(newLeads);
            List<Lead> otherLeads = new List<Lead>();
            for (Lead ld : newLeads) {
                if (!LeadLogicController.isChannelPartnerLead(ld)) {
                    otherLeads.add(ld);
                }
            }
            LeadLogicController.checkDuplicateLead(otherLeads);
        }
        if (isUpdate) {
            // A CP lead approved after another CP won its customer is lost, not Assigned; a lost lead stays closed
            LeadLogicController.settleApprovedChannelPartnerLeads(newLeads, oldMap);
            LeadLogicController.keepLostLeadsClosed(newLeads, oldMap);
            // A channel partner lead that reached the hand-over stage (Visited) goes to the JKP CP team
            PartnerLeadHandover.beforeUpdate(newLeads, oldMap);
            // A lost lead's owner is frozen; a lead approved for, or given to, a channel partner starts its freezing window
            PartnerLeadFreeze.beforeUpdate(newLeads, oldMap);
        }
    }
    public static void afterInsertUpdate(List<Lead> newLeads, Map<Id, Lead> oldMap,Boolean isInsert, Boolean isUpdate) {
        if(newLeads.isEmpty()) {
            System.debug('Lead List is Empty!');
            return;
        }
        // Channel partner leads held for approval are submitted; a lead that cannot be submitted is not saved
        if (isInsert) {
            LeadLogicController.submitChannelPartnerApprovals(newLeads);
        }
        List<Lead> savedLeads = new List<Lead>();
        for (Lead lead : newLeads) {
            if (!lead.hasErrors()) {
                savedLeads.add(lead);
            }
        }
        // A converted lead settles its customer for the channel partners; a CP lead approved as lost is closed
        if (isUpdate) {
            LeadLogicController.applyConversionRule(savedLeads, oldMap);
            LeadLogicController.closeLeadsLostOnApproval(savedLeads, oldMap);
            // The JKP CP team is told about the leads handed over; converted leads' documents follow the customer
            PartnerLeadHandover.afterUpdate(savedLeads, oldMap);
        }
        List<Lead> leadsToSendmail  = new List<Lead>();
        List<Task> tasksToCreate = new List<Task>();
        // Which owners of leads just Qualified are partner users, in one query (no Qualified task for their leads)
        if (isUpdate) {
            Set<Id> qualifiedOwners = new Set<Id>();
            for (Lead lead : savedLeads) {
                Lead oldLead = oldMap.get(lead.Id);
                if (oldLead != null && lead.Status == 'Qualified' && oldLead.Status != 'Qualified') {
                    qualifiedOwners.add(lead.OwnerId);
                }
            }
            partnerWebPortalLeadEditController.loadOwners(qualifiedOwners);
        }
        for(Lead lead : savedLeads){
            if(isInsert){
                if(lead.OwnerId !=null && String.valueOf(lead.OwnerId).startsWith('005') && !LeadLogicController.isChannelPartnerLead(lead)){
                    leadsToSendmail.add(lead);
                }
            }else if(isUpdate){
                Lead oldLead = oldMap.get(lead.Id);
                if(oldLead != null && (lead.OwnerId != oldLead.OwnerId) && String.valueOf(lead.OwnerId).startsWith('005')){
                    leadsToSendmail.add(lead);
                }
            }
             // Create Task when Lead Status changes to Qualified; not for a lead a channel partner works on the portal (a
             // partner user owns it): the partner requests the site visit there, and the task would go to a partner user
            if (isUpdate) {
                Lead oldLead = oldMap.get(lead.Id);
                if (oldLead != null && lead.Status == 'Qualified' && oldLead.Status != 'Qualified'
                        && !partnerWebPortalLeadEditController.isPartnerUser(lead.OwnerId)) {
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
            Database.insert(tasksToCreate, AccessLevel.SYSTEM_MODE);
        }
        // A new channel partner lead has no pre-sales assignment to record
        List<Lead> historyLeads = new List<Lead>();
        for (Lead lead : savedLeads) {
            if (!isInsert || !LeadLogicController.isChannelPartnerLead(lead)) {
                historyLeads.add(lead);
            }
        }
        LeadLogicController.createLeadHistory(historyLeads,oldMap, isInsert);
    }
    
}