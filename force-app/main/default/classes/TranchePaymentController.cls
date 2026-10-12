public with sharing class TranchePaymentController {

    public class PaymentScheduleWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String paymentScheduleName;
        @AuraEnabled public String customerName;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public String unitName;
        @AuraEnabled public String floorName;
        @AuraEnabled public String blockName;
        @AuraEnabled public Decimal totalDueAmount;
        @AuraEnabled public Decimal totalAmountInclusiveOfTax;
        @AuraEnabled public Date dueDate;
        @AuraEnabled public Decimal installment;
        @AuraEnabled public String status;
    }

    @AuraEnabled(cacheable=true)
    public static List<PaymentScheduleWrapper> getPaymentSchedules() {
        Date today = Date.today();
        Date fifteenDaysFromToday = today.addDays(15);
        List<Payment_Schedule__c> schedules = [SELECT Id,Name,Installment__c,Due_Date__c,Payment_Scheme_Installment__r.Milestone_Completion_Date__c,Total_Due_Amount__c,
                Total_Amount_Inclusive_Of_Tax__c, Demand_Letter_Sent__c, Opportunity__c,Opportunity__r.Name,Opportunity__r.Account.Name,Opportunity__r.Unit__r.Name,Opportunity__r.Unit__r.Floor__r.Name, Opportunity__r.Unit__r.Floor__r.Block__r.Name
            FROM Payment_Schedule__c WHERE Total_Due_Amount__c != 0
            AND Payment_Scheme_Installment__r.Milestone_Completion_Date__c >= :today AND Payment_Scheme_Installment__r.Milestone_Completion_Date__c <= :fifteenDaysFromToday
            AND Demand_Letter_Sent__c = false ORDER BY Due_Date__c ASC];

        List<PaymentScheduleWrapper> result = new List<PaymentScheduleWrapper>();
        for (Payment_Schedule__c ps : schedules) {
            PaymentScheduleWrapper wrapper = new PaymentScheduleWrapper();
            wrapper.id = ps.Id;
            wrapper.paymentScheduleName = ps.Name;
            wrapper.installment = ps.Installment__c;
            wrapper.dueDate = ps.Due_Date__c;
            wrapper.totalDueAmount = ps.Total_Due_Amount__c;
            wrapper.totalAmountInclusiveOfTax = ps.Total_Amount_Inclusive_Of_Tax__c;
            wrapper.opportunityName = ps.Opportunity__r != null ? ps.Opportunity__r.Name : null;
            wrapper.customerName = ps.Opportunity__r != null && ps.Opportunity__r.Account != null? ps.Opportunity__r.Account.Name : null;
            wrapper.unitName = ps.Opportunity__r != null && ps.Opportunity__r.Unit__r != null ? ps.Opportunity__r.Unit__r.Name : null;
            wrapper.floorName = ps.Opportunity__r != null && ps.Opportunity__r.Unit__r != null && ps.Opportunity__r.Unit__r.Floor__r != null ? ps.Opportunity__r.Unit__r.Floor__r.Name : null;
            wrapper.blockName = ps.Opportunity__r != null && ps.Opportunity__r.Unit__r != null && ps.Opportunity__r.Unit__r.Floor__r != null && ps.Opportunity__r.Unit__r.Floor__r.Block__r != null ? ps.Opportunity__r.Unit__r.Floor__r.Block__r.Name : null;
            wrapper.status = 'Not Due';

            if (ps.Due_Date__c < today) {
                wrapper.status = 'Overdue';
            } else if (ps.Due_Date__c == today) {
                wrapper.status = 'Due Today';
            } else {
                wrapper.status = 'Due Soon';
            }
            result.add(wrapper);
        }
        return result;
    }

    @AuraEnabled
    public static void generateDemandLetters(List<Id> paymentScheduleIds) {
            if (paymentScheduleIds == null ||
                paymentScheduleIds.isEmpty()) {
                return;
            }
            List<Payment_Schedule__c> schedules = [SELECT Id,Demand_Letter_Sent__c,Demand_Letter_Sent_Date__c FROM Payment_Schedule__c WHERE Id IN :paymentScheduleIds];
            for (Payment_Schedule__c ps : schedules) {
                ps.Demand_Letter_Sent__c = true;
                ps.Demand_Letter_Sent_Date__c = System.today();
            }
            if (!schedules.isEmpty()) {
                update schedules;
            }
    }

}