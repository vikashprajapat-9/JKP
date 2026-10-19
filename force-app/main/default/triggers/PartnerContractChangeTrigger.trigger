// Applies the agent contract steps that need an administrator (PartnerContractService.applyChanges); it runs as the user
// of its PlatformEventSubscriberConfig
trigger PartnerContractChangeTrigger on Partner_Contract_Change__e (after insert) {
    PartnerContractService.applyChanges(Trigger.new);
}