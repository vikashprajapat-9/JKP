public  class EscalatingToMarketingHeadBatch implements Database.Batchable<sObject> {
    public Database.QueryLocator start(Database.BatchableContext bc){
        Datetime thirtyMinutesAgo = Datetime.now().addMinutes(-30);
        String query = 'SELECT Id,Name FROM Lead WHERE Lead_Classification__c = \'Hot\' AND CreatedDate < \'thirtyMinutesAgo\'';
    }
}