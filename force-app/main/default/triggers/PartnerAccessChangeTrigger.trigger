// Applies decided Partner Access Requests (PartnerAccessRequestService.applyDecisions); it runs as the user of its
// PlatformEventSubscriberConfig
trigger PartnerAccessChangeTrigger on Partner_Access_Change__e (after insert) {
    PartnerAccessRequestService.applyDecisions(Trigger.new);
}