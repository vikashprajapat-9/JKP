public without sharing class SiteVisitController {
    //test

    public class SearchWrapper {
        @AuraEnabled
        public List<Lead> leads { get; set; }
        @AuraEnabled
        public List<Opportunity> opportunities { get; set; }
        public SearchWrapper() {
            leads = new List<Lead>();
            opportunities = new List<Opportunity>();
        }
    }

    @AuraEnabled(cacheable=true)
    public static SearchWrapper searchRecords(String searchKey){
        SearchWrapper wrapper = new SearchWrapper();
        if(String.isBlank(searchKey)){
            return wrapper;
        }
        String key = '%' + searchKey.trim() + '%';
        wrapper.leads = [ SELECT Id, Name, FirstName, LastName, Email, Phone, Normalised_Phone__c, Status
                            FROM Lead
                            WHERE IsConverted = FALSE
                            AND
                            (
                                Email LIKE :key
                                OR Normalised_Phone__c LIKE :key
                            )
                            ORDER BY LastModifiedDate DESC
                        ];
        wrapper.opportunities = [ SELECT Id, Name, Email__c, Phone__c, Normalised_Phone__c, StageName, Owner.Name FROM Opportunity
                                    WHERE
                                    (
                                        Email__c LIKE :key
                                        OR Normalised_Phone__c LIKE :key
                                    )
                                    ORDER BY LastModifiedDate DESC
                                ];
        return wrapper;
    }

    @AuraEnabled
    public static Id createVisit(String leadId, String opportunityId, Visit__c visit){
        if(visit == null){
            throw new AuraHandledException('Visit cannot be null.');
        }
        if(leadId == null && opportunityId == null){
            throw new AuraHandledException('Please select a Lead or Opportunity.');
        }
        if(opportunityId != null){
            visit.Opportunity__c = opportunityId;
        }
        insert visit;
        return visit.Id;
    }
}