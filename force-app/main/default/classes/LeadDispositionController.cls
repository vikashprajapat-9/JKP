public with sharing class LeadDispositionController {

    @AuraEnabled(cacheable=true)
    public static List<Call_Disposition__c> getDispositions(Id leadId) {

        return [
            SELECT Id,
                    Name,
                    
                    Subject__c,
                    Description__c,
                    Call_Disposition__c,
                    CreatedDate,
                    Owner.Name
            FROM Call_Disposition__c
            WHERE Lead__c = :leadId
            ORDER BY CreatedDate DESC
        ];
    }

    @AuraEnabled
    public static Call_Disposition__c saveDisposition(
        Id leadId,
        String subject,
        String description,
        String disposition
    ) {

        Call_Disposition__c cd = new Call_Disposition__c();

        cd.Lead__c = leadId;
        cd.Subject__c = subject;
        cd.Description__c = description;
        cd.Call_Disposition__c = disposition;

        insert cd;

        return cd;
    }
}