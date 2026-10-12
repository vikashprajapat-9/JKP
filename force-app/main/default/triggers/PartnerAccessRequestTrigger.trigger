// A Partner Access Request approved or rejected by its approval is passed on to be applied; a decided Lead Grace Period
// request moves its lead's Freezing Date on (approved) and the partner is emailed
trigger PartnerAccessRequestTrigger on Partner_Access_Request__c (after update) {
    PartnerAccessRequestService.requestsDecided(Trigger.new, Trigger.oldMap);
    PartnerLeadFreeze.graceDecided(Trigger.new, Trigger.oldMap);
}