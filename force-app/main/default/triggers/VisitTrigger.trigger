// Site visits:
//  - a channel partner's site visit request: the approvers' decisions set the visit's status, a request the JKP CP
//    Executive rejected goes to the CP Manager, and an approved one moves the lead to Site Visit Scheduled; a completed
//    visit moves its partner lead to Visited (PartnerSiteVisitService);
//  - when a visit is completed, the channel partner lead rules settle whose customer it is (CP -> CP, the first
//    successful site visit; LeadLogicController.applyFirstSiteVisitRule).
trigger VisitTrigger on Visit__c (before update, after insert, after update) {
    if (Trigger.isBefore) {
        PartnerSiteVisitService.beforeUpdate(Trigger.new, Trigger.oldMap);
        return;
    }
    if (Trigger.isUpdate) {
        PartnerSiteVisitService.afterUpdate(Trigger.new, Trigger.oldMap);
    } else {
        PartnerSiteVisitService.afterInsert(Trigger.new);
    }
    LeadLogicController.applyFirstSiteVisitRule(Trigger.new, Trigger.isUpdate ? Trigger.oldMap : null);
}