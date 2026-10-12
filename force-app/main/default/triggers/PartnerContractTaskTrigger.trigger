// The agent contract process of channel partners (PartnerContractService): when the CP Manager closes the verification
// task of a contract draft, the contract is sent to the partner for signature
trigger PartnerContractTaskTrigger on Task (after update) {
    PartnerContractService.verificationTasksClosed(Trigger.new, Trigger.oldMap);
}