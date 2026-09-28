global class BatchForLeadFollowUpSLA implements Database.Batchable<SObject> {

    global Database.QueryLocator start(Database.BatchableContext bc) {
        Date yesterday = Date.today().addDays(-1);
        return Database.getQueryLocator([
            SELECT Id,WhoId,Subject,Status,ActivityDate FROM Task WHERE Subject = 'Lead Follow Up Call'
            AND ActivityDate = :yesterday AND WhoId != null
        ]);
    }
    global void execute( Database.BatchableContext bc,  List<Task> scope) {
        System.debug('BatchForLeadFollowUpSLA Started'  );
        System.debug( 'Task scope size = ' + scope.size());
        Set<Id> leadIds = new Set<Id>();
        for (Task task : scope) {
            if ( task.WhoId != null && String.valueOf(task.WhoId).startsWith('00Q')
            ) {
                leadIds.add(task.WhoId);
            }
        }

        if (leadIds.isEmpty()) {
            return;
        }
        Map<Id, Lead> leadMap = new Map<Id, Lead>([ SELECT Id,OwnerId,Follow_Up_Count__c, Lead_Follow_Up_DateTime__c
                FROM Lead WHERE Id IN :leadIds ]);
        Map<Id, Lead_Assignment_History__c> historyMap = new Map<Id, Lead_Assignment_History__c>();

        for (Lead_Assignment_History__c history : [
            SELECT Id, Lead__c, Lead_Assigned_To__c, OwnerId, SLA1__c,SLA2__c, CreatedDate
            FROM Lead_Assignment_History__c WHERE Lead__c IN :leadIds ORDER BY CreatedDate DESC
        ]) {
            if (!historyMap.containsKey(history.Lead__c)) {
                historyMap.put(history.Lead__c, history);
            }
        }

        List<Lead_Assignment_History__c> historiesToUpdate =  new List<Lead_Assignment_History__c>();

        Set<Id> notificationLeadIds =new Set<Id>();
        for (Task task : scope) {
            if (  task.WhoId == null || !String.valueOf(task.WhoId).startsWith('00Q')
            ) {
                continue;
            }

            Lead lead = leadMap.get(task.WhoId);
            if (lead == null) {
                continue;
            }

            Integer count =  lead.Follow_Up_Count__c == null  ? 0 : Integer.valueOf(lead.Follow_Up_Count__c);
            if (count > 4) {
                continue;
            }

            if (task.Status == 'Completed') {
                continue;
            }
            Lead_Assignment_History__c history =  historyMap.get(lead.Id);
            if (history == null) {
                System.debug( 'No assignment history found for Lead: ' + lead.Id);
                continue;
            }

            if (history.SLA2__c == true) {
                continue;
            }

            notificationLeadIds.add(lead.Id);
            history.SLA2__c = true;
            historiesToUpdate.add(history);
        }

        if (!historiesToUpdate.isEmpty()) {
            update historiesToUpdate;
            System.debug( 'SLA2 updated for ' +  historiesToUpdate.size() + ' assignment histories.' );
        }

        for (Id leadId : notificationLeadIds) {
            LeadEscalationHelper.sendSLA2Notification( leadId );
        }
    }

    global void finish(Database.BatchableContext bc) {
        System.debug('BatchForLeadFollowUpSLA Finished');
    }
}