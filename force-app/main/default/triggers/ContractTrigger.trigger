// The agent contract process of channel partners (PartnerContractService): the CP Executive's stage changes. A new
// contract also gets its Documents (OneDrive folders inside the account folder; ContractDocumentService).
trigger ContractTrigger on Contract (after insert, before update, after update) {
    if (Trigger.isInsert) {
        ContractDocumentService.afterInsert(Trigger.new);
    } else if (Trigger.isBefore) {
        PartnerContractService.beforeUpdate(Trigger.new, Trigger.oldMap);
    } else {
        PartnerContractService.afterUpdate(Trigger.new, Trigger.oldMap);
    }
}