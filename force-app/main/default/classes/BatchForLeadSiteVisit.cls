global class BatchForLeadSiteVisit implements Database.Batchable<SObject> {
    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id,OwnerId,Lead_Assigned_Date_Time__c FROM Lead WHERE Lead_Assigned_Date_Time__c <= :System.now().addDays(-60)
            AND IsConverted = false
        ]);
    }
    global void execute(Database.BatchableContext bc, List<Lead> scope) {
        Set<Id> leadIds = new Set<Id>();
        for (Lead l : scope) {
            leadIds.add(l.Id);
        }
        // Leads that already have a Visit
        Set<Id> visitedLeadIds = new Set<Id>();
        for (Visit__c visit : [ SELECT Lead__c FROM Visit__c WHERE Lead__c IN :leadIds
        ]) {
            visitedLeadIds.add(visit.Lead__c);
        }
        Group marketingQueue = [ SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = 'Marketing_Queue' LIMIT 1 ];

        List<Lead> leadsToUpdate = new List<Lead>();
        for (Lead l : scope) {
            // No Visit record found
            if (!visitedLeadIds.contains(l.Id)) {
                l.OwnerId = marketingQueue.Id;
                leadsToUpdate.add(l);
            }
        }

        if (!leadsToUpdate.isEmpty()) {
            update leadsToUpdate;
        }
    }

    global void finish(Database.BatchableContext bc) {
        System.debug('Lead Site Visit Batch Completed');
    }
}