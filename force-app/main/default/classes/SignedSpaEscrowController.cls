public with sharing class SignedSpaEscrowController {
    @AuraEnabled
    public static void updateSignedDates( Id opportunityId,Date spaSignedDate, Date escrowSignedDate ) {
        if (opportunityId == null) {
            throw new AuraHandledException('Opportunity Id is required.');
        }
        if (spaSignedDate == null) {
            throw new AuraHandledException('SPA Signed Date is required.');
        }
        Opportunity opp = [SELECT Id,SPA_Signed_Date__c,Escrow_Signed_Date__c FROM Opportunity WHERE Id = :opportunityId LIMIT 1  ];
        opp.SPA_Signed_Date__c = spaSignedDate;
        opp.Escrow_Signed_Date__c = escrowSignedDate;
        update opp;
    }
}