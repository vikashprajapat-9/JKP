public with sharing class DepositOverdueController {
    @AuraEnabled
    public static void revokeOfferLetter(Id opportunityId) {
        if (opportunityId == null) {
            throw new AuraHandledException('Opportunity Id is required.');
        }
        try {
            List<SObject> recordsToUpdate = new List<SObject>();
            Opportunity opp = [SELECT Id, Unit__c FROM Opportunity WHERE Id = :opportunityId LIMIT 1];
            opp.StageName ='Cancelled';
            opp.CloseDate = Date.today();
            recordsToUpdate.add(opp);

            if (opp.Unit__c != null) {
                Unit__c unitRec = [ SELECT Id, Status__c FROM Unit__c WHERE Id = :opp.Unit__c LIMIT 1 ];
                unitRec.Status__c = 'Z0';
                recordsToUpdate.add(unitRec);
            }
            List<Escrow_Account__c> escrowAccounts = [SELECT Id, Status__c FROM Escrow_Account__c WHERE Opportunity__c = :opp.Id];
            for (Escrow_Account__c escrow : escrowAccounts) {
                escrow.Status__c = False;
                recordsToUpdate.add(escrow);
            }

            if (!recordsToUpdate.isEmpty()) {
                update recordsToUpdate;
            }

        } catch (Exception e) {
            throw new AuraHandledException( 'Unable to revoke offer letter: ' + e.getMessage());
        }
    }
    @AuraEnabled
    public static void requestTimeExtension(Id opportunityId) {
            System.debug('Opportunity Id: ' + opportunityId);
        if (opportunityId == null) {
            throw new AuraHandledException('Opportunity Id is required.');
        }
        try {
            Opportunity opp = [ SELECT Id, Extended_Deposit_Date__c, Number_Of_Extension__c FROM Opportunity WHERE Id = :opportunityId LIMIT 1];
            System.debug('Opportunity: ' + opp);
            System.debug('Existing Extension Count: ' + opp.Number_Of_Extension__c);
            Integer currentCount = 0;
            if (opp.Number_Of_Extension__c != null) {
                currentCount = opp.Number_Of_Extension__c.intValue();
            }
            if (currentCount >= 3) {
                throw new AuraHandledException('Maximum 3 time extensions are already requested.');
            }
            Integer newCount = currentCount + 1;
            System.debug('New Extension Count: ' + newCount);
            opp.Extended_Deposit_Date__c = Date.today();
            opp.Number_Of_Extension__c = newCount;
            update opp;
            System.debug('Extended Date: ' + opp.Extended_Deposit_Date__c);
            System.debug('Extension Count: ' + opp.Number_Of_Extension__c);
            String approvalProcessName;
            if (newCount == 1) {
                approvalProcessName = 'First_level_Extention';
            } else if (newCount == 2) {
                approvalProcessName = 'Second_level_Extention';
            } else if (newCount == 3) {
                approvalProcessName = 'Third_level_Extention';
            } else {
                throw new AuraHandledException('Invalid extension count.' );
            }
            //approval process submission
            Approval.ProcessSubmitRequest approvalRequest = new Approval.ProcessSubmitRequest();
            approvalRequest.setObjectId(opp.Id);
            approvalRequest.setProcessDefinitionNameOrId(approvalProcessName);
            approvalRequest.setComments('Deposit time extension requested. ' + 'Extension Count: ' + newCount + ', Extension Date: ' + String.valueOf(Date.today()));
            Approval.ProcessResult result = Approval.process(approvalRequest);
            if (!result.isSuccess()) {
                String errorMessage ='Unable to submit approval request.';
                if (result.getErrors() != null && !result.getErrors().isEmpty()) {
                    errorMessage = result.getErrors()[0].getMessage();
                }
                throw new AuraHandledException(errorMessage);
            }
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            System.debug('requestTimeExtension Error: ' + e.getMessage() + ' Line: ' + e.getLineNumber());
            throw new AuraHandledException('Unable to request time extension: ' + e.getMessage());
        }
    }
    @AuraEnabled
    public static void createReceipt( Id opportunityId,Decimal amount, String receiptType) {
        if (opportunityId == null) {
            throw new AuraHandledException('Opportunity Id is required.');
        }
        if (amount == null || amount <= 0) {
            throw new AuraHandledException('Please enter a valid Amount.');
        }
        if (String.isBlank(receiptType)) {
            throw new AuraHandledException('Please select Type.');
        }
        try {
            Receipt_Log__c receipt = new Receipt_Log__c();
            receipt.Opportunity__c = opportunityId;
            receipt.Amount__c = amount;
            receipt.Type__c =receiptType;
            insert receipt;

            Integer receiptCount = [SELECT COUNT() FROM Receipt_Log__c WHERE Opportunity__c = :opportunityId ];
            if (receiptCount == 1) {
                Task paymentTask = new Task();
                paymentTask.Subject ='Deposit Payment Confirmation';
                paymentTask.Status ='Not Started';
                paymentTask.Priority = 'Normal';
                paymentTask.WhatId = opportunityId;
              // paymentTask.Description = 'Auto-created when the first Receipt ' +'was generated. Finance to confirm ' + 'payment and mark the task Completed.';

                // List<Group> financeQueues = [ SELECT Id FROM Group WHERE Name = 'Finance' AND Type = 'Queue' LIMIT 1];
                // if (!financeQueues.isEmpty()) {
                //     paymentTask.OwnerId = financeQueues[0].Id;
                // }
                insert paymentTask;
            }
        } catch (Exception e) {
            System.debug('Create Receipt Error: ' + e.getMessage());
            System.debug( 'Line: ' + e.getLineNumber() );
            throw new AuraHandledException('Unable to create receipt: ' + e.getMessage());
        }
    }
}