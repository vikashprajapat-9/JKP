public without sharing class ReceiptTriggerHandler {

    private static final Map<String, String> RECEIPT_TYPE_TO_PS_TYPE = new Map<String, String>{
        'Final Receipt' => 'Agreement', 'Provisional' => 'Agreement', 'TDS' => 'Agreement',
        'Others' => 'Ammenities'
    };

    public static void updtRcpdAmtOnPymntSchedule(List<SAP_Receipt__c> newRecords, Map<Id, SAP_Receipt__c> oldMap) {
        System.debug('newRecords==>'+newRecords);
        System.debug('oldMap==>'+oldMap);
        if(newRecords == null || newRecords.isEmpty()){
            return;
        }

        Map<Id, SAP_Receipt__c> oppToReceiptMap = new Map<Id, SAP_Receipt__c>();
        Set<Id> oppIdsForWelcomeLetter = new Set<Id>();
        Set<Id> receiptIds = new Set<Id>();

        for(SAP_Receipt__c rcpt : newRecords){
            System.debug('rcpt===>');
            SAP_Receipt__c oldRcpt = oldMap != null ? oldMap.get(rcpt.Id) : null;
           // system.debug('rcpt.Approval_Status__c::'+rcpt.Approval_Status__c + ':::oldRcpt.Approval_Status__c::'+ oldRcpt.Approval_Status__c);
            if(rcpt.Amount__c  != null && rcpt.Amount__c  > 0 && oldRcpt != null  && rcpt.Opportunity__c != null && RECEIPT_TYPE_TO_PS_TYPE.containsKey(rcpt.Type__c) ) { //&& rcpt.Approval_Status__c != oldRcpt.Approval_Status__c && rcpt.Approval_Status__c == 'Approved'
                System.debug('enter the condition');
                oppToReceiptMap.put(rcpt.Opportunity__c, rcpt);
                oppIdsForWelcomeLetter.add(rcpt.Opportunity__c);
                receiptIds.add(rcpt.Id);
            }
        }

        if(oppToReceiptMap.isEmpty()){
            return;
        }

        Map<Id, Decimal> receiptIdToAllocatedAmount = new Map<Id, Decimal>();
        for (AggregateResult result : [
            SELECT SAP_Receipt__c receiptId, SUM(Amount_Contributed__c) allocatedAmount
            FROM Receipt_Payment_Schedule_Link__c
            WHERE SAP_Receipt__c IN :receiptIds
            GROUP BY SAP_Receipt__c
        ]) {
            receiptIdToAllocatedAmount.put(
                (Id) result.get('receiptId'),
                (Decimal) result.get('allocatedAmount')
            );
        }

        List<Payment_Schedule__c> paymentSchedules = [SELECT Id, Agreement_Value__c, Total_Amount_Inclusive_Of_Tax__c, Opportunity__c, Tax_Amount__c, Installment_Sequence__c,
                Total_Received_Amount__c, Total_Due_Amount__c, Type__c
            FROM Payment_Schedule__c
            WHERE Opportunity__c IN :oppToReceiptMap.keySet() AND Type__c IN ('Agreement', 'Ammenities') and Installment_Sequence__c != null
            ORDER BY Installment_Sequence__c
        ];
        if(paymentSchedules.isEmpty()){
            return;
        }

        Map<Id, List<Payment_Schedule__c>> oppToPaymentSchedules = new Map<Id, List<Payment_Schedule__c>>();
        for(Payment_Schedule__c ps : paymentSchedules) {
            if(!oppToPaymentSchedules.containsKey(ps.Opportunity__c)){
                oppToPaymentSchedules.put(ps.Opportunity__c, new List<Payment_Schedule__c>());
            }
            oppToPaymentSchedules.get(ps.Opportunity__c).add(ps);
        }

        Map<Id, Payment_Schedule__c> psIdToUpdate = new Map<Id, Payment_Schedule__c>();
        List<Receipt_Payment_Schedule_Link__c> linksToInsert = new List<Receipt_Payment_Schedule_Link__c>();
        for(SAP_Receipt__c rcpt : oppToReceiptMap.values()){
            Decimal rcptAmt = (rcpt.Amount__c  == null ? 0 : rcpt.Amount__c ) -
                (receiptIdToAllocatedAmount.containsKey(rcpt.Id) ? receiptIdToAllocatedAmount.get(rcpt.Id) : 0);
            String targetPsType = RECEIPT_TYPE_TO_PS_TYPE.get(rcpt.Type__c);
            System.debug('rcptAmt==>'+rcptAmt + ':::targetPsType==>'+targetPsType);
            List<Payment_Schedule__c> psList = oppToPaymentSchedules.get(rcpt.Opportunity__c);
            if(psList == null || psList.isEmpty() || rcptAmt <= 0){
                continue;
            }
            for(Payment_Schedule__c ps : psList){
                Decimal currentDueAmount = ps.Total_Due_Amount__c == null ? 0 : ps.Total_Due_Amount__c;
                if(ps.Type__c != targetPsType || rcptAmt <= 0 || currentDueAmount <= 0) {
                    continue;
                }

                // Decimal contributionAmount = Math.min(rcptAmt, currentDueAmount);
                // ps.Total_Received_Amount__c = (contributionAmount == currentDueAmount) ? ps.Total_Amount_Inclusive_Of_Tax__c : ((ps.Total_Received_Amount__c != null ? ps.Total_Received_Amount__c : 0) + contributionAmount);
                
                // rcptAmt -= contributionAmount;
                // System.debug('rcptAmt after contribution==>'+rcptAmt);

                // psIdToUpdate.put(ps.Id, ps);
                // linksToInsert.add(new Receipt_Payment_Schedule_Link__c(
                //     SAP_Receipt__c = rcpt.Id,
                //     Payment_Schedule__c = ps.Id,
                //     Amount_Contributed__c = contributionAmount,
                //     Receipt_Type__c = rcpt.Type__c,
                //     Adjustment_Type__c = 'Added'
                // ));
                // if(rcptAmt == 0){
                //     break;
                // }

                Decimal contributionAmount = Math.min(rcptAmt, currentDueAmount);
                Decimal existingReceivedAmount = ps.Total_Received_Amount__c == null ? 0 : ps.Total_Received_Amount__c;
                Decimal newReceivedAmount;
                if (contributionAmount == currentDueAmount) {
                    newReceivedAmount = ps.Total_Amount_Inclusive_Of_Tax__c;
                } else {
                    newReceivedAmount = existingReceivedAmount + contributionAmount;
                }
                System.debug('Payment Schedule Id = ' + ps.Id);
                System.debug('Existing Received Amount = ' + existingReceivedAmount);
                System.debug('Current Due Amount = ' + currentDueAmount);
                System.debug('Receipt Amount Remaining = ' + rcptAmt);
                System.debug('Contribution Amount = ' + contributionAmount);
                System.debug('New Received Amount = ' + newReceivedAmount);

                Payment_Schedule__c psUpdate = new Payment_Schedule__c(Id = ps.Id,Total_Received_Amount__c = newReceivedAmount);
                psIdToUpdate.put(ps.Id, psUpdate);
                linksToInsert.add(
                    new Receipt_Payment_Schedule_Link__c(
                        SAP_Receipt__c = rcpt.Id,
                        Payment_Schedule__c = ps.Id,
                        Amount_Contributed__c = contributionAmount,
                        Receipt_Type__c = rcpt.Type__c,
                        Adjustment_Type__c = 'Added'
                    )
                );
                rcptAmt -= contributionAmount;
                System.debug('Remaining Receipt Amount = ' + rcptAmt);
                if (rcptAmt == 0) {
                    break;
                }
            }
        }

        if(!psIdToUpdate.isEmpty()){
            update psIdToUpdate.values();
            System.debug('psToUpdate===>'+psIdToUpdate.values());
            System.debug('Payment Schedule records updated successfully');
        }

        if(!linksToInsert.isEmpty()){
            insert linksToInsert;
            System.debug('Receipt Payment Schedule Link records inserted successfully');
        }

        if (!oppIdsForWelcomeLetter.isEmpty()) {
            System.debug('oppIdsForWelcomeLetter => ' + oppIdsForWelcomeLetter);

            List<Opportunity> oppsToQueue = [SELECT Id, Welcome_Letter_Sent_Date__c FROM Opportunity WHERE Id IN :oppIdsForWelcomeLetter AND Welcome_Letter_Sent_Date__c = NULL];
            System.debug('oppsToQueue => ' + oppsToQueue);

            for (Opportunity o : oppsToQueue) {
                if (!Test.isRunningTest()) {
                    //System.enqueueJob(new QueueableToGenerateWelcomeLetter(o.Id));
                } else {
                    System.debug('Test context: skipping enqueue for Opp => ' + o.Id);
                }
            }
        }
    }
}