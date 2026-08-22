public with sharing class LeadDispositionController {

    @AuraEnabled(cacheable=true)
    public static List<Call_Disposition__c> getDispositions(Id leadId) {

        return [
            SELECT Id,Name,Follow_Up_DateTime__c,Direction__c,Call_DateTime__c, Subject__c,Description__c,
                    Call_Disposition__c, CreatedDate,Owner.Name FROM Call_Disposition__c WHERE Lead__c = :leadId
            ORDER BY CreatedDate DESC
        ];
    }

    @AuraEnabled
    public static Call_Disposition__c saveDisposition(
        Id leadId,
        String subject,
        String description,
        String disposition,
        DateTime callDateTime,
        DateTime followUpDateTime,
        String lossReason,
        String otherLossReason,
        String purchasePurpose,
        String unitType,
        Integer unitSize,
        String purchaseTimeline,
        String assessBudget,
        String assessFinanceReadiness
    ) {

        Call_Disposition__c cd = new Call_Disposition__c();
        cd.Lead__c = leadId;
        cd.Subject__c = subject;
        cd.Description__c = description;
        cd.Call_Disposition__c = disposition;
        cd.Call_DateTime__c = callDateTime;
        cd.Follow_Up_DateTime__c = followUpDateTime;
        system.debug('LeadDispositionController.saveDisposition: ' + cd);
        insert cd;
        
        Lead lead = new Lead(Id = leadId);

            if (disposition == 'In Discussion') {
                lead.Lead_Follow_Up_DateTime__c = followUpDateTime;
                lead.Status = 'In-Discussion';
            } else if (disposition == 'Not Reachable') {
                lead.Lead_Follow_Up_DateTime__c = followUpDateTime;
                lead.Status = 'Not Reachable';
            }
            if (disposition == 'Not Interested') {
                lead.Status = 'Not Interested';
                lead.Loss_Reason__c = lossReason;
                if(lossReason == 'Other'){
                    lead.Other_Loss_Reason__c = otherLossReason;
                }
                Group marketingQueue = [SELECT Id FROM Group  WHERE Type='Queue' AND DeveloperName='Marketing_Queue' LIMIT 1  ];
                lead.OwnerId = marketingQueue.Id;
            }
            if(disposition == 'Good Response') {
                lead.Status = 'Contacted';
                lead.Purchase_Purpose__c = purchasePurpose;
                lead.Unit_Type__c = unitType;
                lead.Unit_Size__c = unitSize;
                lead.Purchase_Timeline__c = purchaseTimeline;
                lead.Assess_Budget__c = assessBudget;
                lead.Assess_Finance_Readiness__c = assessFinanceReadiness;
            }

            if (lead.Status != null) {
                update lead;
            }
        return cd;
    }
}