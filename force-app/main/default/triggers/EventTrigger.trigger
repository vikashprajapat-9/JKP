trigger EventTrigger on Lead_Duplicate_Event__e (after insert) {
    Set<Id> existingLeadIds = new Set<Id>();
    for (Lead_Duplicate_Event__e e : Trigger.new) {
        if (e.Existing_Lead_Id__c != null) {
            existingLeadIds.add((Id) e.Existing_Lead_Id__c);
        }
    }
    if (existingLeadIds.isEmpty()) return;

    Map<Id, Lead> existingLeads = new Map<Id, Lead>(
        [SELECT Id, LeadSource, Lead_Sub_Source__c,IsConverted,Multi_Channel_Engaged__c,ConvertedOpportunityId FROM Lead WHERE Id IN :existingLeadIds]
    );

    List<Re_Enquiry__c> reEnquiries = new List<Re_Enquiry__c>();
    Map<Id, Lead> leadsToUpdate = new Map<Id, Lead>();

    for (Lead_Duplicate_Event__e e : Trigger.new) {
        Lead existingLead = existingLeads.get((Id) e.Existing_Lead_Id__c);
        if (existingLead == null) continue;
        Re_Enquiry__c enquiry = new Re_Enquiry__c();
        if(existingLead.IsConverted){
            enquiry.Opportunity__c = existingLead.ConvertedOpportunityId;
        }else{
            enquiry.Lead__c = existingLead.Id;
        }
        enquiry.Re_Enquiry_Source__c = e.New_Lead_Source__c;
        enquiry.Re_Enquiry_Sub_Source__c = e.New_Lead_Sub_Source__c;
        enquiry.Enquiry_DateTime__c = System.now();
        enquiry.Source_Match__c = (existingLead.LeadSource == e.New_Lead_Source__c) ? 'Same Source' : 'New Source';
        enquiry.Sub_Source_Match__c = (existingLead.Lead_Sub_Source__c == e.New_Lead_Sub_Source__c) ? 'Same Sub Source' : 'New Sub Source';
        reEnquiries.add(enquiry);

        if (existingLead.LeadSource != e.New_Lead_Source__c) {
            existingLead.Multi_Channel_Engaged__c = true;
            leadsToUpdate.put(existingLead.Id, existingLead);
        }
    }

    if (!reEnquiries.isEmpty()) insert reEnquiries;
    if (!leadsToUpdate.isEmpty()) update leadsToUpdate.values();
}