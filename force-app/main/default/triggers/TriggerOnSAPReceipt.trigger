trigger TriggerOnSAPReceipt on SAP_Receipt__c (after insert) {
    if(Trigger.isAfter && Trigger.isInsert){//&& Trigger.isInsert
        // receiptTriggerHandler.generateDoc(Trigger.new, Trigger.oldMap);
        ReceiptTriggerHandler.updtRcpdAmtOnPymntSchedule(Trigger.new, Trigger.oldMap);
    }
}